import AppKit
import Foundation

/// How dictated text should land in one app. Matched on the frontmost app's
/// bundle ID at recording start. Anything not set here follows the global
/// Transcription settings.
struct AppProfile: Codable, Identifiable, Equatable {
    enum Casing: String, Codable, CaseIterable {
        /// Whatever the model produced (sentence case).
        case asSpoken
        /// Everything lowercase except names, acronyms, and your replacements.
        case lowercase

        var label: String {
            switch self {
            case .asSpoken: return "As spoken"
            case .lowercase: return "lowercase"
            }
        }
    }

    enum TrailingFullStop: String, Codable, CaseIterable {
        case inherit, drop, keep

        var label: String {
            switch self {
            case .inherit: return "Default"
            case .drop: return "Drop"
            case .keep: return "Keep"
            }
        }
    }

    var id = UUID()
    var bundleID: String
    var name: String
    var casing: Casing = .asSpoken
    var trailingFullStop: TrailingFullStop = .inherit
    /// Off skips Apple Intelligence cleanup for this app even when it's on
    /// globally (editors and terminals want predictable text).
    var aiCleanup = true

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Seeded once on first run; every row is editable and deletable.
    static let defaults: [AppProfile] = [
        AppProfile(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", casing: .lowercase, trailingFullStop: .drop),
        AppProfile(bundleID: "com.apple.dt.Xcode", name: "Xcode", aiCleanup: false),
        AppProfile(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", aiCleanup: false),
        AppProfile(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", aiCleanup: false),
        AppProfile(bundleID: "com.apple.Terminal", name: "Terminal", aiCleanup: false),
        AppProfile(bundleID: "com.googlecode.iterm2", name: "iTerm", aiCleanup: false),
        AppProfile(bundleID: "dev.warp.Warp-Stable", name: "Warp", aiCleanup: false),
        AppProfile(bundleID: "com.mitchellh.ghostty", name: "Ghostty", aiCleanup: false),
    ]
}

enum TranscriptCasing {
    private static let acronym = try! NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9]{1,5}\b"#)

    /// Lowercase the text but keep: acronyms (PRD, API, Q3), the words in
    /// `preserving` (Names & phrases, replacement outputs) in their exact case.
    static func lowercase(_ text: String, preserving: [String]) -> String {
        var keep: [(NSRange, String)] = []
        let full = NSRange(text.startIndex..., in: text)
        for match in acronym.matches(in: text, range: full) {
            keep.append((match.range, (text as NSString).substring(with: match.range)))
        }
        for term in preserving where !term.isEmpty {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: full) {
                keep.append((match.range, term))
            }
        }
        let lowered = text.lowercased()
        // Ranges are UTF-16 offsets into the original; a rare script where
        // lowercasing changes length would misplace them, so just lowercase.
        guard lowered.utf16.count == text.utf16.count else { return lowered }
        let result = NSMutableString(string: lowered)
        for (range, original) in keep {
            result.replaceCharacters(in: range, with: original)
        }
        return result as String
    }
}
