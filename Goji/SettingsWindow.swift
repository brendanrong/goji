import AppKit
import SwiftUI

/// Owns the Settings window. SwiftUI's `Settings` scene + `openSettings()`
/// silently no-op for menu-bar-only apps on macOS 26 (there's no SwiftUI window
/// render tree to resolve against), so Goji manages a plain NSWindow instead.
///
/// Construction details matter here: the window is created with its final
/// styleMask, and the SwiftUI view is installed as a plain NSHostingView
/// contentView. Building it from an NSHostingController and mutating styleMask
/// afterwards lets the hosting controller drive window sizing, which can spin
/// into a layout loop (main thread hang, dead controls, beachball on click).
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show() {
        // Menu-item actions run while the MenuBarExtra menu is tearing down;
        // activating and ordering a window front synchronously here can get
        // undone as the menu closes. Defer a runloop pass first.
        DispatchQueue.main.async { [self] in reallyShow() }
    }

    private func reallyShow() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Goji Settings"
            win.titlebarAppearsTransparent = true
            win.collectionBehavior = [.moveToActiveSpace]
            win.isReleasedWhenClosed = false
            win.delegate = self

            let hosting = NSHostingView(rootView: SettingsView())
            hosting.autoresizingMask = [.width, .height]
            win.contentView = hosting

            win.center()
            window = win
        }
        // A window can't reliably become key without a Dock icon; run as a
        // regular app while Settings is open, restore the user's pref on close.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Give the policy flip a beat before ordering front; doing it in the
        // same runloop pass as the .accessory -> .regular switch is flaky.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the window so the next open gets a fresh view (re-runs onAppear,
        // which refreshes the mic list and stops any running mic test).
        window = nil
        SettingsStore.shared.applyDockPolicy()
    }
}
