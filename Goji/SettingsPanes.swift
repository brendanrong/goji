import AppKit
import SwiftUI

struct GeneralPane: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        PaneScaffold(title: "General", subtitle: "Shortcut and app behavior") {
            SectionHeader("Dictation")
            SettingsCard {
                SettingsRow("Recording shortcut", subtitle: shortcutHint) {
                    Picker("Recording shortcut", selection: hotkeyChoice) {
                        ForEach(HotkeyKey.allCases) { key in
                            Text(key.label).tag(HotkeyChoice.preset(key))
                        }
                        Text("Custom Combo…").tag(HotkeyChoice.custom)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if settings.customHotkey != nil {
                    Divider()
                    SettingsRow("Custom combo",
                                subtitle: "Click record, hold any mix of Fn ⌃ ⌥ ⌘ ⇧ (left and right count as different keys), then release.") {
                        HotkeyRecorder()
                    }
                }
                Divider()
                SettingsRow("Mode") {
                    Picker("Mode", selection: $settings.activationMode) {
                        ForEach(ActivationMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            CaptionText(modeHint)

            SectionHeader("Microphone")
            MicrophoneSection()

            SectionHeader("Fine-tuning")
            SettingsCard {
                SettingsRow("Recording display",
                            subtitle: "Notch blends into the camera housing on MacBooks and draws its own island on external displays.") {
                    Picker("Recording display", selection: $settings.hudStyle) {
                        ForEach(HUDStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                if settings.activationMode == .hold {
                    SettingsRow("Double-tap to lock recording",
                                subtitle: "Tap twice quickly to keep recording hands-free, tap again to finish.") {
                        Toggle("Double-tap to lock recording", isOn: $settings.doubleTapLock)
                            .labelsHidden()
                    }
                    Divider()
                }
                SettingsRow("Play start/stop sounds",
                            subtitle: "Cues when recording begins and ends, in the pack of your choice.") {
                    HStack(spacing: 10) {
                        Picker("Sound pack", selection: $settings.soundPack) {
                            ForEach(SoundPack.allCases) { pack in
                                Text(pack.label).tag(pack)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!settings.playSounds)
                        Toggle("Play start/stop sounds", isOn: $settings.playSounds)
                            .labelsHidden()
                    }
                }
                Divider()
                SettingsRow("While dictating",
                            subtitle: "Quieter ducks your speakers to 20% and restores them after (falls back to Pause on outputs without volume control). Pause stops music or video and resumes it.") {
                    Picker("While dictating", selection: $settings.whileDictating) {
                        ForEach(WhileDictating.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SectionHeader("System")
            SettingsCard {
                SettingsRow("Appearance",
                            subtitle: "Follow the system, or keep Goji light or dark.") {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingsRow("Launch at login",
                            subtitle: "Open Goji automatically when you log in.") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Show in menu bar",
                            subtitle: "The berry icon in the status bar.") {
                    Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Show in Dock",
                            subtitle: "Clicking the Dock icon opens Settings.") {
                    Toggle("Show in Dock", isOn: $settings.showInDock)
                        .labelsHidden()
                }
            }
            if !settings.showInMenuBar {
                Text("Icon hidden. Launch Goji again from Spotlight or Finder to bring it back.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var hotkeyChoice: Binding<HotkeyChoice> {
        Binding(
            get: {
                settings.customHotkey != nil ? .custom : .preset(settings.hotkeyKey)
            },
            set: { choice in
                switch choice {
                case .preset(let key):
                    settings.customHotkey = nil
                    settings.hotkeyKey = key
                case .custom:
                    if settings.customHotkey == nil {
                        settings.customHotkey = CustomHotkey()
                    }
                }
            }
        )
    }

    private var shortcutHint: String? {
        (settings.effectiveHotkeyMask & NSEvent.ModifierFlags.function.rawValue) != 0
            ? "If pressing Fn also opens emoji or switches input source, set \"Press 🌐 key to\" to \"Do Nothing\" in System Settings > Keyboard."
            : nil
    }

    private var modeHint: String {
        switch settings.activationMode {
        case .hold:
            return settings.doubleTapLock
                ? "Hold \(settings.hotkeyDisplay), speak, release. Double-tap to keep recording hands-free, tap again to finish. Esc cancels."
                : "Hold \(settings.hotkeyDisplay), speak, release. Esc cancels."
        case .toggle:
            return "Tap \(settings.hotkeyDisplay) to start, tap again to finish. Esc cancels."
        }
    }
}

/// Picker selection for the shortcut row: one of the presets, or a recorded combo.
enum HotkeyChoice: Hashable {
    case preset(HotkeyKey)
    case custom
}

/// Mic picker + live level test, embedded in General.
struct MicrophoneSection: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var devices: [MicDevices.Device] = []
    @StateObject private var micPreview = MicLevelPreview()

    var body: some View {
        SettingsCard {
            SettingsRow("Input device",
                        subtitle: "Used from the next recording. Falls back to the system default if unavailable.") {
                Picker("Input device", selection: $settings.micDeviceUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                    if let saved = settings.micDeviceUID, !devices.contains(where: { $0.uid == saved }) {
                        Text("Saved device (unavailable)").tag(String?.some(saved))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingsRow(micPreview.running ? "Listening…" : "Check your input level") {
                HStack(spacing: 12) {
                    if micPreview.running {
                        WaveformBars(level: micPreview.level, color: .green, barCount: 18, maxHeight: 14)
                    }
                    Button(micPreview.running ? "Stop Test" : "Test Mic") {
                        micPreview.toggle(deviceUID: settings.micDeviceUID)
                    }
                }
            }
        }
        .onAppear { devices = MicDevices.inputDevices() }
        .onDisappear { micPreview.stop() }
        .onChange(of: settings.micDeviceUID) { _, _ in
            if micPreview.running {
                micPreview.stop()
                micPreview.toggle(deviceUID: settings.micDeviceUID)
            }
        }
    }
}

struct TranscriptionPane: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        PaneScaffold(title: "Transcription", subtitle: "What happens to your words, in order") {
            SectionHeader("Names & phrases")
            SettingsCard {
                ForEach($settings.vocabulary) { $word in
                    HStack {
                        TextField("Name, team, or term", text: $word.text)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            settings.vocabulary.removeAll { $0.id == word.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                SettingsRow("Words Goji keeps mishearing",
                            subtitle: "Add each one once: people, teams, product names, jargon.") {
                    Button("Add Word") {
                        settings.vocabulary.append(VocabWord())
                    }
                }
            }
            CaptionText("AI cleanup nudges close mishearings to these exact spellings ('Jaken' becomes 'Jachin'). Needs the cleanup toggle on. For stubborn repeat offenders, add a Word replacement below.")

            SectionHeader("AI cleanup")
            SettingsCard {
                SettingsRow("Clean up transcripts with Apple Intelligence") {
                    Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
                        .labelsHidden()
                        .disabled(!Cleaner.isSupported)
                }
            }
            CaptionText(Cleaner.unavailabilityHint
                ?? "Removes filler words, applies self-corrections like 'scratch that', and turns 'new line' into a real line break. The only option on this pane that needs Apple Intelligence.")

            SectionHeader("Formatting")
            SettingsCard {
                SettingsRow("Remove the full stop at the end",
                            subtitle: "Drops the final period the model adds to every dictation. Question marks and exclamations stay.") {
                    Toggle("Remove the full stop at the end", isOn: $settings.removeTrailingFullStop)
                        .labelsHidden()
                }
            }

            SectionHeader("Word replacements")
            SettingsCard {
                ForEach($settings.replacements) { $rule in
                    HStack {
                        TextField("Replace", text: $rule.find)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("With", text: $rule.replace)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            settings.replacements.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                SettingsRow("Add a rule") {
                    Button("Add Replacement") {
                        settings.replacements.append(ReplacementRule())
                    }
                }
            }
            CaptionText("Literal find and replace, applied last. Case-insensitive, whole words. For name fixes, prefer Names & phrases at the top.")
        }
    }

}

struct ModelsPane: View {
    @ObservedObject private var library = ModelLibrary.shared

    var body: some View {
        PaneScaffold(title: "Models", subtitle: "The speech model that turns your voice into text") {
            SettingsCard {
                ForEach(SpeechModel.allCases) { model in
                    if model != SpeechModel.allCases.first {
                        Divider()
                    }
                    ModelRow(model: model)
                }
            }
            if let error = library.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            CaptionText("Everything runs on this Mac. Switching models applies from your next dictation.")

            SectionHeader("Storage")
            SettingsCard {
                SettingsRow("Models on disk",
                            subtitle: "\(library.totalSizeOnDisk()) in Application Support > FluidAudio > Models.") {
                    Button("Show in Finder") {
                        library.revealInFinder()
                    }
                }
            }
        }
    }
}

/// One model in the list: name, badges, description, and the state control
/// (Download with progress, Use, Remove, or In Use).
struct ModelRow: View {
    let model: SpeechModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var library = ModelLibrary.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(.semibold)
                    if model == .standard {
                        TagBadge("Default")
                    }
                }
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(model.languagesLabel)  ·  \(model.approxDownload)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            control
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var control: some View {
        if let progress = library.downloading[model] {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: progress.fraction)
                    .frame(width: 110)
                Text("\(Int(progress.fraction * 100))%  \(progress.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if Transcriber.availableLocally(model) {
            if settings.selectedModel == model {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("In Use")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                HStack(spacing: 8) {
                    Button("Use") {
                        settings.selectedModel = model
                    }
                    if model.isInstalled {
                        Button {
                            library.remove(model)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove the downloaded files")
                    }
                }
            }
        } else {
            Button("Download") {
                library.download(model)
            }
        }
    }
}

/// Small capsule label ("Default").
struct TagBadge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
    }
}

struct HistoryPane: View {
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        PaneScaffold(title: "History", subtitle: "Recent transcripts, stored only on this Mac") {
            if history.items.isEmpty {
                SettingsCard {
                    Text("No transcripts yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            } else {
                SettingsCard {
                    ForEach(history.items.prefix(8)) { item in
                        HStack(alignment: .top) {
                            Text(item.text)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.text, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy")
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                    SettingsRow("Remove all transcripts") {
                        Button("Clear History", role: .destructive) {
                            history.clear()
                        }
                    }
                }
            }
        }
    }
}

struct AboutPane: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        PaneScaffold(title: "About", subtitle: "Version info and support") {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goji")
                        .font(.title2.bold())
                    Text(version)
                        .foregroundStyle(.secondary)
                    Text("Local, private dictation for macOS")
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                // Re-check whenever About opens, not just at launch.
                Task { await updates.check() }
            }

            Text("Hold a key, talk, release, and your words paste where your cursor is. Speech is transcribed entirely on this Mac.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Signed and notarized by Apple")
                }
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("No cloud, no account, no telemetry. Free forever.")
                }
            }
            .font(.callout)

            Text("Built by Brendan Rong.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                updatesControl
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/brendanrong/goji/issues")!)
                } label: {
                    Label("Report a Problem", systemImage: "envelope")
                }
            }
            Text(updateStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    private var version: String {
        "Version " + UpdateChecker.currentVersion
    }

    @ViewBuilder
    private var updatesControl: some View {
        switch updates.installPhase {
        case .downloading(let fraction):
            ProgressView(value: fraction)
                .frame(width: 110)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Button("Download in Browser") {
                updates.openDownload()
            }
        case .idle:
            if let available = updates.availableVersion {
                Button {
                    updates.installUpdate()
                } label: {
                    Label("Install Goji \(available)", systemImage: "arrow.down.circle")
                }
            } else {
                Button {
                    Task { await updates.check() }
                } label: {
                    Label(updates.checking ? "Checking…" : "Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(updates.checking)
            }
        }
    }

    private var updateStatus: String {
        switch updates.installPhase {
        case .downloading:
            return "Downloading Goji \(updates.availableVersion ?? "")…"
        case .installing:
            return "Installing… Goji will relaunch itself in a moment."
        case .failed(let message):
            return "Couldn't install automatically (\(message)) Grab it in the browser instead."
        case .idle:
            break
        }
        if let available = updates.availableVersion {
            let how = updates.canSelfInstall ? "One click installs and relaunches." : "Opens the download in your browser."
            return "Goji \(available) is ready. You're on \(UpdateChecker.currentVersion). \(how)"
        }
        if updates.lastCheckFailed {
            return "Couldn't reach GitHub to check. Try again in a moment."
        }
        return "You're on the latest version (\(UpdateChecker.currentVersion))."
    }
}

/// Tiny standalone mic monitor for the "Test Mic" row.
@MainActor
final class MicLevelPreview: ObservableObject {
    @Published var level: Float = 0
    @Published var running = false

    private let recorder = AudioRecorder()

    func toggle(deviceUID: String?) {
        if running {
            stop()
        } else {
            start(deviceUID: deviceUID)
        }
    }

    private func start(deviceUID: String?) {
        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            self.level = self.level * 0.5 + level * 0.5
        }
        do {
            try recorder.start(deviceUID: deviceUID)
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        _ = recorder.stop()
        running = false
        level = 0
    }
}
