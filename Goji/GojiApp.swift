import SwiftUI

@main
struct GojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var settings = SettingsStore.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $settings.showInMenuBar) {
            MenuContent(state: delegate.state, controller: delegate.controller)
        } label: {
            MenuBarLabel(state: delegate.state)
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = AppState()
    private(set) lazy var controller = DictationController(state: state)

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.applyDockPolicy()
        controller.start()
    }

    /// Escape hatch: relaunching Goji from Spotlight/Finder restores a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsStore.shared.showInMenuBar = true
        return true
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch state.phase {
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .idle:
            switch state.modelState {
            case .ready: return "mic"
            case .preparing: return "arrow.down.circle"
            case .failed: return "mic.slash"
            }
        }
    }
}
