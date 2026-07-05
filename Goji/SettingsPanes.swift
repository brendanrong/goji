import AppKit
import SwiftUI

struct GeneralPane: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        PaneScaffold(title: "General", subtitle: "Shortcut and app behavior") {
            SectionHeader("Dictation")
            SettingsCard {
                SettingsRow("Recording shortcut") {
                    Picker("Recording shortcut", selection: $settings.hotkeyKey) {
                        ForEach(HotkeyKey.allCases) { key in
                            Text(key.label).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
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
                    SettingsRow("Double-tap to lock recording") {
                        Toggle("Double-tap to lock recording", isOn: $settings.doubleTapLock)
                            .labelsHidden()
                    }
                }
                Divider()
                SettingsRow("Play start/stop sounds") {
                    Toggle("Play start/stop sounds", isOn: $settings.playSounds)
                        .labelsHidden()
                }
            }
            CaptionText(modeHint)

            SectionHeader("System")
            SettingsCard {
                SettingsRow("Launch at login") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Show in menu bar") {
                    Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Show in Dock") {
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

    private var modeHint: String {
        switch settings.activationMode {
        case .hold:
            return settings.doubleTapLock
                ? "Hold \(settings.hotkeyKey.shortLabel), speak, release. Double-tap to keep recording hands-free, tap again to finish. Esc cancels."
                : "Hold \(settings.hotkeyKey.shortLabel), speak, release. Esc cancels."
        case .toggle:
            return "Tap \(settings.hotkeyKey.shortLabel) to start, tap again to finish. Esc cancels."
        }
    }
}

struct MicrophonePane: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var devices: [MicDevices.Device] = []
    @StateObject private var micPreview = MicLevelPreview()

    var body: some View {
        PaneScaffold(title: "Microphone", subtitle: "Input device for dictation") {
            SettingsCard {
                SettingsRow("Input device") {
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
            CaptionText("Used from the next recording. Falls back to the system default if unavailable.")
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
            }
            CaptionText("Everything runs on this Mac. Audio, transcripts, and settings never leave it.")
        }
    }

    private var version: String {
        "Version " + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev")
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
