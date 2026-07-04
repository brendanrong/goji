import AppKit
import SwiftUI

/// Single-pane settings window (Cmd+, or menu bar > Settings…).
struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @State private var devices: [MicDevices.Device] = []
    @StateObject private var micPreview = MicLevelPreview()

    var body: some View {
        Form {
            Section("Behavior") {
                Picker("Recording shortcut", selection: $settings.hotkeyKey) {
                    ForEach(HotkeyKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                Picker("Mode", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                Toggle("Play start/stop sounds", isOn: $settings.playSounds)
                if !settings.showInMenuBar {
                    Text("Icon hidden. Launch Goji again from Spotlight or Finder to bring it back.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(modeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Microphone") {
                Picker("Input device", selection: $settings.micDeviceUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                    if let saved = settings.micDeviceUID, !devices.contains(where: { $0.uid == saved }) {
                        Text("Saved device (unavailable)").tag(String?.some(saved))
                    }
                }
                Text("Used from the next recording. Falls back to the system default if unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(micPreview.running ? "Stop Test" : "Test Mic") {
                        micPreview.toggle(deviceUID: settings.micDeviceUID)
                    }
                    if micPreview.running {
                        WaveformBars(level: micPreview.level, color: .green, barCount: 18, maxHeight: 14)
                    }
                }
            }

            Section("AI cleanup") {
                Toggle("Clean up transcripts with Apple Intelligence", isOn: $settings.cleanupEnabled)
                    .disabled(!Cleaner.isSupported)
                Text(Cleaner.isSupported
                    ? "Removes filler words, applies self-corrections like 'scratch that', and turns 'new line' into a real line break. Runs entirely on this Mac."
                    : "Needs macOS 26 with Apple Intelligence enabled on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Interface") {
                Picker("Recording display", selection: $settings.hudStyle) {
                    ForEach(HUDStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text("Notch style falls back to a top pill on displays without a notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Word replacements") {
                ForEach($settings.replacements) { $rule in
                    HStack {
                        TextField("Replace", text: $rule.find)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("With", text: $rule.replace)
                        Button {
                            settings.replacements.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Replacement") {
                    settings.replacements.append(ReplacementRule())
                }
                Text("Applied after every transcription. Case-insensitive, whole words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                if history.items.isEmpty {
                    Text("No transcripts yet.")
                        .foregroundStyle(.secondary)
                } else {
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
                    }
                    Button("Clear History", role: .destructive) {
                        history.clear()
                    }
                }
                Text("Transcripts are stored only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
        .onAppear { devices = MicDevices.inputDevices() }
        .onDisappear { micPreview.stop() }
        .onChange(of: settings.micDeviceUID) { _, _ in
            if micPreview.running {
                micPreview.stop()
                micPreview.toggle(deviceUID: settings.micDeviceUID)
            }
        }
    }

    private var modeHint: String {
        switch settings.activationMode {
        case .hold:
            return "Hold \(settings.hotkeyKey.shortLabel), speak, release. Esc cancels."
        case .toggle:
            return "Tap \(settings.hotkeyKey.shortLabel) to start, tap again to finish. Esc cancels."
        }
    }
}

/// Tiny standalone mic monitor for the Settings "Test Mic" row.
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
