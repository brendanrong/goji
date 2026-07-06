import AppKit

/// Checks GitHub's releases feed for a newer version, on launch and once a
/// day while running (optional, on by default). The only network call asks
/// api.github.com for the latest release tag; nothing about the user or their
/// dictations is sent.
///
/// Installing happens in-app: download the notarized DMG, mount it quietly,
/// swap /Applications/Goji.app, relaunch. If Goji isn't running from
/// /Applications (or anything fails), it falls back to opening the DMG the
/// manual way.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum InstallPhase: Equatable {
        case idle
        case downloading(Double)
        case installing
        case failed(String)
    }

    /// Version string like "1.0.8" when something newer exists, nil when current.
    @Published private(set) var availableVersion: String?
    @Published private(set) var checking = false
    /// True when the last check couldn't reach GitHub, so "no update" isn't
    /// silently conflated with "couldn't check".
    @Published private(set) var lastCheckFailed = false
    @Published private(set) var installPhase: InstallPhase = .idle

    static let downloadURL = URL(string: "https://github.com/brendanrong/goji/releases/latest/download/Goji.dmg")!
    private static let apiURL = URL(string: "https://api.github.com/repos/brendanrong/goji/releases/latest")!

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    private var timer: Timer?

    func startAutomaticChecks() {
        stopAutomaticChecks()
        Task { await check() }
        let t = Timer(timeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in
                await UpdateChecker.shared.check()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }

        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            lastCheckFailed = true
            return
        }

        lastCheckFailed = false
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        availableVersion = Self.isNewer(latest, than: Self.currentVersion) ? latest : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func openDownload() {
        NSWorkspace.shared.open(Self.downloadURL)
    }

    // MARK: - In-app install

    /// Self-install only makes sense for the standard install location; a
    /// debug build in DerivedData or an app run from the DMG falls back to
    /// the browser download.
    var canSelfInstall: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    func installUpdate() {
        guard availableVersion != nil else { return }
        switch installPhase {
        case .downloading, .installing:
            return
        case .idle, .failed:
            break
        }
        guard canSelfInstall else {
            openDownload()
            return
        }
        installPhase = .downloading(0)
        Task {
            do {
                let dmg = try await downloadDMG()
                defer { try? FileManager.default.removeItem(at: dmg) }
                installPhase = .installing
                try await Self.applyUpdate(from: dmg)
                relaunch()
            } catch {
                installPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func downloadDMG() async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Goji-Update.dmg")
        let delegate = DownloadDelegate(destination: destination) { fraction in
            Task { @MainActor [weak self] in
                if case .downloading = self?.installPhase {
                    self?.installPhase = .downloading(fraction)
                }
            }
        }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            session.downloadTask(with: Self.downloadURL).resume()
        }
        return destination
    }

    /// Mount, stage next to the current app, swap, unmount. The swap goes
    /// staging-first so a failure can't leave /Applications without a Goji.
    private static func applyUpdate(from dmg: URL) async throws {
        let mount = "/private/tmp/GojiUpdateMount"
        _ = try? await run("/usr/bin/hdiutil", ["detach", mount, "-force"])
        try await runOK("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noautoopen", "-mountpoint", mount])

        do {
            let newApp = URL(fileURLWithPath: mount).appendingPathComponent("Goji.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw GojiError("The update package looks wrong (no Goji.app inside).")
            }
            let current = Bundle.main.bundleURL
            let staging = current.deletingLastPathComponent().appendingPathComponent("Goji-Update.app")
            try? FileManager.default.removeItem(at: staging)
            try await runOK("/usr/bin/ditto", [newApp.path, staging.path])
            // The DMG came from the internet; without this the swapped-in app
            // gets a "downloaded from the internet" interrogation on launch.
            _ = try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
            try FileManager.default.trashItem(at: current, resultingItemURL: nil)
            try FileManager.default.moveItem(at: staging, to: current)
        } catch {
            _ = try? await run("/usr/bin/hdiutil", ["detach", mount])
            throw error
        }
        _ = try? await run("/usr/bin/hdiutil", ["detach", mount])
    }

    /// The relaunch helper outlives this process: sleep past our exit, open
    /// the fresh copy.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.7; /usr/bin/open \"\(Bundle.main.bundlePath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func runOK(_ tool: String, _ arguments: [String]) async throws {
        let status = try await run(tool, arguments)
        guard status == 0 else {
            throw GojiError("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(status)).")
        }
    }

    /// Streams the DMG to disk with byte progress; non-200 responses fail
    /// instead of saving an error page.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
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
                moveError = GojiError("Update download failed (HTTP \(status)).")
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
