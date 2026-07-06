import AppKit

/// Checks GitHub's releases feed for a newer version, on launch and once a
/// day while running (optional, on by default). The only network call asks
/// api.github.com for the latest release tag; nothing about the user or their
/// dictations is sent. Downloading opens the standard DMG from the latest
/// release, so installing an update is open + drag, same as the first install.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// Version string like "1.0.8" when something newer exists, nil when current.
    @Published private(set) var availableVersion: String?
    @Published private(set) var checking = false
    /// True when the last check couldn't reach GitHub, so "no update" isn't
    /// silently conflated with "couldn't check".
    @Published private(set) var lastCheckFailed = false

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
}
