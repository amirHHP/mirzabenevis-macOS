import Foundation

/// Buffers mic and system audio streams and emits mixed PCM when both have data.
/// Uses amortized O(1) buffer slicing and a timer-based flush to ensure low-latency audio flow.
final class AudioMixer {
    var onMixedData: ((Data) -> Void)?

    private var micBuffer = Data()
    private var systemBuffer = Data()
    private var micReadOffset: Int = 0
    private var systemReadOffset: Int = 0

    private let lock = NSLock()
    private let emitChunkSize = 3200 // ~100ms at 16kHz mono int16
    private let maxBufferBytes = 16000 * 2 * 2 // 2 seconds safety cap to prevent latency drift
    private let compactionThreshold = 16384 // Compact buffer after reading 16KB

    private var flushTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.mirzabenevis.mixer-timer")

    /// Start the periodic flush timer. Must be called before audio begins.
    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        // 300ms grace period gives both sources time to buffer, then flushes whatever is available
        timer.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.timerFlush()
        }
        timer.resume()
        flushTimer = timer
    }

    /// Stop the timer and clear buffers.
    func stop() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    func appendMic(_ data: Data) {
        lock.lock()
        micBuffer.append(data)
        lock.unlock()
        mixIfBothReady()
    }

    func appendSystem(_ data: Data) {
        lock.lock()
        systemBuffer.append(data)
        lock.unlock()
        mixIfBothReady()
    }

    func reset() {
        stop()
        lock.lock()
        micBuffer.removeAll(keepingCapacity: true)
        systemBuffer.removeAll(keepingCapacity: true)
        micReadOffset = 0
        systemReadOffset = 0
        lock.unlock()
    }

    private func compactBuffersIfNeeded() {
        if micReadOffset >= compactionThreshold {
            micBuffer.removeSubrange(0..<micReadOffset)
            micReadOffset = 0
        }
        if systemReadOffset >= compactionThreshold {
            systemBuffer.removeSubrange(0..<systemReadOffset)
            systemReadOffset = 0
        }
    }

    /// Mix and emit when both sources have enough data (lowest latency path).
    private func mixIfBothReady() {
        var toEmit: [Data] = []
        lock.lock()
        while (micBuffer.count - micReadOffset) >= emitChunkSize && (systemBuffer.count - systemReadOffset) >= emitChunkSize {
            let micChunk = micBuffer.subdata(in: micReadOffset..<(micReadOffset + emitChunkSize))
            let sysChunk = systemBuffer.subdata(in: systemReadOffset..<(systemReadOffset + emitChunkSize))
            micReadOffset += emitChunkSize
            systemReadOffset += emitChunkSize

            let mixed = PCMConverter.mixPCM16(micChunk, sysChunk)
            toEmit.append(mixed)
        }

        // Cap buffer to prevent latency desynchronization
        if (micBuffer.count - micReadOffset) > maxBufferBytes {
            micReadOffset = micBuffer.count - maxBufferBytes
        }
        if (systemBuffer.count - systemReadOffset) > maxBufferBytes {
            systemReadOffset = systemBuffer.count - maxBufferBytes
        }

        compactBuffersIfNeeded()
        lock.unlock()

        for chunk in toEmit {
            onMixedData?(chunk)
        }
    }

    /// Timer-based flush: if only one source has data after the grace period,
    /// pass it through instead of waiting forever for the other source.
    private func timerFlush() {
        var toEmit: [Data] = []
        lock.lock()
        // First, mix anything where both sources have data
        while (micBuffer.count - micReadOffset) >= emitChunkSize && (systemBuffer.count - systemReadOffset) >= emitChunkSize {
            let micChunk = micBuffer.subdata(in: micReadOffset..<(micReadOffset + emitChunkSize))
            let sysChunk = systemBuffer.subdata(in: systemReadOffset..<(systemReadOffset + emitChunkSize))
            micReadOffset += emitChunkSize
            systemReadOffset += emitChunkSize
            toEmit.append(PCMConverter.mixPCM16(micChunk, sysChunk))
        }

        // Then, flush any remaining mic data (system might be silent)
        while (micBuffer.count - micReadOffset) >= emitChunkSize {
            let chunk = micBuffer.subdata(in: micReadOffset..<(micReadOffset + emitChunkSize))
            micReadOffset += emitChunkSize
            toEmit.append(chunk)
        }

        // Flush any remaining system data (mic might be muted)
        while (systemBuffer.count - systemReadOffset) >= emitChunkSize {
            let chunk = systemBuffer.subdata(in: systemReadOffset..<(systemReadOffset + emitChunkSize))
            systemReadOffset += emitChunkSize
            toEmit.append(chunk)
        }

        compactBuffersIfNeeded()
        lock.unlock()

        for chunk in toEmit {
            onMixedData?(chunk)
        }
    }
}
