import AppKit
import SwiftUI

/// Floating recording indicator. Two styles: a capsule panel at the bottom of the
/// screen, or a notch extension on Macs with a notch (top-pill fallback elsewhere).
/// Non-activating panel so focus stays in the app being dictated into.
@MainActor
final class HUDController {
    enum Mode {
        case listening
        case transcribing
    }

    private enum Placement: Equatable {
        case bottomPanel
        case topPill
        case notch(NSRect)
    }

    private var panel: NSPanel?
    private var currentPlacement: Placement?
    private let model = HUDModel()

    func show(_ mode: Mode, style: HUDStyle) {
        model.mode = mode
        let placement = placement(for: style)
        if panel == nil || placement != currentPlacement {
            rebuild(for: placement)
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
            return .topPill
        }
    }

    private func rebuild(for placement: Placement) {
        panel?.orderOut(nil)
        panel = nil

        let newPanel: NSPanel
        switch placement {
        case .bottomPanel, .topPill:
            newPanel = makePanel(size: NSSize(width: 180, height: 44))
            newPanel.level = .statusBar
            newPanel.contentView = NSHostingView(rootView: PanelHUDView(model: model))
        case .notch(let notch):
            // Barely wider than the notch itself: Willow-style, never covers menu bar items.
            newPanel = makePanel(size: NSSize(width: notch.width + 190, height: notch.height + 14))
            newPanel.level = .screenSaver
            newPanel.contentView = NSHostingView(rootView: NotchHUDView(model: model, notchWidth: notch.width))
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
        case .topPill:
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12))
        case .notch:
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
