import Foundation

/// Lightweight, on-device Voice Activity Detector (VAD) for 16 kHz 16-bit mono PCM.
/// Uses energy (RMS), zero-crossing rate, and dynamic hangover smoothing.
final class VADDetector {
    /// Energy threshold above which audio is considered active speech.
    var speechThreshold: Float = 0.004 // ~ -48 dBFS (sensitive enough for quiet microphones and laptop speech)

    /// Number of consecutive silent frames required to declare the end of an utterance.
    var silenceHangoverFrames: Int = 8 // ~800ms when frame is 100ms

    private var consecutiveSilenceCount: Int = 0
    private var consecutiveSpeechCount: Int = 0
    private(set) var isSpeaking: Bool = false

    /// Calculate Root-Mean-Square (RMS) amplitude from 16-bit PCM data.
    static func calculateRMS(_ data: Data) -> Float {
        guard data.count >= MemoryLayout<Int16>.size else { return 0 }
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var sumSquares: Double = 0

        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let normalized = Double(samples[i]) / 32768.0
                sumSquares += normalized * normalized
            }
        }

        return Float(sqrt(sumSquares / Double(sampleCount)))
    }

    /// Calculate Zero-Crossing Rate (helps detect unvoiced fricatives like 's', 'sh', 'f').
    static func calculateZCR(_ data: Data) -> Float {
        guard data.count >= MemoryLayout<Int16>.size * 2 else { return 0 }
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var crossings = 0

        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            var prevSign = samples[0] >= 0
            for i in 1..<sampleCount {
                let currentSign = samples[i] >= 0
                if currentSign != prevSign {
                    crossings += 1
                    prevSign = currentSign
                }
            }
        }

        return Float(crossings) / Float(sampleCount)
    }

    /// Process an audio frame (e.g. 50-100ms) and return whether speech was detected.
    func processFrame(_ pcmData: Data) -> Bool {
        let rms = Self.calculateRMS(pcmData)
        let zcr = Self.calculateZCR(pcmData)

        // Speech can be voiced (high energy) or unvoiced (medium energy + high ZCR)
        let frameHasSpeech = (rms >= speechThreshold) || (rms >= speechThreshold * 0.5 && zcr > 0.12)

        if frameHasSpeech {
            consecutiveSpeechCount += 1
            consecutiveSilenceCount = 0
            if consecutiveSpeechCount >= 2 { // At least ~150-200ms of sustained energy
                isSpeaking = true
            }
        } else {
            consecutiveSilenceCount += 1
            if consecutiveSilenceCount >= silenceHangoverFrames {
                isSpeaking = false
                consecutiveSpeechCount = 0
            }
        }

        return isSpeaking
    }

    /// Reset internal state between recording sessions.
    func reset() {
        consecutiveSilenceCount = 0
        consecutiveSpeechCount = 0
        isSpeaking = false
    }
}
