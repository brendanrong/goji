import SwiftUI

@main
struct RubricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: delegate.state, controller: delegate.controller)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = AppState()
    private(set) lazy var controller = DictationController(state: state)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
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
