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
                if settings.activationMode == .hold {
                    Divider()
                    SettingsRow("Double-tap to lock recording",
                                subtitle: "Tap twice quickly to keep recording hands-free, tap again to finish.") {
                        Toggle("Double-tap to lock recording", isOn: $settings.doubleTapLock)
                            .labelsHidden()
                    }
                }
                Divider()
                SettingsRow("Play start/stop sounds",
                            subtitle: "Soft cues when recording begins and ends.") {
                    Toggle("Play start/stop sounds", isOn: $settings.playSounds)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Pause media while dictating",
                            subtitle: "Pauses music or video while you record and resumes it after, so nothing bleeds into the mic.") {
                    Toggle("Pause media while dictating", isOn: $settings.pauseMediaWhileDictating)
                        .labelsHidden()
                }
            }
            CaptionText(modeHint)

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

struct MicrophonePane: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var devices: [MicDevices.Device] = []
    @StateObject private var micPreview = MicLevelPreview()

    var body: some View {
        PaneScaffold(title: "Microphone", subtitle: "Input device for dictation") {
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
        PaneScaffold(title: "Transcription", subtitle: "Cleanup and word replacements") {
            SectionHeader("AI cleanup")
            SettingsCard {
                SettingsRow("Clean up transcripts with Apple Intelligence") {
                    Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
                        .labelsHidden()
                        .disabled(!Cleaner.isSupported)
                }
            }
            CaptionText(Cleaner.unavailabilityHint
                ?? "Removes filler words, applies self-corrections like 'scratch that', and turns 'new line' into a real line break. Runs entirely on this Mac.")

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
            CaptionText("Applied after every transcription. Case-insensitive, whole words.")
        }
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
        PaneScaffold(title: "About", subtitle: "Local, private dictation") {
            SettingsCard {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text("Goji")
                            .font(.title3.bold())
                        Text(version)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
                Divider()
                SettingsRow("Updates", subtitle: updateStatus) {
                    if updates.availableVersion != nil {
                        Button("Download Update") {
                            updates.openDownload()
                        }
                    } else {
                        Button(updates.checking ? "Checking…" : "Check for Updates") {
                            Task { await updates.check() }
                        }
                        .disabled(updates.checking)
                    }
                }
                Divider()
                SettingsRow("Check automatically",
                            subtitle: "Asks GitHub once a day whether a newer version exists. Nothing else is sent.") {
                    Toggle("Check automatically", isOn: $settings.autoCheckUpdates)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Private by design",
                            subtitle: "Audio, transcripts, and settings never leave this Mac. No account, no telemetry, free forever.") {
                    EmptyView()
                }
                Divider()
                SettingsRow("Something broken?",
                            subtitle: "Open an issue on GitHub and I'll take a look.") {
                    Button("Report a Problem") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/brendanrong/goji/issues")!)
                    }
                }
                Divider()
                SettingsRow("Enjoying Goji?",
                            subtitle: "Goji is free. If it saves you time, a coffee keeps it going.") {
                    Button("Buy Me a Coffee") {
                        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/livewall")!)
                    }
                }
            }
        }
    }

    private var version: String {
        "Version " + UpdateChecker.currentVersion
    }

    private var updateStatus: String {
        if let available = updates.availableVersion {
            return "Goji \(available) is ready to download. You're on \(UpdateChecker.currentVersion)."
        }
        return "You're on the latest version."
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
