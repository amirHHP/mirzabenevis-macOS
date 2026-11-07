import AVFoundation
import CoreMedia

/// High-performance cached converter to prevent recreating AVAudioConverter on every audio buffer.
final class CachedAudioConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?
    private let outputFormat: AVAudioFormat

    init(targetSampleRate: Double = PCMConverter.targetSampleRate) {
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
    }

    func convertToPCM16Mono(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        guard let inputFormat = AVAudioFormat(streamDescription: asbdPtr) else { return nil }

        var sampleBufferCopy = sampleBuffer
        guard let pcmBuffer = PCMConverter.convertSampleBufferToPCMBuffer(&sampleBufferCopy, format: inputFormat) else {
            return nil
        }

        if inputFormat.sampleRate == outputFormat.sampleRate &&
           inputFormat.channelCount == outputFormat.channelCount &&
           inputFormat.commonFormat == outputFormat.commonFormat {
            return PCMConverter.extractInt16Data(from: pcmBuffer)
        }

        // Cache or recreate converter only if input format changed
        if converter == nil || cachedInputFormat == nil || cachedInputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            cachedInputFormat = inputFormat
        }

        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outFrames) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil else { return nil }

        return PCMConverter.extractInt16Data(from: outBuffer)
    }
}

enum PCMConverter {
    static let targetSampleRate: Double = 16000

    /// Global fallback converter for one-off conversions.
    private static let sharedCachedConverter = CachedAudioConverter(targetSampleRate: targetSampleRate)

    /// Convert CMSampleBuffer (float or int PCM) to 16-bit mono PCM at 16 kHz.
    static func toPCM16Mono(_ sampleBuffer: CMSampleBuffer) -> Data? {
        sharedCachedConverter.convertToPCM16Mono(sampleBuffer)
    }

    static func convertSampleBufferToPCMBuffer(
        _ sampleBuffer: inout CMSampleBuffer,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }

    static func extractInt16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }

    /// Mix two equal-length PCM16 mono buffers with headroom-preserving soft mixing.
    static func mixPCM16(_ a: Data, _ b: Data) -> Data {
        let count = min(a.count, b.count)
        guard count >= 2 else { return a.count >= b.count ? a : b }

        var result = Data(count: count)
        result.withUnsafeMutableBytes { outPtr in
            a.withUnsafeBytes { aPtr in
                b.withUnsafeBytes { bPtr in
                    let aSamples = aPtr.bindMemory(to: Int16.self)
                    let bSamples = bPtr.bindMemory(to: Int16.self)
                    let outSamples = outPtr.bindMemory(to: Int16.self)
                    let sampleCount = count / MemoryLayout<Int16>.size
                    for i in 0..<sampleCount {
                        let sampleA = Float(aSamples[i])
                        let sampleB = Float(bSamples[i])
                        // Headroom scaling prevents harsh digital clipping when both sources are loud
                        let mixed = (sampleA + sampleB) * 0.75
                        let clamped = max(-32767.0, min(32767.0, mixed))
                        outSamples[i] = Int16(clamped)
                    }
                }
            }
        }
        return result
    }
}
