import AppKit
import SwiftUI

/// Single-pane settings window (Cmd+, or menu bar > Settings…).
struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var history = HistoryStore.shared

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
                Text(modeHint)
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
        .frame(width: 480, height: 640)
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
