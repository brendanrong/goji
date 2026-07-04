import AppKit
import SwiftUI

/// Small floating capsule at the bottom of the screen: "Listening…" / "Transcribing…".
/// Non-activating panel so focus stays in the app being dictated into.
@MainActor
final class HUDController {
    enum Mode {
        case listening
        case transcribing
    }

    private var panel: NSPanel?
    private let model = HUDModel()

    func show(_ mode: Mode) {
        model.mode = mode
        if panel == nil {
            panel = makePanel()
        }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 60))
    }
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var mode: HUDController.Mode = .listening
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            if model.mode == .listening {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .opacity(pulsing ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
                Text("Listening…")
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
