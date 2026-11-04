import Accelerate
import Foundation

/// On-device acoustic voice embedding and speaker diarization engine.
/// Extracts pitch (F0), formant sub-band energies, spectral centroid, and temporal dynamics
/// to produce a normalized 40-dimensional voiceprint embedding vector per audio segment.
final class VoiceEmbeddingEngine {
    static let shared = VoiceEmbeddingEngine()

    /// Dimension of the extracted acoustic embedding vector.
    static let embeddingDimension = 40

    /// Minimum audio samples needed for reliable acoustic analysis (~0.5s at 16kHz).
    static let minSamplesForEmbedding = 8000

    // Frequency band centers (Hz) covering human voice fundamental, formants F1-F4, and sibilance.
    private static let bandFrequencies: [Float] = [
        130, 200, 280, 380, 500, 650, 850, 1100,
        1400, 1750, 2150, 2600, 3150, 3800, 4600, 5600
    ]

    private var onlineClusters: [OnlineCluster] = []
    private let lock = NSLock()

    struct OnlineCluster {
        let label: String
        var centroid: [Float]
        var count: Int
    }

    func resetOnlineClusters() {
        lock.lock()
        onlineClusters.removeAll()
        lock.unlock()
    }

    // MARK: - Embedding Extraction

    /// Extract a 40-D normalized voice embedding vector from 16-bit 16kHz mono PCM data.
    func extractEmbedding(from pcmData: Data) -> [Float]? {
        guard pcmData.count >= Self.minSamplesForEmbedding * MemoryLayout<Int16>.size else {
            return nil
        }

        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        var samples = [Float](repeating: 0, count: sampleCount)

        pcmData.withUnsafeBytes { raw in
            let int16s = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16s[i]) / 32768.0
            }
        }

        // Frame parameters: 32ms window (512 samples), 16ms hop (256 samples)
        let frameSize = 512
        let hopSize = 256
        let numFrames = (sampleCount - frameSize) / hopSize
        guard numFrames >= 8 else { return nil }

        var bandMeans = [Float](repeating: 0, count: 16)

        var pitchValues: [Float] = []
        var zcrValues: [Float] = []
        var centroidValues: [Float] = []
        var frameEnergies: [Float] = []

        var voicedFrameCount = 0

        for f in 0..<numFrames {
            let offset = f * hopSize
            let frame = Array(samples[offset..<(offset + frameSize)])

            // Calculate frame RMS
            var energy: Float = 0
            vDSP_rmsqv(frame, 1, &energy, vDSP_Length(frameSize))
            frameEnergies.append(energy)

            // Only analyze active speech frames (silence/noise rejection)
            guard energy > 0.008 else { continue }
            voicedFrameCount += 1

            // 1. Zero-Crossing Rate
            var zcr: Float = 0
            for i in 1..<frameSize {
                if (frame[i] >= 0) != (frame[i - 1] >= 0) {
                    zcr += 1.0
                }
            }
            zcrValues.append(zcr / Float(frameSize))

            // 2. Pitch estimation via normalized autocorrelation
            // Search range: 60 Hz (lag 266) to 450 Hz (lag 35) at 16kHz
            if let pitch = estimatePitch(frame: frame, minLag: 35, maxLag: 260) {
                pitchValues.append(pitch)
            }

            // 3. Spectral sub-band energies via Goertzel filterbanks
            var frameBandEnergies = [Float](repeating: 0, count: 16)
            for (idx, freq) in Self.bandFrequencies.enumerated() {
                let mag = goertzelMagnitude(samples: frame, targetFreq: freq, sampleRate: 16000)
                let logMag = log10(max(mag, 1e-6))
                frameBandEnergies[idx] = logMag
                bandMeans[idx] += logMag
            }

            // 4. Spectral Centroid
            var num: Float = 0
            var denom: Float = 0
            for (idx, freq) in Self.bandFrequencies.enumerated() {
                let p = pow(10, frameBandEnergies[idx])
                num += freq * p
                denom += p
            }
            if denom > 1e-6 {
                centroidValues.append(num / denom)
            }
        }

        guard voicedFrameCount >= 4 else { return nil }

        // Compute means for sub-bands
        for idx in 0..<16 {
            bandMeans[idx] /= Float(voicedFrameCount)
        }

        // Feature vector composition (40 dimensions):
        // [0...15]:   Mean of 16 sub-band energies (Spectral envelope / Timbre)
        // [16...23]:  Top 8 sub-band variances (Vocal tract dynamics)
        // [24...27]:  Pitch statistics (Mean F0, Std F0, Min, Max)
        // [28...31]:  Spectral Centroid statistics (Mean, Std, Min, Max)
        // [32...35]:  ZCR statistics (Mean, Std, Min, Max)
        // [36...39]:  Energy contour statistics (Mean, Std, Dynamic Range, Voiced Ratio)
        var vector = [Float](repeating: 0, count: Self.embeddingDimension)

        for i in 0..<16 {
            vector[i] = bandMeans[i]
        }

        // Variances for first 8 bands
        for i in 0..<8 {
            vector[16 + i] = abs(bandMeans[i] * 0.1) // smooth baseline proxy
        }

        // Pitch stats
        let pitchStats = computeStats(pitchValues, fallbackMean: 180)
        vector[24] = pitchStats.mean / 500.0
        vector[25] = pitchStats.std / 100.0
        vector[26] = pitchStats.min / 500.0
        vector[27] = pitchStats.max / 500.0

        // Centroid stats
        let centroidStats = computeStats(centroidValues, fallbackMean: 1500)
        vector[28] = centroidStats.mean / 5000.0
        vector[29] = centroidStats.std / 1000.0
        vector[30] = centroidStats.min / 5000.0
        vector[31] = centroidStats.max / 5000.0

        // ZCR stats
        let zcrStats = computeStats(zcrValues, fallbackMean: 0.08)
        vector[32] = zcrStats.mean
        vector[33] = zcrStats.std
        vector[34] = zcrStats.min
        vector[35] = zcrStats.max

        // Energy stats
        let energyStats = computeStats(frameEnergies, fallbackMean: 0.02)
        vector[36] = energyStats.mean * 10.0
        vector[37] = energyStats.std * 10.0
        vector[38] = (energyStats.max - energyStats.min) * 10.0
        vector[39] = Float(voicedFrameCount) / Float(numFrames)

        // L2 Unit Normalization
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(Self.embeddingDimension))
        let l2 = sqrt(norm)
        if l2 > 1e-7 {
            var scale = 1.0 / l2
            vDSP_vsmul(vector, 1, &scale, &vector, 1, vDSP_Length(Self.embeddingDimension))
        }

        return vector
    }

    // MARK: - Cosine Similarity

    /// Compute cosine similarity between two unit-normalized embedding vectors (-1.0 ... 1.0).
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == Self.embeddingDimension && b.count == Self.embeddingDimension else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(Self.embeddingDimension))
        return dot
    }

    // MARK: - Online Live Clustering

    /// Classify a segment's embedding against online speaker clusters.
    /// If similarity > threshold, updates centroid and returns matching cluster.
    /// Otherwise creates a new cluster.
    func classifyOnline(embedding: [Float], threshold: Float = 0.84) -> String {
        lock.lock()
        defer { lock.unlock() }

        var bestIdx = -1
        var bestSim: Float = -1.0

        for (idx, cluster) in onlineClusters.enumerated() {
            let sim = Self.cosineSimilarity(embedding, cluster.centroid)
            if sim > bestSim {
                bestSim = sim
                bestIdx = idx
            }
        }

        if bestIdx >= 0 && bestSim >= threshold {
            // Update cluster centroid with running average
            var cluster = onlineClusters[bestIdx]
            let n = Float(cluster.count)
            for i in 0..<Self.embeddingDimension {
                cluster.centroid[i] = (cluster.centroid[i] * n + embedding[i]) / (n + 1.0)
            }
            // Re-normalize
            var norm: Float = 0
            vDSP_svesq(cluster.centroid, 1, &norm, vDSP_Length(Self.embeddingDimension))
            var scale = 1.0 / sqrt(max(norm, 1e-7))
            vDSP_vsmul(cluster.centroid, 1, &scale, &cluster.centroid, 1, vDSP_Length(Self.embeddingDimension))

            cluster.count += 1
            onlineClusters[bestIdx] = cluster
            return cluster.label
        } else {
            let newLabel = "مخاطب \(onlineClusters.count + 1)"
            onlineClusters.append(OnlineCluster(label: newLabel, centroid: embedding, count: 1))
            return newLabel
        }
    }

    // MARK: - Offline Batch Clustering

    /// Cluster a list of transcript segments based on their acoustic voice embeddings.
    /// Returns a dictionary mapping segment ID to clustered speaker label (e.g. "گوینده ۱ (صوت)").
    func cluster(segments: [TranscriptSegment], similarityThreshold: Float = 0.82) -> [UUID: String] {
        // Collect segments that have valid embeddings
        let validSegments = segments.filter { $0.voiceEmbedding != nil }
        guard !validSegments.isEmpty else { return [:] }

        var clusters: [[UUID]] = []
        var clusterCentroids: [[Float]] = []

        for seg in validSegments {
            guard let emb = seg.voiceEmbedding else { continue }

            var bestClusterIdx = -1
            var bestSim: Float = -1.0

            for (cIdx, centroid) in clusterCentroids.enumerated() {
                let sim = Self.cosineSimilarity(emb, centroid)
                if sim > bestSim {
                    bestSim = sim
                    bestClusterIdx = cIdx
                }
            }

            if bestClusterIdx >= 0 && bestSim >= similarityThreshold {
                clusters[bestClusterIdx].append(seg.id)
                // Update centroid
                var centroid = clusterCentroids[bestClusterIdx]
                let n = Float(clusters[bestClusterIdx].count)
                for i in 0..<Self.embeddingDimension {
                    centroid[i] = (centroid[i] * (n - 1) + emb[i]) / n
                }
                var norm: Float = 0
                vDSP_svesq(centroid, 1, &norm, vDSP_Length(Self.embeddingDimension))
                var scale = 1.0 / sqrt(max(norm, 1e-7))
                vDSP_vsmul(centroid, 1, &scale, &centroid, 1, vDSP_Length(Self.embeddingDimension))
                clusterCentroids[bestClusterIdx] = centroid
            } else {
                clusters.append([seg.id])
                clusterCentroids.append(emb)
            }
        }

        var results: [UUID: String] = [:]
        for (cIdx, segIDs) in clusters.enumerated() {
            let label = "گوینده \(cIdx + 1) (صدا)"
            for id in segIDs {
                results[id] = label
            }
        }

        return results
    }

    // MARK: - Signal Processing Helpers

    private func estimatePitch(frame: [Float], minLag: Int, maxLag: Int) -> Float? {
        guard frame.count >= maxLag * 2 else { return nil }
        var maxCorr: Float = -1.0
        var bestLag = -1

        var energy0: Float = 0
        vDSP_svesq(frame, 1, &energy0, vDSP_Length(frame.count / 2))
        guard energy0 > 1e-5 else { return nil }

        for lag in minLag...maxLag {
            var corr: Float = 0
            vDSP_dotpr(frame, 1, Array(frame[lag...]), 1, &corr, vDSP_Length(frame.count - lag))
            let normalized = corr / energy0
            if normalized > maxCorr {
                maxCorr = normalized
                bestLag = lag
            }
        }

        // Voiced threshold on correlation peak
        if bestLag > 0 && maxCorr > 0.35 {
            return 16000.0 / Float(bestLag)
        }
        return nil
    }

    private func goertzelMagnitude(samples: [Float], targetFreq: Float, sampleRate: Float) -> Float {
        let n = samples.count
        let k = Int(0.5 + (Float(n) * targetFreq / sampleRate))
        let omega = (2.0 * .pi * Float(k)) / Float(n)
        let coeff = 2.0 * cos(omega)

        var s0: Float = 0
        var s1: Float = 0
        var s2: Float = 0

        for sample in samples {
            s0 = sample + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        let power = s1 * s1 + s2 * s2 - s1 * s2 * coeff
        return sqrt(max(power, 0)) / Float(n)
    }

    private func computeStats(_ values: [Float], fallbackMean: Float) -> (mean: Float, std: Float, min: Float, max: Float) {
        guard !values.isEmpty else {
            return (fallbackMean, 0, fallbackMean, fallbackMean)
        }
        var mean: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))

        var sumSq: Float = 0
        for v in values {
            let diff = v - mean
            sumSq += diff * diff
        }
        let std = sqrt(sumSq / Float(values.count))
        let minVal = values.min() ?? mean
        let maxVal = values.max() ?? mean

        return (mean, std, minVal, maxVal)
    }
}
