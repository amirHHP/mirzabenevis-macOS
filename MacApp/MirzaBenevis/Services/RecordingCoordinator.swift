import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published var statusMessage = "آماده"
    @Published var isActive = false
    @Published var selectedLanguage: String? = AppSettings.selectedLanguage
    @Published var audioSource: AudioSourceMode = AppSettings.audioSource

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

    /// Accumulator for saving the full audio as a WAV file
    private var audioRecording = Data()
    private var audioChunkCount = 0

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

        // Save raw audio for file export
        audioRecording.append(data)
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

            Task {
                await transcribeChunk(
                    chunkToTranscribe,
                    speaker: speaker,
                    startTime: chunkStartTime,
                    endTime: chunkEndTime
                )
            }
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
        endTime: Double
    ) async {
        print("[RecordingCoordinator] transcribeChunk called, size: \(chunk.count) bytes, speaker: \(speaker.rawValue)")

        let basePrompt: String
        let lang = selectedLanguage ?? "fa"
        if lang == "fa" {
            basePrompt = "گفتگوهای روزمره، جلسات، ویدئو، پادکست و تست صدا به زبان فارسی."
        } else if lang == "en" {
            basePrompt = "Conversational speech, meeting transcription, video, and everyday discussion."
        } else {
            basePrompt = ""
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

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Create structured dialogue segment
        let segment = TranscriptSegment(
            speaker: speaker,
            text: text,
            start: startTime,
            end: endTime,
            words: words
        )

        transcriptStore.appendSegment(segment)

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

        pcmBuffer.removeAll(keepingCapacity: true)
        audioRecording.removeAll(keepingCapacity: true)
        audioChunkCount = 0
        totalBytesProcessed = 0
        wasSpeaking = false
        recentTranscriptContext = ""
        currentChunkSpeaker = .unknown

        switch audioSource {
        case .microphone:
            guard await micCapture.requestPermission() else {
                statusMessage = "دسترسی میکروفون رد شد. لطفاً دسترسی به میکروفون را در تنظیمات سیستم فعال کنید."
                return
            }
        case .systemAudio:
            guard await systemCapture.requestPermission() else {
                statusMessage = "دسترسی Screen Recording رد شد. اگر دسترسی داده‌اید، برنامه را ببندید و دوباره باز کنید."
                return
            }
        case .both:
            let micOK = await micCapture.requestPermission()
            let sysOK = await systemCapture.requestPermission()
            if !micOK && !sysOK {
                statusMessage = "دسترسی میکروفون و Screen Recording رد شد."
            } else if !micOK {
                statusMessage = "دسترسی میکروفون رد شد. لطفاً دسترسی به میکروفون را در تنظیمات سیستم فعال کنید."
            } else if !sysOK {
                statusMessage = "دسترسی Screen Recording (صدای سیستم) رد شد. اگر دسترسی داده‌اید، برنامه را ببندید و دوباره باز کنید."
            }
            guard micOK && sysOK else {
                return
            }
        }

        // Look up active calendar meeting title if available
        let calTitle = CalendarService.shared.currentMeetingTitle()
        transcriptStore.startNewSession(language: selectedLanguage, calendarEventTitle: calTitle)

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
            print("[RecordingCoordinator] ✅ Recording started, source: \(audioSource.rawValue), calendar: \(calTitle ?? "none")")
        } catch {
            statusMessage = "خطا: \(error.localizedDescription)"
            print("[RecordingCoordinator] ❌ Failed to start recording: \(error)")
            await stopAllCapture()
        }
    }

    func stopRecording() async {
        await stopAllCapture()

        if pcmBuffer.count >= 16000 * 2 {
            let chunk = pcmBuffer
            let start = Double(totalBytesProcessed) / (16000.0 * 2.0)
            let end = start + (Double(chunk.count) / (16000.0 * 2.0))
            await transcribeChunk(chunk, speaker: currentChunkSpeaker, startTime: start, endTime: end)
            pcmBuffer.removeAll()
        }

        // Save audio file
        let audioPath = saveAudioFile()

        transcriptStore.stopSession(audioFilePath: audioPath)
        isActive = false
        statusMessage = "ضبط متوقف شد"
        print("[RecordingCoordinator] Recording stopped. Audio chunks: \(audioChunkCount), total bytes: \(audioRecording.count)")
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

    // MARK: - Audio File Saving

    /// Save accumulated PCM data as a WAV file. Returns the file path if successful.
    private func saveAudioFile() -> String? {
        guard !audioRecording.isEmpty else {
            print("[RecordingCoordinator] No audio data to save")
            return nil
        }

        let dir = audioDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).wav"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            let wavData = Self.createWAVFile(from: audioRecording, sampleRate: 16000, channels: 1, bitsPerSample: 16)
            try wavData.write(to: fileURL, options: .atomic)
            print("[RecordingCoordinator] ✅ Audio saved: \(fileURL.path) (\(wavData.count) bytes)")
            return fileURL.path
        } catch {
            print("[RecordingCoordinator] ❌ Failed to save audio: \(error)")
            return nil
        }
    }

    private var audioDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MirzaBenevis/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Create a WAV file from raw PCM data.
    static func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = UInt32(36 + pcmData.count)

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })     // sub-chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })      // PCM format
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)

        return header
    }
}
