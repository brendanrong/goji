import AppKit
import SwiftUI

/// First-run window: shown when no speech model is bundled or cached, so the
/// one-time ~600 MB download is an explicit choice with visible progress
/// instead of a silent background pull. Managed NSWindow for the same reason
/// as SettingsWindow (SwiftUI window scenes are broken for menu bar apps).
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private var window: NSWindow?

    func show(state: AppState, controller: DictationController) {
        DispatchQueue.main.async { [self] in reallyShow(state: state, controller: controller) }
    }

    func close() {
        window?.close()
    }

    private func reallyShow(state: AppState, controller: DictationController) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Welcome to Goji"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.collectionBehavior = [.moveToActiveSpace]
            win.isReleasedWhenClosed = false
            win.delegate = self

            let hosting = NSHostingView(rootView: WelcomeView(state: state, controller: controller))
            hosting.autoresizingMask = [.width, .height]
            win.contentView = hosting

            win.center()
            window = win
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        SettingsStore.shared.applyDockPolicy()
    }
}
