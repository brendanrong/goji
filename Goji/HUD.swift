import AppKit
import SwiftUI

/// Floating recording indicator. Two styles: a capsule panel at the bottom of the
/// screen, or a notch extension (a synthetic notch island on displays without a
/// real cutout, so the design stays consistent on external monitors).
/// Non-activating panel so focus stays in the app being dictated into.
@MainActor
final class HUDController {
    enum Mode {
        case listening
        case transcribing
    }

    private enum Placement: Equatable {
        case bottomPanel
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

    func show(_ mode: Mode, style: HUDStyle) {
        if mode == .listening {
            // The app being dictated into. Goji never activates itself, so the
            // frontmost app at recording start is the paste target.
            model.frontAppIcon = NSWorkspace.shared.frontmostApplication?.icon
        }
        model.mode = mode
        let placement = placement(for: style)
        if panel == nil || placement != currentPlacement {
            rebuild(for: placement)
        } else if let panel {
            // Same placement kind, but possibly a different screen: the user
            // may have moved to another monitor since the last dictation.
            // Without this, the panel keeps stale coordinates, which on
            // stacked arrangements shows up at the neighboring screen's
            // bottom edge.
            position(panel, placement: placement)
        }
        panel?.orderFrontRegardless()
        model.visible = true
    }

    func hide() {
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

    private func placement(for style: HUDStyle) -> Placement {
        switch style {
        case .panel:
            return .bottomPanel
        case .notch:
            if let notch = NSScreen.main?.notchArea {
                return .notch(notch)
            }
            return .syntheticNotch
        }
    }

    private func rebuild(for placement: Placement) {
        panel?.orderOut(nil)
        panel = nil

        let newPanel: NSPanel
        switch placement {
        case .bottomPanel:
            newPanel = makePanel(size: NSSize(width: 180, height: 44))
            newPanel.level = .statusBar
            newPanel.contentView = NSHostingView(rootView: PanelHUDView(model: model))
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

        position(newPanel, placement: placement)
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

    private func position(_ panel: NSPanel, placement: Placement) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        switch placement {
        case .bottomPanel:
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
