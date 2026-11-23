import Foundation

enum PermissionErrorType: Equatable {
    case microphone
    case systemAudio
    case both
}

@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published var statusMessage = "آماده"
    @Published var permissionError: PermissionErrorType? = nil
    @Published var isActive = false
    @Published var selectedLanguage: String? = AppSettings.selectedLanguage
    @Published var audioSource: AudioSourceMode = AppSettings.audioSource {
        didSet {
            if permissionError == .systemAudio && audioSource == .microphone {
                permissionError = nil
            }
        }
    }

    let micCapture = AudioCaptureService()
    let systemCapture = SystemAudioCaptureService()
    let whisperEngine = WhisperEngine()
    let transcriptStore: TranscriptStore

    private let audioMixer = AudioMixer()
    private let vad = VADDetector()

    private var pcmBuffer = Data()
    /// Minimum chunk: ~2.0 sec (need ≥ 1.5s for reliable Whisper processing)
    private let minChunkBytes = 16000 * 2 * 2
    /// Maximum chunk: ~8.0 sec to avoid high latency and memory overhead
    private let maxChunkBytes = 16000 * 2 * 8

    private var wasSpeaking = false
    private var totalBytesProcessed: Int = 0
    private var recentTranscriptContext: String = ""

    // Speaker tracking energies
    private var recentMicEnergy: Float = 0
    private var recentSystemEnergy: Float = 0
    private var currentChunkSpeaker: SpeakerType = .unknown

    /// Streaming file handle and state for disk-backed audio recording (0 MB RAM overhead)
    private var recordingFileHandle: FileHandle?
    private var recordingFileURL: URL?
    private var totalAudioBytesWritten: Int64 = 0
    private var audioChunkCount = 0

    /// Serial execution queue for in-flight audio transcription chunks
    private struct TranscriptionJob {
        let data: Data
        let speaker: SpeakerType
        let startTime: Double
        let endTime: Double
        let sessionID: UUID?
    }

    private var jobContinuation: AsyncStream<TranscriptionJob>.Continuation?
    private var workerTask: Task<Void, Never>?
    private var activeSessionID: UUID?

    // MARK: - Hourly Meeting Confirmation
    @Published var isHourlyConfirmationActive = false
    @Published var hourlyConfirmationHours = 1
    @Published var autoStopCountdownSeconds = 300 // 5 minutes

    private var recordingStartTime: Date?
    private var nextHourlyCheckSeconds: TimeInterval = 3600
    private var hourlyMonitoringTimer: Timer?
    private var autoStopCountdownTimer: Timer?

    init(transcriptStore: TranscriptStore) {
        self.transcriptStore = transcriptStore
    }

    func prepareModel() async {
        let modelSize = AppSettings.whisperModelSize
        if !whisperEngine.isModelLoaded || whisperEngine.modelName != modelSize.rawValue {
            if ModelManager.shared.isModelDownloaded(modelSize) {
                statusMessage = "بارگذاری مدل \(modelSize.rawValue)..."
                await whisperEngine.loadModel(size: modelSize)
                statusMessage = whisperEngine.isModelLoaded ? "آماده" : (whisperEngine.loadError ?? "خطا")
            } else {
                statusMessage = "مدل دانلود نشده است"
            }
        }
    }

    private func wireAudioCallbacks(for mode: AudioSourceMode) {
        micCapture.onAudioData = nil
        systemCapture.onAudioData = nil
        audioMixer.reset()

        switch mode {
        case .microphone:
            micCapture.onAudioData = { [weak self] data in
                Task { @MainActor in
                    self?.handleAudioChunk(data, sourceSpeaker: .user)
                }
            }
        case .systemAudio:
            systemCapture.onAudioData = { [weak self] data in
                Task { @MainActor in
                    self?.handleAudioChunk(data, sourceSpeaker: .system)
                }
            }
        case .both:
            micCapture.onAudioData = { [weak self] data in
                let energy = VADDetector.calculateRMS(data)
                Task { @MainActor in
                    self?.recentMicEnergy = energy
                }
                self?.audioMixer.appendMic(data)
            }
            systemCapture.onAudioData = { [weak self] data in
                let energy = VADDetector.calculateRMS(data)
                Task { @MainActor in
                    self?.recentSystemEnergy = energy
                }
                self?.audioMixer.appendSystem(data)
            }
            audioMixer.onMixedData = { [weak self] data in
                Task { @MainActor in
                    guard let self else { return }
                    // Determine dominant speaker in dual mode
                    let speaker: SpeakerType
                    if self.recentMicEnergy > self.recentSystemEnergy * 1.25 && self.recentMicEnergy > 0.015 {
                        speaker = .user
                    } else if self.recentSystemEnergy > self.recentMicEnergy * 1.25 && self.recentSystemEnergy > 0.015 {
                        speaker = .system
                    } else {
                        speaker = self.currentChunkSpeaker != .unknown ? self.currentChunkSpeaker : .unknown
                    }
                    self.handleAudioChunk(data, sourceSpeaker: speaker)
                }
            }
            audioMixer.start()
        }
    }

    private func handleAudioChunk(_ data: Data, sourceSpeaker: SpeakerType) {
        guard isActive else { return }

        // Stream raw audio directly to disk — 0 MB RAM footprint
        recordingFileHandle?.write(data)
        totalAudioBytesWritten += Int64(data.count)
        audioChunkCount += 1

        let isSpeakingNow = vad.processFrame(data)
        pcmBuffer.append(data)

        if isSpeakingNow {
            currentChunkSpeaker = sourceSpeaker
        }

        let bufferSize = pcmBuffer.count

        // Trigger conditions:
        // 1. We were speaking, but now silence was detected (natural sentence boundary) and buffer is long enough
        let phraseEnded = wasSpeaking && !isSpeakingNow && bufferSize >= minChunkBytes
        // 2. Continuous speech reached the maximum chunk window (prevent latency creep)
        let reachedMaxWindow = bufferSize >= maxChunkBytes

        if phraseEnded || reachedMaxWindow {
            let chunkToTranscribe = pcmBuffer
            let speaker = currentChunkSpeaker
            let chunkStartTime = Double(totalBytesProcessed) / (16000.0 * 2.0)
            let chunkEndTime = chunkStartTime + (Double(chunkToTranscribe.count) / (16000.0 * 2.0))

            totalBytesProcessed += chunkToTranscribe.count
            pcmBuffer.removeAll(keepingCapacity: true)
            currentChunkSpeaker = .unknown

            jobContinuation?.yield(TranscriptionJob(
                data: chunkToTranscribe,
                speaker: speaker,
                startTime: chunkStartTime,
                endTime: chunkEndTime,
                sessionID: activeSessionID
            ))
        } else if !isSpeakingNow && bufferSize > 16000 * 2 * 6 && !wasSpeaking {
            // Buffer is full of pure silence without any speech: prune old silence only if truly silent
            let bufferRMS = VADDetector.calculateRMS(pcmBuffer)
            if bufferRMS < 0.002 {
                let keepRecent = 16000 * 2 / 2 // keep last 0.5s
                if bufferSize > keepRecent {
                    let discarded = bufferSize - keepRecent
                    pcmBuffer.removeFirst(discarded)
                    totalBytesProcessed += discarded
                }
            }
        }

        wasSpeaking = isSpeakingNow
    }

    static func deduplicateRepeatedPhrases(in text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return "" }

        // 1. Sentence-level deduplication (split by sentence-ending punctuation)
        let delimiters = CharacterSet(charactersIn: ".!?؟؛\n")
        let rawParts = current.components(separatedBy: delimiters)
        var cleanedSentences: [String] = []
        var lastNormalizedSentence = ""

        for part in rawParts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            if normalized == lastNormalizedSentence {
                continue
            }
            lastNormalizedSentence = normalized
            cleanedSentences.append(trimmed)
        }

        if !cleanedSentences.isEmpty && cleanedSentences.count < rawParts.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count {
            current = cleanedSentences.joined(separator: ". ") + "."
        }

        // 2. Word n-gram deduplication for phrases of length 12 down to 2 words
        var words = current.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 4 else { return current }

        var changed = true
        var loopCount = 0
        while changed && loopCount < 5 {
            changed = false
            loopCount += 1
            let n = words.count
            guard n >= 4 else { break }

            let maxK = min(12, n / 2)
            outer: for k in stride(from: maxK, through: 2, by: -1) {
                if n < 2 * k { continue }
                for i in 0...(n - 2 * k) {
                    let p1 = words[i..<(i + k)]
                    let p2 = words[(i + k)..<(i + 2 * k)]
                    if p1.elementsEqual(p2) {
                        words.removeSubrange((i + k)..<(i + 2 * k))
                        changed = true
                        break outer
                    }
                }
            }
        }

        // 3. Collapse 3+ consecutive identical single words down to 1
        var finalWords: [String] = []
        var consecutiveCount = 0
        var lastWord = ""
        for w in words {
            if w == lastWord {
                consecutiveCount += 1
                if consecutiveCount < 2 {
                    finalWords.append(w)
                }
            } else {
                consecutiveCount = 0
                lastWord = w
                finalWords.append(w)
            }
        }

        return finalWords.joined(separator: " ")
    }

    private static func isHallucinatedOrRepetitive(_ text: String) -> Bool {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 2 else { return false }

        // Check for 3 consecutive identical words (e.g. "باکم باکم باکم")
        if words.count >= 3 {
            for i in 0..<(words.count - 2) {
                if words[i] == words[i+1] && words[i+1] == words[i+2] {
                    return true
                }
            }
        }

        // Check for 2 consecutive identical 2-word phrases (e.g. "نهاشه لایم - نهاشه لایم")
        if words.count >= 4 {
            for i in 0..<(words.count - 3) {
                if words[i] == words[i+2] && words[i+1] == words[i+3] {
                    return true
                }
            }
        }

        // Check if a single word dominates the output (e.g. "های سمجد؟ های سمجد؟")
        var counts: [String: Int] = [:]
        for w in words {
            counts[w, default: 0] += 1
            if counts[w]! >= 3 && Double(counts[w]!) / Double(words.count) >= 0.4 {
                return true
            }
        }
        return false
    }

    private func transcribeChunk(
        _ chunk: Data,
        speaker: SpeakerType,
        startTime: Double,
        endTime: Double,
        targetSessionID: UUID? = nil
    ) async {
        print("[RecordingCoordinator] transcribeChunk called, size: \(chunk.count) bytes, speaker: \(speaker.rawValue)")

        let basePrompt: String
        let lang = selectedLanguage ?? "fa"
        let customVocab = AppSettings.customVocabulary

        if lang == "fa" {
            let defaultFaPrompt = "جلسات کاری، گفتگو، برنامه‌نویسی و اصطلاحات فنی به زبان فارسی و انگلیسی: نرم‌افزار، سرور، کد، permission، certificate، API، پکیج، تست، چک کردن، باگ، پروژه، سیستم، تنظیمات، گیت، ریکوئست."
            if !customVocab.isEmpty {
                basePrompt = "\(defaultFaPrompt) واژگان تخصصی: \(customVocab)"
            } else {
                basePrompt = defaultFaPrompt
            }
        } else if lang == "en" {
            let defaultEnPrompt = "Conversational speech, engineering meeting transcription, code, software, and everyday discussion."
            if !customVocab.isEmpty {
                basePrompt = "\(defaultEnPrompt) Keywords: \(customVocab)"
            } else {
                basePrompt = defaultEnPrompt
            }
        } else {
            basePrompt = customVocab
        }

        // Use clean static prompt to prevent cross-chunk hallucination feedback loops
        let promptToUse = basePrompt.isEmpty ? nil : basePrompt

        guard let result = await whisperEngine.transcribe(
            pcm16: chunk,
            language: selectedLanguage,
            initialPrompt: promptToUse
        ) else {
            print("[RecordingCoordinator] whisperEngine.transcribe returned nil")
            return
        }

        var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Deduplicate repeated sentences and n-gram loops
        text = Self.deduplicateRepeatedPhrases(in: text)
        guard !text.isEmpty else { return }

        if Self.isHallucinatedOrRepetitive(text) {
            print("[RecordingCoordinator] Suppressed repetitive hallucination: '\(text)'")
            return
        }

        print("[RecordingCoordinator] result: text='\(text)', words=\(result.words.count), lang=\(result.detectedLanguage ?? "?")")

        // Build word timestamps
        let words: [TranscriptWord]
        if !result.words.isEmpty {
            words = result.words.map { w in
                TranscriptWord(
                    text: w.text,
                    start: w.start,
                    end: w.end,
                    confidence: w.confidence,
                    speaker: speaker
                )
            }
        } else {
            // Fallback word
            words = [
                TranscriptWord(
                    text: text,
                    start: startTime,
                    end: endTime,
                    confidence: 0,
                    speaker: speaker
                )
            ]
        }

        // Extract acoustic voice embedding from the audio chunk
        let embedding = VoiceEmbeddingEngine.shared.extractEmbedding(from: chunk)

        var initialCustomName: String? = nil
        if speaker == .user {
            initialCustomName = AppSettings.userName
        } else if let emb = embedding, speaker == .system && audioSource == .both {
            initialCustomName = VoiceEmbeddingEngine.shared.classifyOnline(embedding: emb)
        }

        // Create structured dialogue segment
        let segment = TranscriptSegment(
            speaker: speaker,
            speakerCustomName: initialCustomName,
            text: text,
            start: startTime,
            end: endTime,
            words: words,
            voiceEmbedding: embedding
        )

        transcriptStore.appendSegment(segment, targetSessionID: targetSessionID)

        // Update context prompt with the tail of the recent transcript (max 10 words)
        let wordsList = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let tailWords = wordsList.suffix(10).joined(separator: " ")
        recentTranscriptContext = tailWords
    }

    func startRecording() async {
        await prepareModel()
        guard whisperEngine.isModelLoaded else {
            if !ModelManager.shared.isModelDownloaded(AppSettings.whisperModelSize) {
                statusMessage = "مدل دانلود نشده است. لطفاً از بخش تنظیمات مدل را دانلود کنید."
            } else {
                statusMessage = whisperEngine.loadError ?? "مدل بارگذاری نشد"
            }
            return
        }

        audioSource = AppSettings.audioSource
        wireAudioCallbacks(for: audioSource)
        whisperEngine.resetTiming()
        vad.reset()
        VoiceEmbeddingEngine.shared.resetOnlineClusters()

        pcmBuffer.removeAll(keepingCapacity: true)
        audioChunkCount = 0
        totalBytesProcessed = 0
        wasSpeaking = false
        recentTranscriptContext = ""
        currentChunkSpeaker = .unknown

        switch audioSource {
        case .microphone:
            guard await micCapture.requestPermission() else {
                permissionError = .microphone
                statusMessage = "دسترسی میکروفون رد شد."
                return
            }
        case .systemAudio:
            guard await systemCapture.requestPermission() else {
                permissionError = .systemAudio
                statusMessage = "دسترسی Screen Recording رد شد."
                return
            }
        case .both:
            let micOK = await micCapture.requestPermission()
            let sysOK = await systemCapture.requestPermission()
            if !micOK && !sysOK {
                permissionError = .both
                statusMessage = "دسترسی میکروفون و Screen Recording رد شد."
            } else if !micOK {
                permissionError = .microphone
                statusMessage = "دسترسی میکروفون رد شد."
            } else if !sysOK {
                permissionError = .systemAudio
                statusMessage = "دسترسی Screen Recording (صدای سیستم) رد شد."
            }
            guard micOK && sysOK else {
                return
            }
        }
        permissionError = nil

        // Start streaming audio to disk immediately (0 MB RAM overhead)
        let audioPath = startAudioStream()

        // Cancel previous worker if any
        jobContinuation?.finish()
        workerTask?.cancel()
        jobContinuation = nil
        workerTask = nil

        // Initialize fresh serial worker stream
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptionJob.self)
        self.jobContinuation = continuation

        workerTask = Task { [weak self] in
            for await job in stream {
                guard let self else { break }
                await self.transcribeChunk(
                    job.data,
                    speaker: job.speaker,
                    startTime: job.startTime,
                    endTime: job.endTime,
                    targetSessionID: job.sessionID
                )
            }
        }

        // Look up active calendar meeting title if available
        let calTitle = CalendarService.shared.currentMeetingTitle()
        transcriptStore.startNewSession(language: selectedLanguage, calendarEventTitle: calTitle, audioFilePath: audioPath)
        activeSessionID = transcriptStore.currentSession?.id

        do {
            switch audioSource {
            case .microphone:
                try micCapture.startCapture()
            case .systemAudio:
                try await systemCapture.startCapture()
            case .both:
                try micCapture.startCapture()
                try await systemCapture.startCapture()
            }
            isActive = true
            statusMessage = statusLabel(for: audioSource)
            recordingStartTime = Date()
            nextHourlyCheckSeconds = 3600
            isHourlyConfirmationActive = false
            startHourlyMonitoring()
            print("[RecordingCoordinator] ✅ Recording started, source: \(audioSource.rawValue), calendar: \(calTitle ?? "none")")
        } catch {
            statusMessage = "خطا: \(error.localizedDescription)"
            print("[RecordingCoordinator] ❌ Failed to start recording: \(error)")
            stopHourlyMonitoring()
            _ = finalizeAudioStream()
            await stopAllCapture()
        }
    }

    func stopRecording() async {
        stopHourlyMonitoring()
        dismissHourlyConfirmationPrompt()
        await stopAllCapture()

        if pcmBuffer.count >= 16000 * 2 {
            let chunk = pcmBuffer
            let start = Double(totalBytesProcessed) / (16000.0 * 2.0)
            let end = start + (Double(chunk.count) / (16000.0 * 2.0))
            let speaker = currentChunkSpeaker
            let sessionID = activeSessionID
            jobContinuation?.yield(TranscriptionJob(
                data: chunk,
                speaker: speaker,
                startTime: start,
                endTime: end,
                sessionID: sessionID
            ))
            pcmBuffer.removeAll()
        }

        // Finish queue and wait for remaining in-flight chunks to transcribe
        jobContinuation?.finish()
        jobContinuation = nil

        if let worker = workerTask {
            statusMessage = "در حال تکمیل پردازش صوت..."
            _ = await worker.value
            workerTask = nil
        }

        // Finalize audio file on disk
        let audioPath = finalizeAudioStream()

        transcriptStore.stopSession(audioFilePath: audioPath)
        activeSessionID = nil
        isActive = false
        statusMessage = "ضبط متوقف شد"
        print("[RecordingCoordinator] Recording stopped. Audio chunks: \(audioChunkCount), total bytes: \(totalAudioBytesWritten)")
    }

    func dismissPermissionError() {
        permissionError = nil
    }

    func copyCurrentTranscript() {
        guard let session = transcriptStore.currentSession else { return }
        ClipboardService.copySession(session)
        statusMessage = "در کلیپ‌بورد کپی شد"
    }

    private func stopAllCapture() async {
        micCapture.stopCapture()
        await systemCapture.stopCapture()
        audioMixer.reset()
    }

    private func statusLabel(for mode: AudioSourceMode) -> String {
        switch mode {
        case .microphone: return "ضبط — میکروفون (on-device)"
        case .systemAudio: return "ضبط — صدای سیستم (on-device)"
        case .both: return "ضبط — میک + سیستم (تفکیک گوینده)"
        }
    }

    // MARK: - Hourly Meeting Monitoring

    private func startHourlyMonitoring() {
        stopHourlyMonitoring()
        hourlyMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkHourlyRecordingDuration()
            }
        }
    }

    private func stopHourlyMonitoring() {
        hourlyMonitoringTimer?.invalidate()
        hourlyMonitoringTimer = nil
        autoStopCountdownTimer?.invalidate()
        autoStopCountdownTimer = nil
    }

    private func checkHourlyRecordingDuration() {
        guard isActive, AppSettings.hourlyMeetingReminder, let start = recordingStartTime else { return }
        guard !isHourlyConfirmationActive else { return }

        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= nextHourlyCheckSeconds {
            let hours = max(1, Int(round(elapsed / 3600.0)))
            triggerHourlyConfirmation(hours: hours)
            nextHourlyCheckSeconds += 3600
        }
    }

    private func triggerHourlyConfirmation(hours: Int) {
        isHourlyConfirmationActive = true
        hourlyConfirmationHours = hours
        autoStopCountdownSeconds = 300 // 5 minutes

        // Show floating confirmation panel
        MeetingConfirmationPanel.shared.show(coordinator: self)

        // Start 5-minute countdown timer
        autoStopCountdownTimer?.invalidate()
        autoStopCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.autoStopCountdownSeconds -= 1
                if self.autoStopCountdownSeconds <= 0 {
                    self.autoStopCountdownTimer?.invalidate()
                    self.autoStopCountdownTimer = nil
                    print("[RecordingCoordinator] ⚠️ Hourly meeting confirmation timed out. Auto-stopping session...")
                    self.dismissHourlyConfirmationPrompt()
                    Task {
                        await self.stopRecording()
                        self.statusMessage = "ضبط جلسه به دلیل عدم تایید پس از ۱ ساعت، خودکار ذخیره شد"
                    }
                }
            }
        }
    }

    func confirmContinueRecording() {
        dismissHourlyConfirmationPrompt()
        print("[RecordingCoordinator] ✅ User confirmed meeting is still ongoing. Scheduled next check in 1 hour.")
    }

    func confirmStopRecording() {
        dismissHourlyConfirmationPrompt()
        Task {
            await stopRecording()
        }
    }

    private func dismissHourlyConfirmationPrompt() {
        isHourlyConfirmationActive = false
        autoStopCountdownTimer?.invalidate()
        autoStopCountdownTimer = nil
        MeetingConfirmationPanel.shared.dismiss()
    }

    // MARK: - Audio File Streaming

    private func startAudioStream() -> String? {
        let dir = audioDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).wav"
        let fileURL = dir.appendingPathComponent(filename)

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            print("[RecordingCoordinator] ❌ Could not create FileHandle for: \(fileURL.path)")
            return nil
        }

        // Write initial 44-byte WAV header placeholder
        let initialHeader = Self.createWAVHeader(dataSize: 0, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        handle.write(initialHeader)

        recordingFileHandle = handle
        recordingFileURL = fileURL
        totalAudioBytesWritten = 0

        print("[RecordingCoordinator] 🎙️ Audio stream file started: \(fileURL.path)")
        return fileURL.path
    }

    private func finalizeAudioStream() -> String? {
        guard let handle = recordingFileHandle, let url = recordingFileURL else {
            return nil
        }

        defer {
            try? handle.close()
            recordingFileHandle = nil
            recordingFileURL = nil
        }

        guard totalAudioBytesWritten > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        // Clamp data size to UInt32.max - 36 to prevent 32-bit WAV header overflow on long recordings
        let clampedDataSize = UInt32(min(totalAudioBytesWritten, Int64(UInt32.max - 36)))
        let clampedFileSize = clampedDataSize + 36

        // Seek and patch RIFF file size (offset 4)
        try? handle.seek(toOffset: 4)
        withUnsafeBytes(of: clampedFileSize.littleEndian) { buffer in
            handle.write(Data(buffer))
        }

        // Seek and patch data chunk size (offset 40)
        try? handle.seek(toOffset: 40)
        withUnsafeBytes(of: clampedDataSize.littleEndian) { buffer in
            handle.write(Data(buffer))
        }

        print("[RecordingCoordinator] ✅ Audio stream finalized: \(url.path) (\(totalAudioBytesWritten) bytes)")
        return url.path
    }

    private var audioDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MirzaBenevis/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func createWAVHeader(dataSize: UInt32, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let fileSize = 36 + dataSize

        var header = Data()
        header.reserveCapacity(44)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: fileSize.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        withUnsafeBytes(of: UInt32(16).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(channels).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(byteRate).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { header.append(contentsOf: $0) }

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { header.append(contentsOf: $0) }

        return header
    }

    static func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var fileData = createWAVHeader(
            dataSize: UInt32(min(pcmData.count, Int(UInt32.max - 36))),
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bitsPerSample
        )
        fileData.append(pcmData)
        return fileData
    }
}
