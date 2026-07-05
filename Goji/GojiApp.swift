import SwiftUI

@main
struct GojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var settings = SettingsStore.shared

    var body: some Scene {
        // No Settings scene: openSettings()/SettingsLink silently no-op for
        // menu-bar-only apps on macOS 26. SettingsWindow manages it instead.
        MenuBarExtra(isInserted: dedupedShowInMenuBar) {
            MenuContent(state: delegate.state, controller: delegate.controller)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
    }

    /// MenuBarExtra writes `isInserted` back on every scene update (KVO on the
    /// status item), even when the value hasn't changed. Feeding that straight
    /// into the @Published property fires objectWillChange -> App body re-eval
    /// -> MenuBarExtra update -> write again: an infinite invalidation loop
    /// that pegs the main thread (confirmed via sample). Dedupe before writing.
    private var dedupedShowInMenuBar: Binding<Bool> {
        Binding(
            get: { settings.showInMenuBar },
            set: { newValue in
                if settings.showInMenuBar != newValue {
                    settings.showInMenuBar = newValue
                }
            }
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = AppState()
    private(set) lazy var controller = DictationController(state: state)

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.applyDockPolicy()
        // Defer off the launch render pass. start() mutates @Published AppState, and
        // doing that synchronously here lands mid first-render -> SwiftUI's
        // "Publishing changes from within view updates" warning.
        DispatchQueue.main.async { [weak self] in
            self?.controller.start()
        }
    }

    /// Escape hatch: relaunching Goji from Spotlight/Finder restores a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !SettingsStore.shared.showInMenuBar {
            SettingsStore.shared.showInMenuBar = true
        }
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
            case .needsDownload, .downloading, .preparing: return "arrow.down.circle"
            case .failed: return "mic.slash"
            }
        }
    }
}
