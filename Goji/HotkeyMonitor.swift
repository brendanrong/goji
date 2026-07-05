import AppKit

/// Global monitors for the dictation key (a single modifier, read live from
/// SettingsStore). Emits raw down/up transitions; DictationController decides
/// what they mean based on Hold vs Toggle mode. Esc handling lives in
/// EscapeInterceptor (it must consume the event, which monitors can't).
/// Global NSEvent monitors only deliver events once Accessibility is granted,
/// which Goji needs anyway to paste.
@MainActor
final class HotkeyMonitor {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var monitors: [Any] = []
    private var keyIsDown = false
    private var downKeyCode: UInt16?

    func start() {
        guard monitors.isEmpty else { return }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
        }) {
            monitors.append(global)
        }

        // Local monitor so the hotkey also works while a Goji window has focus.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        keyIsDown = false
        downKeyCode = nil
    }

    private func handleFlags(_ event: NSEvent) {
        let key = SettingsStore.shared.hotkeyKey

        // If the configured key changed while the old one was down, treat it as released.
        if keyIsDown, let down = downKeyCode, down != key.keyCode {
            keyIsDown = false
            downKeyCode = nil
            onHotkeyUp?()
            return
        }

        guard event.keyCode == key.keyCode else { return }
        // Use the device-dependent mask (distinguishes left vs right) so holding
        // the other Option/Control key can't mask this key's release.
        let pressed = (event.modifierFlags.rawValue & key.deviceMask) != 0

        if pressed && !keyIsDown {
            keyIsDown = true
            downKeyCode = key.keyCode
            onHotkeyDown?()
        } else if !pressed && keyIsDown {
            keyIsDown = false
            downKeyCode = nil
            onHotkeyUp?()
        }
    }
}
