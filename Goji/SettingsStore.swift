import AppKit
import ServiceManagement

enum HotkeyKey: String, CaseIterable, Identifiable {
    case rightOption
    case leftOption
    case rightCommand
    case rightControl
    case leftControl
    case fnGlobe
    case rightShift
    case leftShift

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .rightControl: return 62
        case .leftControl: return 59
        case .fnGlobe: return 63
        case .rightShift: return 60
        case .leftShift: return 56
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption, .leftOption: return .option
        case .rightCommand: return .command
        case .rightControl, .leftControl: return .control
        case .fnGlobe: return .function
        case .rightShift, .leftShift: return .shift
        }
    }

    /// Device-dependent modifier bit, distinguishes left vs right of the same
    /// key. Fn has no left/right twin, so its plain flag bit works.
    var deviceMask: UInt {
        switch self {
        case .rightOption: return 0x40
        case .leftOption: return 0x20
        case .rightCommand: return 0x10
        case .rightControl: return 0x2000
        case .leftControl: return 0x01
        case .fnGlobe: return NSEvent.ModifierFlags.function.rawValue
        case .rightShift: return 0x04
        case .leftShift: return 0x02
        }
    }

    var label: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        case .leftControl: return "Left ⌃ Control"
        case .fnGlobe: return "Fn Globe"
        case .rightShift: return "Right ⇧ Shift"
        case .leftShift: return "Left ⇧ Shift"
        }
    }

    var shortLabel: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .leftOption: return "Left ⌥"
        case .rightCommand: return "Right ⌘"
        case .rightControl: return "Right ⌃"
        case .leftControl: return "Left ⌃"
        case .fnGlobe: return "Fn"
        case .rightShift: return "Right ⇧"
        case .leftShift: return "Left ⇧"
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

/// What happens to other audio while recording.
enum WhileDictating: String, CaseIterable, Identifiable {
    case nothing
    case quieter
    case pause

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nothing: return "Do Nothing"
        case .quieter: return "Quieter"
        case .pause: return "Pause Media"
        }
    }
}

enum SoundPack: String, CaseIterable, Identifiable {
    case minimal
    case wood
    case classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .wood: return "Wood"
        case .classic: return "Classic"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct ReplacementRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var find = ""
    var replace = ""
}

/// A name or term the speaker uses; AI cleanup nudges close mishearings to
/// these exact spellings.
struct VocabWord: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
}

/// A user-recorded combination of modifier keys (e.g. Fn + Right ⌃).
/// deviceMask is the union of the required bits; all must be held together.
/// A zero mask means "selected Custom but nothing recorded yet" and falls
/// back to the preset key.
struct CustomHotkey: Codable, Equatable {
    var deviceMask: UInt = 0
    var label: String = ""
}

