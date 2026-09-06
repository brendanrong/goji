import AppKit
import ApplicationServices
import SwiftUI

/// Floating recording indicator. Two styles: a capsule panel at the bottom of the
/// screen, or a notch extension (a synthetic notch island on displays without a
/// real cutout, so the design stays consistent on external monitors).
/// Non-activating panel so focus stays in the app being dictated into.
@MainActor
final class HUDController {
    enum Mode: Equatable {
        case listening
        case transcribing
        /// Something went wrong: a short title plus a one-line hint, shown
        /// briefly with a draining countdown bar, then auto-hides.
        case failed(title: String, hint: String)
    }

    /// How long a failure toast stays up. The countdown bar drains over this.
    static let failureDuration: TimeInterval = 4.0

    private enum Placement: Equatable {
        case bottomPanel
        /// Wider bottom capsule for a failure reason. Used for both HUD styles:
        /// the notch wings have no room for text.
        case failureToast
        /// Physical notch cutout: wings hug the real notch.
        case notch(NSRect)
        /// No hardware notch (external monitor, older Mac): draw a fake notch
        /// island at MacBook proportions so the design stays consistent.
        case syntheticNotch
    }

    /// Fake cutout dimensions for notchless displays, roughly MacBook Pro
    /// proportions. The island hangs from the top edge, Willow style.
    private static let syntheticNotchSize = NSSize(width: 170, height: 34)

    private var panel: NSPanel?
    private var currentPlacement: Placement?
    private let model = HUDModel()
    private var failureDismiss: DispatchWorkItem?

    func show(_ mode: Mode, style: HUDStyle) {
        failureDismiss?.cancel()
        failureDismiss = nil
        if mode == .listening {
            // The app being dictated into. Goji never activates itself, so the
            // frontmost app at recording start is the paste target.
            model.frontAppIcon = NSWorkspace.shared.frontmostApplication?.icon
        }
        model.mode = mode
        guard let screen = targetScreen else { return }
        let placement = placement(for: style, on: screen)
        present(placement, on: screen)
    }

    /// Red card with a title and hint, visible for a few seconds. Replaces
    /// whatever the HUD was showing; a new dictation replaces it in turn.
    /// `offerMicPicker` adds an inline mic menu so a wrong or dead mic can be
    /// fixed right there. The view owns the countdown (it pauses on hover) and
    /// calls back when it expires; the timer here is only a safety net.
    func showFailure(title: String, hint: String, offerMicPicker: Bool = false) {
        failureDismiss?.cancel()
        model.mode = .failed(title: title, hint: hint)
        model.offerMicPicker = offerMicPicker
        model.failureID = UUID()  // restarts the countdown bar
        model.onFailureExpired = { [weak self] in
            guard let self, case .failed = self.model.mode else { return }
            self.dismiss()
        }
        guard let screen = targetScreen else { return }
        present(.failureToast, on: screen)
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .failed = self.model.mode else { return }
            self.dismiss()
        }
        failureDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    func hide() {
        // A failure toast has its own timer; don't let the normal
        // end-of-dictation hide cut it short.
        if case .failed = model.mode { return }
        dismiss()
    }

    private func present(_ placement: Placement, on screen: NSScreen) {
        if panel == nil || placement != currentPlacement {
            rebuild(for: placement, on: screen)
        } else if let panel {
            // Same placement kind, but possibly a different screen: the user
            // may have moved to another monitor since the last dictation.
            position(panel, placement: placement, on: screen)
        }
        panel?.orderFrontRegardless()
        model.visible = true
    }

    private func dismiss() {
        model.visible = false
        // Let the exit animation play before the panel disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    func updateLevel(_ level: Float) {
        model.level = model.level * 0.55 + level * 0.45
    }

    /// The screen dictation is landing on. NSScreen.main is useless for a
    /// background app that never activates (it degrades to the primary
    /// display), so ask where the focused text field actually is via
    /// Accessibility, then fall back to the mouse's screen, then main.
    private var targetScreen: NSScreen? {
        if let point = Self.focusedElementPoint(),
           let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// AppKit-space position of the system-wide focused UI element, if any.
    private static func focusedElementPoint() -> NSPoint? {
        var focusedRef: CFTypeRef?
        let systemWide = AXUIElementCreateSystemWide()
        guard
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focused = focusedRef
        else {
            return nil
        }
        let element = focused as! AXUIElement
        var posRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
            let posValue = posRef,
            CFGetTypeID(posValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var cgPoint = CGPoint.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &cgPoint) else {
            return nil
        }
        // AX coordinates are top-left origin; AppKit is bottom-left.
        // Flip against the primary screen.
        guard let primary = NSScreen.screens.first else { return nil }
        return NSPoint(x: cgPoint.x, y: primary.frame.maxY - cgPoint.y)
    }

    private func placement(for style: HUDStyle, on screen: NSScreen) -> Placement {
        switch style {
        case .panel:
            return .bottomPanel
        case .notch:
            if let notch = screen.notchArea {
                return .notch(notch)
            }
            return .syntheticNotch
        }
    }

    private func rebuild(for placement: Placement, on screen: NSScreen) {
        panel?.orderOut(nil)
        panel = nil

        let newPanel: NSPanel
        switch placement {
        case .bottomPanel:
            newPanel = makePanel(size: NSSize(width: 180, height: 44))
            newPanel.level = .statusBar
            newPanel.contentView = NSHostingView(rootView: PanelHUDView(model: model))
        case .failureToast:
            newPanel = makePanel(size: NSSize(width: 460, height: 72))
            newPanel.level = .statusBar
            // The only HUD that takes clicks (the inline mic menu). Still
            // non-activating, so the app being dictated into keeps focus.
            newPanel.ignoresMouseEvents = false
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.contentView = NSHostingView(rootView: FailureToastView(model: model))
        case .notch(let notch):
            // Barely wider than the notch and EXACTLY its height: Willow-style
            // wings beside the notch, flush with the menu bar, nothing below it.
            newPanel = makePanel(size: NSSize(width: notch.width + 120, height: notch.height))
            newPanel.level = .screenSaver
            newPanel.contentView = NSHostingView(rootView: NotchHUDView(model: model, notchWidth: notch.width))
        case .syntheticNotch:
            // Same view, fake cutout: black island top-center over the menu bar.
            let fake = Self.syntheticNotchSize
            newPanel = makePanel(size: NSSize(width: fake.width + 120, height: fake.height))
            newPanel.level = .screenSaver
            newPanel.contentView = NSHostingView(rootView: NotchHUDView(model: model, notchWidth: fake.width))
        }

        position(newPanel, placement: placement, on: screen)
        panel = newPanel
        currentPlacement = placement
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func position(_ panel: NSPanel, placement: Placement, on screen: NSScreen) {
        let size = panel.frame.size
        switch placement {
        case .bottomPanel, .failureToast:
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 60))
        case .notch, .syntheticNotch:
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height))
        }
    }
}

extension NSScreen {
    /// The physical notch cutout in screen coordinates, nil on screens without one.
    var notchArea: NSRect? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return NSRect(x: left.maxX, y: frame.maxY - safeAreaInsets.top, width: width, height: safeAreaInsets.top)
    }
}
