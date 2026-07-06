import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState
    let controller: DictationController
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        Group {
            Text(statusLine)

            if let error = state.lastError {
                Text("⚠︎ \(error)")
            }

            Divider()

            Button("Paste Last Transcription") {
                controller.insertLast()
            }
            .disabled(history.items.isEmpty)

            // Quick mic switcher. The device list is fetched fresh every time
            // the menu opens, so newly plugged-in mics show up immediately.
            Menu("Microphone: \(currentMicName)") {
                Picker("Microphone", selection: $settings.micDeviceUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(MicDevices.inputDevices()) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Text(hintLine)

            if !state.accessibilityGranted {
                Button("Grant Accessibility (needed to paste)…") {
                    Permissions.openAccessibilitySettings()
                }
                Button("Re-check permissions") {
                    controller.refreshAccessibility(prompt: true)
                }
            }

            if state.modelState == .needsDownload {
                Button("Download Speech Model (600 MB)…") {
                    WelcomeWindow.shared.show(state: state, controller: controller)
                }
            }

            if case .failed = state.modelState {
                Button("Retry model download") {
                    controller.downloadModels()
                }
            }

            Divider()

            Button("Settings…") {
                SettingsWindow.shared.show()
            }
            .keyboardShortcut(",")

            Button("Quit Goji") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var currentMicName: String {
        guard let uid = settings.micDeviceUID else { return "System Default" }
        return MicDevices.inputDevices().first { $0.uid == uid }?.name ?? "Unavailable"
    }

    private var hintLine: String {
        switch settings.activationMode {
        case .hold:
            return settings.doubleTapLock
                ? "Hold \(settings.hotkeyDisplay) to dictate, double-tap to lock. Esc cancels."
                : "Hold \(settings.hotkeyDisplay) to dictate. Esc cancels."
        case .toggle:
            return "Tap \(settings.hotkeyDisplay) to start/stop. Esc cancels."
        }
    }

    private var statusLine: String {
        switch state.modelState {
        case .needsDownload:
            return "Speech model not downloaded"
        case .downloading(let fraction, let label):
            return "\(label) \(Int(fraction * 100))%"
        case .preparing(let status):
            return status
        case .failed(let message):
            return "Model failed: \(message)"
        case .ready:
            switch state.phase {
            case .idle: return "Ready"
            case .recording: return "Listening…"
            case .transcribing: return "Transcribing…"
            }
        }
    }
}
