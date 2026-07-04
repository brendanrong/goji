import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState
    let controller: DictationController
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.openSettings) private var openSettings

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

            Text(hintLine)

            if !state.accessibilityGranted {
                Button("Grant Accessibility (needed to paste)…") {
                    Permissions.openAccessibilitySettings()
                }
                Button("Re-check permissions") {
                    controller.refreshAccessibility(prompt: true)
                }
            }

            if case .failed = state.modelState {
                Button("Retry model download") {
                    controller.loadModels()
                }
            }

            Divider()

            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Button("Quit Goji") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var hintLine: String {
        switch settings.activationMode {
        case .hold:
            return "Hold \(settings.hotkeyKey.shortLabel) to dictate. Esc cancels."
        case .toggle:
            return "Tap \(settings.hotkeyKey.shortLabel) to start/stop. Esc cancels."
        }
    }

    private var statusLine: String {
        switch state.modelState {
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
