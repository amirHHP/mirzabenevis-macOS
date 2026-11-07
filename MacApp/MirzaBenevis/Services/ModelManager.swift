import Foundation
import AppKit

enum WhisperModelSize: String, CaseIterable, Identifiable, Codable {
    case persianTurbo = "persian-turbo"
    case persianTurboQ5 = "persian-turbo-q5"
    case turbo = "turbo"
    case largeV3 = "large-v3"
    case medium = "medium"
    case small = "small"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .persianTurbo:
            return "Persian Turbo Givia (~1.6 GB) — فاین‌تیون مکالمه و عامیانه فارسی (پیشنهادی)"
        case .persianTurboQ5:
            return "Persian Turbo Q5 (~560 MB) — فاین‌تیون فارسی سبک و فشرده"
        case .turbo:
            return "Large v3 Turbo (~1.6 GB) — رسمی OpenAI (سریع و بهینه)"
        case .largeV3:
            return "Large v3 (~3.1 GB) — حداکثر دقت OpenAI (کامل‌ترین مدل چندزبانه)"
        case .medium:
            return "Medium (~1.5 GB) — چندزبانه بسیار دقیق"
        case .small:
            return "Small (~466 MB) — استاندارد سبک و سریع"
        }
    }

    var downloadFileName: String {
        switch self {
        case .persianTurbo:
            return "ggml-persian-v3-turbo.bin"
        case .persianTurboQ5:
            return "ggml-large-v3-turbo-persian-q5_0.bin"
        case .turbo:
            return "ggml-large-v3-turbo.bin"
        case .largeV3:
            return "ggml-large-v3.bin"
        default:
            return "ggml-\(rawValue).bin"
        }
    }

    /// Multiple mirror URLs – tried in order until one works.
    var downloadURLs: [URL] {
        switch self {
        case .persianTurbo:
            return [
                URL(string: "https://huggingface.co/givia/whisper-large-v3-turbo-persian/resolve/main/ggml-persian-v3-turbo.bin")!
            ]
        case .persianTurboQ5:
            return [
                URL(string: "https://huggingface.co/pejmans21/whisper-large-v3-turbo-persian-ggml/resolve/main/ggml-large-v3-turbo-persian-q5_0.bin")!
            ]
        case .largeV3:
            return [
                URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
                URL(string: "https://github.com/ggerganov/whisper.cpp/releases/download/v1.7.4/ggml-large-v3.bin")!,
            ]
        case .turbo:
            return [
                URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
                URL(string: "https://github.com/ggerganov/whisper.cpp/releases/download/v1.7.4/ggml-large-v3-turbo.bin")!,
            ]
        default:
            return [
                URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(downloadFileName)")!,
                URL(string: "https://github.com/ggerganov/whisper.cpp/releases/download/v1.7.4/\(downloadFileName)")!,
            ]
        }
    }

    var approximateSizeMB: Int {
        switch self {
        case .persianTurbo: return 1600
        case .persianTurboQ5: return 560
        case .turbo: return 1600
        case .largeV3: return 3100
        case .medium: return 1500
        case .small: return 466
        }
    }
}

// MARK: - Download Error

enum ModelDownloadError: LocalizedError {
    case allMirrorsFailed(underlyingErrors: [Error])
    case cancelled
    case invalidResponse(statusCode: Int)
    case fileOperationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .allMirrorsFailed(let errors):
            let msgs = errors.map { $0.localizedDescription }.joined(separator: "\n  • ")
            return "دانلود از همه آدرس‌ها ناموفق بود:\n  • \(msgs)"
        case .cancelled:
            return "دانلود لغو شد."
        case .invalidResponse(let code):
            return "پاسخ نامعتبر از سرور (کد: \(code))"
        case .fileOperationFailed(let e):
            return "خطا در ذخیره فایل: \(e.localizedDescription)"
        }
    }
}

