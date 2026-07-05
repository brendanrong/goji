import AppKit
import CoreGraphics

/// Consumes the Esc key while a recording is active, so cancelling a dictation
/// doesn't also deliver Esc to the frontmost app (stopping a running AI turn,
/// dismissing a dialog, ...). NSEvent global monitors are observe-only; only a
/// CGEventTap can swallow an event. The tap is armed solely while recording so
/// it can never affect normal typing, and it relies on the same Accessibility
/// permission Goji already needs for pasting (tapCreate fails without it, in
/// which case pasting is broken anyway).
///
/// Not @MainActor because the C tap callback can't carry actor isolation.
/// arm()/disarm() must be called on the main thread (DictationController is
/// @MainActor, so they are), and the callback runs on the main run loop since
/// that's where the tap source is added.
final class EscapeInterceptor {
    var onEscape: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static let escapeKeyCode: Int64 = 53

    func arm() {
        guard tap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<EscapeInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func disarm() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown where event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode:
            // Defer the actual cancel so the callback returns instantly; the
            // system disables taps whose callbacks are slow.
            DispatchQueue.main.async { [weak self] in self?.onEscape?() }
            return nil // swallowed
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
