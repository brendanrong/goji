import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState
    let controller: DictationController

    var body: some View {
        Group {
            Text(statusLine)

            if let transcript = state.lastTranscript {
                Text("Last: \(String(transcript.prefix(60)))")
            }
            if let error = state.lastError {
                Text("⚠︎ \(error)")
            }

            Divider()

            Text("Hold Right ⌥ to dictate. Esc cancels.")

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

            Button("Quit Goji") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
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
