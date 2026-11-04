import Foundation
import AppKit

@MainActor
final class WhisperEngine: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var isProcessing = false
    @Published private(set) var modelName = ""
    @Published var loadError: String?

    private var context: WhisperContext?
    private var timeOffsetMs: Int32 = 0

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleWillTerminate() {
        print("[WhisperEngine] App is terminating, releasing model context...")
        context = nil
        isModelLoaded = false
    }

    func loadModel(size: WhisperModelSize) async {
        loadError = nil
        isModelLoaded = false
        context = nil

        do {
            print("[WhisperEngine] Loading model: \(size.rawValue)...")
            guard ModelManager.shared.isModelDownloaded(size) else {
                throw NSError(domain: "WhisperEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "مدل \(size.label) هنوز دانلود نشده است."])
            }
            let path = try await ModelManager.shared.ensureModel(size)
            print("[WhisperEngine] Model file: \(path.path)")
            context = try WhisperContext.createContext(
                modelPath: path.path,
                useGPU: AppSettings.useGPU
            )
            modelName = size.rawValue
            isModelLoaded = true
            timeOffsetMs = 0
            print("[WhisperEngine] ✅ Model loaded successfully, GPU=\(AppSettings.useGPU)")
        } catch {
            loadError = error.localizedDescription
            isModelLoaded = false
            print("[WhisperEngine] ❌ Failed to load model: \(error)")
        }
    }

    func resetTiming() {
        timeOffsetMs = 0
    }

    func transcribe(pcm16: Data, language: String?, initialPrompt: String? = nil) async -> WhisperTranscriptionResult? {
        guard let context, !pcm16.isEmpty else {
            print("[WhisperEngine] transcribe skipped: context=\(context != nil), dataSize=\(pcm16.count)")
            return nil
        }

        isProcessing = true
        defer { isProcessing = false }

        let samples = Self.pcm16ToFloat(pcm16)
        guard samples.count >= 16_000 else {
            print("[WhisperEngine] transcribe skipped: only \(samples.count) samples (need ≥16000)")
            return nil
        } // min ~1 sec

        do {
            print("[WhisperEngine] Transcribing \(samples.count) samples, lang=\(language ?? "auto"), offset=\(timeOffsetMs)ms, prompt=\(initialPrompt != nil)")
            let result = try await context.transcribe(
                samples: samples,
                language: language,
                offsetMs: timeOffsetMs,
                initialPrompt: initialPrompt
            )
            timeOffsetMs += Int32(Double(pcm16.count) / (16000 * 2) * 1000)
            print("[WhisperEngine] ✅ Got \(result.words.count) words, text length=\(result.text.count)")
            return result
        } catch {
            loadError = error.localizedDescription
            print("[WhisperEngine] ❌ Transcription error: \(error)")
            return nil
        }
    }

    private static func pcm16ToFloat(_ data: Data) -> [Float] {
        let samples: [Float] = data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Int16.self)
            return ptr.map { Float($0) / 32768.0 }
        }
        guard !samples.isEmpty else { return samples }

        var maxPeak: Float = 0
        for s in samples {
            let absVal = abs(s)
            if absVal > maxPeak { maxPeak = absVal }
        }

        // If audio is audible but low volume, normalize up to peak ~0.7 to improve Whisper accuracy
        if maxPeak > 0.005 && maxPeak < 0.5 {
            let gain = min(Float(5.0), 0.7 / maxPeak)
            return samples.map { $0 * gain }
        }
        return samples
    }
}