// MARK: - ModelManager

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var downloadError: String?
    @Published private(set) var downloadSpeed: String = ""
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var currentlyDownloadingSize: WhisperModelSize?

    static let shared = ModelManager()

    private var activeDelegate: DownloadDelegate?
    private var activeDownloadTask: Task<Void, Error>?

    var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MirzaBenevis/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func modelPath(for size: WhisperModelSize) -> URL {
        modelsDirectory.appendingPathComponent(size.downloadFileName)
    }

    func resumeDataURL(for size: WhisperModelSize) -> URL {
        modelsDirectory.appendingPathComponent("\(size.downloadFileName).resumedata")
    }

    func coreMLModelPath(for size: WhisperModelSize) -> URL {
        let base = size.downloadFileName.replacingOccurrences(of: ".bin", with: "")
        return modelsDirectory.appendingPathComponent("\(base)-encoder.mlmodelc")
    }

    func isCoreMLAvailable(for size: WhisperModelSize) -> Bool {
        let path = coreMLModelPath(for: size).path
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
        let base = size.downloadFileName.replacingOccurrences(of: ".bin", with: "")
        if Bundle.main.url(forResource: "\(base)-encoder", withExtension: "mlmodelc") != nil {
            return true
        }
        return false
    }

    func openModelsDirectory() {
        NSWorkspace.shared.open(modelsDirectory)
    }

    func isModelDownloaded(_ size: WhisperModelSize) -> Bool {
        if FileManager.default.fileExists(atPath: modelPath(for: size).path) {
            return true
        }
        if Bundle.main.url(forResource: size.downloadFileName, withExtension: nil) != nil {
            return true
        }
        return false
    }

    func ensureModel(_ size: WhisperModelSize) async throws -> URL {
        let path = modelPath(for: size)
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        if let bundlePath = Bundle.main.url(forResource: size.downloadFileName, withExtension: nil) {
            return bundlePath
        }
        try await downloadModel(size)
        return path
    }

    /// Cancel the in-progress download safely, saving resume data if available.
    func cancelDownload() {
        if let currentSize = currentlyDownloadingSize {
            let resumePath = resumeDataURL(for: currentSize)
            let sizeName = currentSize.rawValue
            activeDelegate?.cancel { data in
                if let data, !data.isEmpty {
                    try? data.write(to: resumePath, options: .atomic)
                    print("[ModelManager] ✅ Saved \(data.count) bytes of resume data for \(sizeName)")
                }
            }
        } else {
            activeDelegate?.cancel()
        }
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDelegate = nil
        isDownloading = false
        currentlyDownloadingSize = nil
        downloadProgress = 0
        downloadedBytes = 0
        totalBytes = 0
        statusMessage = "دانلود لغو شد"
        downloadSpeed = ""
    }

    /// Download with real progress, retries across mirrors, and cancel support.
    func downloadModel(_ size: WhisperModelSize) async throws {
        // Prevent concurrent or duplicate downloads
        if isDownloading {
            if currentlyDownloadingSize == size, let existing = activeDownloadTask {
                print("[ModelManager] Already downloading \(size.rawValue), joining existing task")
                try await existing.value
                return
            } else {
                print("[ModelManager] Cancelling existing download to start \(size.rawValue)")
                cancelDownload()
            }
        }

        let task = Task { @MainActor in
            try await executeDownload(size)
        }
        activeDownloadTask = task
        try await task.value
    }

    private func executeDownload(_ size: WhisperModelSize) async throws {
        isDownloading = true
        currentlyDownloadingSize = size
        downloadProgress = 0
        downloadedBytes = 0
        totalBytes = 0
        downloadError = nil
        downloadSpeed = ""
        statusMessage = "در حال اتصال به سرور..."
        defer {
            isDownloading = false
            currentlyDownloadingSize = nil
            activeDownloadTask = nil
            activeDelegate = nil
        }

        let destination = modelPath(for: size)
        var mirrorErrors: [Error] = []

        for (index, url) in size.downloadURLs.enumerated() {
            let mirrorName = index == 0 ? "Hugging Face" : "GitHub"
            statusMessage = "در حال دانلود از \(mirrorName)..."
            downloadProgress = 0
            downloadedBytes = 0
            totalBytes = 0
            downloadSpeed = ""

            do {
                try await downloadFromURL(url, to: destination, modelName: size.downloadFileName, size: size)
                // Success!
                downloadProgress = 1
                statusMessage = "✅ مدل دانلود شد"
                downloadError = nil
                return
            } catch is CancellationError {
                throw ModelDownloadError.cancelled
            } catch let error as ModelDownloadError where error.errorDescription?.contains("لغو") == true {
                throw error
            } catch {
                mirrorErrors.append(error)
                print("[ModelManager] Mirror \(mirrorName) failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: resumeDataURL(for: size))
                if index < size.downloadURLs.count - 1 {
                    statusMessage = "آدرس \(mirrorName) ناموفق، تلاش بعدی..."
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        let finalError = ModelDownloadError.allMirrorsFailed(underlyingErrors: mirrorErrors)
        downloadError = finalError.localizedDescription
        statusMessage = "❌ دانلود ناموفق"
        throw finalError
    }

    // MARK: - Private download implementation

    private func downloadFromURL(_ url: URL, to destination: URL, modelName: String, size: WhisperModelSize) async throws {
        let resumeURL = resumeDataURL(for: size)
        let resumeData = try? Data(contentsOf: resumeURL)

        // Build a URLSession with a delegate for progress tracking
        let delegate = DownloadDelegate()
        activeDelegate = delegate

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30       // 30s for initial response
        config.timeoutIntervalForResource = 7200    // 2 hours max for large models
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 1

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let downloadTask: URLSessionDownloadTask
        if let data = resumeData, !data.isEmpty {
            print("[ModelManager] Resuming download with \(data.count) bytes of resume data")
            statusMessage = "ادامه دانلود قبلی..."
            downloadTask = session.downloadTask(withResumeData: data)
        } else {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) MirzaBenevis/1.0", forHTTPHeaderField: "User-Agent")
            downloadTask = session.downloadTask(with: request)
        }

        delegate.startTask(downloadTask)

        // Observe progress on main actor
        let progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.downloadProgress = delegate.progress
                self.downloadSpeed = delegate.formattedSpeed
                self.downloadedBytes = delegate.totalBytesWritten
                self.totalBytes = delegate.totalBytesExpected
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        defer { progressTask.cancel() }

        // Wait for completion
        let result = await delegate.waitForCompletion()

        switch result {
        case .success(let tempURL):
            // Validate response
            if let httpResponse = delegate.httpResponse {
                guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                    throw ModelDownloadError.invalidResponse(statusCode: httpResponse.statusCode)
                }
            }

            // Validate that the downloaded file is a real model file (minimum 10MB)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let fileSize = attrs[.size] as? Int64, fileSize < 10_000_000 {
                try? FileManager.default.removeItem(at: tempURL)
                throw ModelDownloadError.invalidResponse(statusCode: delegate.httpResponse?.statusCode ?? 400)
            }

            do {
                // Remove old model if exists
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                // Clean up resume data file upon successful completion
                try? FileManager.default.removeItem(at: resumeURL)
                try FileManager.default.moveItem(at: tempURL, to: destination)
            } catch {
                throw ModelDownloadError.fileOperationFailed(error)
            }

        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                throw ModelDownloadError.cancelled
            }
            // If resuming failed because resume data was expired or invalid, delete it so next try starts fresh
            try? FileManager.default.removeItem(at: resumeURL)
            throw error
        }
    }
}

