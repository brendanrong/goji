import FluidAudio
import Foundation

/// Downloads the Parakeet model as a single zip from Goji's GitHub release
/// (fast CDN, one file, real byte progress) instead of FluidAudio's
/// file-by-file HuggingFace crawl, which stalls for many users. The zip is a
/// straight archive of the FluidAudio cache folder, so after extraction the
/// normal loading path finds it as if FluidAudio downloaded it itself.
enum ModelFetcher {
    /// Fixed release tag that only hosts the model asset. Not an app release;
    /// it's created once with `--latest=false` so it never becomes "Latest".
    private static let assetURL = URL(
        string: "https://github.com/brendanrong/goji/releases/download/models-v3/parakeet-tdt-0.6b-v3-coreml.zip"
    )!

    enum FetchError: LocalizedError {
        case badStatus(Int)
        case extractFailed
        case verifyFailed

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Model download failed (HTTP \(code))."
            case .extractFailed: return "Couldn't unpack the model archive."
            case .verifyFailed: return "The downloaded model is incomplete."
            }
        }
    }

    /// Downloads and unpacks the model into FluidAudio's cache location.
    /// Throws if anything goes wrong; the caller falls back to HuggingFace.
    static func fetch(progress: @escaping @Sendable (Double) -> Void) async throws {
        let modelsRoot = AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)

        let zip = modelsRoot.appendingPathComponent("parakeet-v3-download.zip")
        defer { try? FileManager.default.removeItem(at: zip) }

        try await download(to: zip, progress: progress)
        try await extract(zip, into: modelsRoot)

        guard AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3) else {
            throw FetchError.verifyFailed
        }
    }

    private static func download(to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = Delegate(destination: destination, onProgress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            session.downloadTask(with: assetURL).resume()
        }
    }

    private static func extract(_ zip: URL, into directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, directory.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FetchError.extractFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Streams the zip to disk and reports byte progress. 404s (asset missing)
    /// surface as errors instead of saving GitHub's error page as a "model".
    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        let destination: URL
        let onProgress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        private var moveError: Error?

        init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
        ) {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                moveError = FetchError.badStatus(status)
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                moveError = error
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
            } else if let moveError {
                continuation?.resume(throwing: moveError)
            } else {
                continuation?.resume()
            }
            continuation = nil
        }
    }
}
