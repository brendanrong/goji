import AppKit

/// Global hold-to-talk hotkey: Right Option (keyCode 61). Esc cancels an active recording.
/// Global NSEvent monitors only deliver events once Accessibility is granted,
/// which Goji needs anyway to paste.
@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var isHeld = false

    private let hotkeyCode: UInt16 = 61  // Right Option
    private let escapeCode: UInt16 = 53

    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
        }) {
            monitors.append(global)
        }

        // Local monitor so the hotkey also works while a Goji window/menu has focus.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
            return event
        }) {
            monitors.append(local)
        }

        if let escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.isHeld, event.keyCode == self.escapeCode else { return }
            self.isHeld = false
            self.onCancel?()
        }) {
            monitors.append(escape)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isHeld = false
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == hotkeyCode else { return }
        let pressed = event.modifierFlags.contains(.option)

        if pressed && !isHeld {
            isHeld = true
            onPress?()
        } else if !pressed && isHeld {
            isHeld = false
            onRelease?()
        }
    }
}