// MARK: - DownloadDelegate

/// Handles URLSession download callbacks and bridges to async/await.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Result<URL, Error>, Never>?
    private var downloadTask: URLSessionDownloadTask?

    private(set) var progress: Double = 0
    private(set) var totalBytesWritten: Int64 = 0
    private(set) var totalBytesExpected: Int64 = 0
    private(set) var httpResponse: HTTPURLResponse?

    // Speed tracking
    private var lastBytesWritten: Int64 = 0
    private var lastSpeedUpdate = Date()
    private var currentSpeed: Double = 0 // bytes per second

    var formattedSpeed: String {
        lock.lock()
        let speed = currentSpeed
        lock.unlock()
        if speed < 1 { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }

    func startTask(_ task: URLSessionDownloadTask) {
        lock.lock()
        downloadTask = task
        lock.unlock()
        task.resume()
    }

    func cancel(onProduceResumeData: (@Sendable (Data?) -> Void)? = nil) {
        lock.lock()
        let task = downloadTask
        lock.unlock()
        if let onProduceResumeData {
            task?.cancel(byProducingResumeData: onProduceResumeData)
        } else {
            task?.cancel()
        }
    }

    func waitForCompletion() async -> Result<URL, Error> {
        await withCheckedContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        lock.lock()
        // Ignore tiny responses (like 302 redirects or small web error bodies)
        if totalBytesExpectedToWrite > 1_000_000 {
            self.totalBytesWritten = totalBytesWritten
            self.totalBytesExpected = totalBytesExpectedToWrite
            let newProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            self.progress = max(self.progress, min(newProgress, 1.0))
        }

        // Calculate speed
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedUpdate)
        if elapsed >= 0.8 {
            let bytesInInterval = totalBytesWritten - lastBytesWritten
            if bytesInInterval >= 0 {
                currentSpeed = Double(bytesInInterval) / elapsed
            }
            lastBytesWritten = totalBytesWritten
            lastSpeedUpdate = now
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Copy to a temp file we control (the system deletes `location` after this returns)
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent(UUID().uuidString + ".bin")
        do {
            try FileManager.default.moveItem(at: location, to: tmpFile)
            lock.lock()
            httpResponse = downloadTask.response as? HTTPURLResponse
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(returning: .success(tmpFile))
        } catch {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(returning: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: .failure(error))
    }
}