/// All user preferences. UserDefaults-backed, applied live (no restart needed).
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var hotkeyKey: HotkeyKey {
        didSet { defaults.set(hotkeyKey.rawValue, forKey: Keys.hotkeyKey) }
    }
    /// Non-nil with a non-zero mask overrides hotkeyKey with a recorded combo.
    @Published var customHotkey: CustomHotkey? {
        didSet { persistCustomHotkey() }
    }
    @Published var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }
    @Published var hudStyle: HUDStyle {
        didSet { defaults.set(hudStyle.rawValue, forKey: Keys.hudStyle) }
    }
    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }
    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }
    @Published var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Keys.showInDock)
            applyDockPolicy()
        }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }
    /// Hold mode only: double-tapping the hotkey locks recording hands-free.
    @Published var doubleTapLock: Bool {
        didSet { defaults.set(doubleTapLock, forKey: Keys.doubleTapLock) }
    }
    /// What happens to other audio while recording: nothing, duck, or pause.
    @Published var whileDictating: WhileDictating {
        didSet { defaults.set(whileDictating.rawValue, forKey: Keys.whileDictating) }
    }
    /// Which cue set plays for start/stop.
    @Published var soundPack: SoundPack {
        didSet { defaults.set(soundPack.rawValue, forKey: Keys.soundPack) }
    }
    /// Which speech model transcribes. Views only offer installed models.
    @Published var selectedModel: SpeechModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel) }
    }
    @Published var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }
    /// Drop the final period the model tacks onto every utterance.
    @Published var removeTrailingFullStop: Bool {
        didSet { defaults.set(removeTrailingFullStop, forKey: Keys.removeTrailingFullStop) }
    }
    /// Ask GitHub once a day whether a newer release exists.
    @Published var autoCheckUpdates: Bool {
        didSet {
            defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates)
            if autoCheckUpdates {
                UpdateChecker.shared.startAutomaticChecks()
            } else {
                UpdateChecker.shared.stopAutomaticChecks()
            }
        }
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
    @Published var vocabulary: [VocabWord] {
        didSet { persistVocabulary() }
    }

    /// Non-empty vocabulary entries, trimmed, ready for the cleanup prompt.
    var vocabularyTerms: [String] {
        vocabulary
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }


    private let defaults = UserDefaults.standard
    private var applyingLoginItem = false

    private enum Keys {
        static let hotkeyKey = "hotkeyKey"
        static let customHotkey = "customHotkey"
        static let activationMode = "activationMode"
        static let hudStyle = "hudStyle"
        static let appearance = "appearance"
        static let replacements = "replacements"
        static let vocabulary = "vocabularyWords"
        static let showInMenuBar = "showInMenuBar"
        static let showInDock = "showInDock"
        static let micDeviceUID = "micDeviceUID"
        static let playSounds = "playSounds"
        static let doubleTapLock = "doubleTapLock"
        static let whileDictating = "whileDictating"
        static let soundPack = "soundPack"
        static let selectedModel = "selectedModel"
        static let legacyPauseMedia = "pauseMediaWhileDictating"
        static let legacyMuteWhileDictating = "muteWhileDictating"
        static let cleanupEnabled = "cleanupEnabled"
        static let removeTrailingFullStop = "removeTrailingFullStop"
        static let autoCheckUpdates = "autoCheckUpdates"
    }

    private init() {
        let d = UserDefaults.standard
        hotkeyKey = HotkeyKey(rawValue: d.string(forKey: Keys.hotkeyKey) ?? "") ?? .rightOption
        if let data = d.data(forKey: Keys.customHotkey),
           let hotkey = try? JSONDecoder().decode(CustomHotkey.self, from: data) {
            customHotkey = hotkey
        } else {
            customHotkey = nil
        }
        activationMode = ActivationMode(rawValue: d.string(forKey: Keys.activationMode) ?? "") ?? .hold
        hudStyle = HUDStyle(rawValue: d.string(forKey: Keys.hudStyle) ?? "") ?? .notch
        appearance = AppearanceMode(rawValue: d.string(forKey: Keys.appearance) ?? "") ?? .system
        launchAtLogin = SMAppService.mainApp.status == .enabled
        showInMenuBar = (d.object(forKey: Keys.showInMenuBar) as? Bool) ?? true
        showInDock = (d.object(forKey: Keys.showInDock) as? Bool) ?? true
        micDeviceUID = d.string(forKey: Keys.micDeviceUID)
        playSounds = (d.object(forKey: Keys.playSounds) as? Bool) ?? true
        doubleTapLock = (d.object(forKey: Keys.doubleTapLock) as? Bool) ?? true
        if let raw = d.string(forKey: Keys.whileDictating), let mode = WhileDictating(rawValue: raw) {
            whileDictating = mode
        } else {
            // Migrate the old pause/mute toggles: on meant pause.
            let legacyOn = (d.object(forKey: Keys.legacyPauseMedia) as? Bool)
                ?? d.bool(forKey: Keys.legacyMuteWhileDictating)
            whileDictating = legacyOn ? .pause : .nothing
        }
        soundPack = SoundPack(rawValue: d.string(forKey: Keys.soundPack) ?? "") ?? .minimal
        selectedModel = SpeechModel(rawValue: d.string(forKey: Keys.selectedModel) ?? "") ?? .standard
        cleanupEnabled = d.bool(forKey: Keys.cleanupEnabled)
        removeTrailingFullStop = d.bool(forKey: Keys.removeTrailingFullStop)
        autoCheckUpdates = (d.object(forKey: Keys.autoCheckUpdates) as? Bool) ?? true
        if let data = d.data(forKey: Keys.replacements),
           let rules = try? JSONDecoder().decode([ReplacementRule].self, from: data) {
            replacements = rules
        } else {
            replacements = []
        }
        if let data = d.data(forKey: Keys.vocabulary),
           let words = try? JSONDecoder().decode([VocabWord].self, from: data) {
            vocabulary = words
        } else {
            vocabulary = []
        }
    }

    /// The modifier bits the hotkey monitor must see held simultaneously.
    var effectiveHotkeyMask: UInt {
        if let customHotkey, customHotkey.deviceMask != 0 {
            return customHotkey.deviceMask
        }
        return hotkeyKey.deviceMask
    }

    /// What the shortcut is called in hints: "Right ⌥" or "Fn + Right ⌃".
    var hotkeyDisplay: String {
        if let customHotkey, customHotkey.deviceMask != 0 {
            return customHotkey.label
        }
        return hotkeyKey.shortLabel
    }

    private func persistCustomHotkey() {
        if let customHotkey, let data = try? JSONEncoder().encode(customHotkey) {
            defaults.set(data, forKey: Keys.customHotkey)
        } else {
            defaults.removeObject(forKey: Keys.customHotkey)
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

    /// LSUIElement keeps the app out of the Dock at process start;
    /// this flips it at runtime based on the user's preference.
    func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    /// Forces light/dark app-wide, or follows the system when .system.
    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
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

    private func persistVocabulary() {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        defaults.set(data, forKey: Keys.vocabulary)
    }
}
