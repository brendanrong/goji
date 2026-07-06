import AppKit

/// Global monitors for the dictation shortcut (a preset modifier key or a
/// recorded combo of modifiers, read live from SettingsStore). Emits raw
/// down/up transitions; DictationController decides what they mean based on
/// Hold vs Toggle mode. Esc handling lives in EscapeInterceptor (it must
/// consume the event, which monitors can't). Global NSEvent monitors only
/// deliver events once Accessibility is granted, which Goji needs anyway to paste.
@MainActor
final class HotkeyMonitor {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var monitors: [Any] = []
    private var keyIsDown = false
    private var armedMask: UInt = 0

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
        armedMask = 0
    }

    private func handleFlags(_ event: NSEvent) {
        // The recorder in Settings owns the keyboard while capturing a combo.
        guard !HotkeyRecorder.isRecording else { return }

        let required = SettingsStore.shared.effectiveHotkeyMask
        guard required != 0 else { return }

        // If the configured shortcut changed while the old one was down,
        // treat the old one as released.
        if keyIsDown, armedMask != required {
            keyIsDown = false
            armedMask = 0
            onHotkeyUp?()
            return
        }

        // Down when every required bit is held together (device-dependent
        // masks distinguish left from right), up as soon as any is released.
        let pressed = (event.modifierFlags.rawValue & required) == required

        if pressed && !keyIsDown {
            keyIsDown = true
            armedMask = required
            onHotkeyDown?()
        } else if !pressed && keyIsDown {
            keyIsDown = false
            armedMask = 0
            onHotkeyUp?()
        }
    }
}
