import AppKit
import ServiceManagement

enum HotkeyKey: String, CaseIterable, Identifiable {
    case rightOption
    case leftOption
    case rightCommand
    case rightControl
    case leftControl

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .rightControl: return 62
        case .leftControl: return 59
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption, .leftOption: return .option
        case .rightCommand: return .command
        case .rightControl, .leftControl: return .control
        }
    }

    var label: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        case .leftControl: return "Left ⌃ Control"
        }
    }

    var shortLabel: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .leftOption: return "Left ⌥"
        case .rightCommand: return "Right ⌘"
        case .rightControl: return "Right ⌃"
        case .leftControl: return "Left ⌃"
        }
    }
}

enum ActivationMode: String, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }
    var label: String { self == .hold ? "Hold" : "Toggle" }
}

enum HUDStyle: String, CaseIterable, Identifiable {
    case panel
    case notch

    var id: String { rawValue }
    var label: String { self == .panel ? "Panel" : "Notch" }
}

struct ReplacementRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var find = ""
    var replace = ""
}

/// All user preferences. UserDefaults-backed, applied live (no restart needed).
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var hotkeyKey: HotkeyKey {
        didSet { defaults.set(hotkeyKey.rawValue, forKey: Keys.hotkeyKey) }
    }
    @Published var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }
    @Published var hudStyle: HUDStyle {
        didSet { defaults.set(hudStyle.rawValue, forKey: Keys.hudStyle) }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }
    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }
    @Published var micDeviceUID: String? {
        didSet {
            if let micDeviceUID {
                defaults.set(micDeviceUID, forKey: Keys.micDeviceUID)
            } else {
                defaults.removeObject(forKey: Keys.micDeviceUID)
            }
        }
    }
    @Published var replacements: [ReplacementRule] {
        didSet { persistReplacements() }
    }

    private let defaults = UserDefaults.standard
    private var applyingLoginItem = false

    private enum Keys {
        static let hotkeyKey = "hotkeyKey"
        static let activationMode = "activationMode"
        static let hudStyle = "hudStyle"
        static let replacements = "replacements"
        static let showInMenuBar = "showInMenuBar"
        static let micDeviceUID = "micDeviceUID"
    }

    private init() {
        let d = UserDefaults.standard
        hotkeyKey = HotkeyKey(rawValue: d.string(forKey: Keys.hotkeyKey) ?? "") ?? .rightOption
        activationMode = ActivationMode(rawValue: d.string(forKey: Keys.activationMode) ?? "") ?? .hold
        hudStyle = HUDStyle(rawValue: d.string(forKey: Keys.hudStyle) ?? "") ?? .panel
        launchAtLogin = SMAppService.mainApp.status == .enabled
        showInMenuBar = (d.object(forKey: Keys.showInMenuBar) as? Bool) ?? true
        micDeviceUID = d.string(forKey: Keys.micDeviceUID)
        if let data = d.data(forKey: Keys.replacements),
           let rules = try? JSONDecoder().decode([ReplacementRule].self, from: data) {
            replacements = rules
        } else {
            replacements = []
        }
    }

    /// Case-insensitive, whole-word replacements applied after every transcription.
    func applyReplacements(to text: String) -> String {
        var result = text
        for rule in replacements {
            let find = rule.find.trimmingCharacters(in: .whitespaces)
            guard !find.isEmpty else { continue }

            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: find))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }

            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replace)
            )
        }
        return result
    }

    private func applyLaunchAtLogin() {
        guard !applyingLoginItem else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // System call failed, reflect reality without re-triggering didSet logic.
            applyingLoginItem = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            applyingLoginItem = false
        }
    }

    private func persistReplacements() {
        guard let data = try? JSONEncoder().encode(replacements) else { return }
        defaults.set(data, forKey: Keys.replacements)
    }
}
