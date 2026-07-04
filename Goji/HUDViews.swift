import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    @Published var mode: HUDController.Mode = .listening
    @Published var level: Float = 0
    @Published var visible = false
}

/// Live waveform bars driven by the real mic level.
struct WaveformBars: View {
    var level: Float
    var color: Color
    var barCount = 14
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: barWidth) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Double(index) * 0.9
                    let wobble = 0.35 + 0.65 * abs(sin(time * 6.5 + phase))
                    let height = 3 + CGFloat(level) * maxHeight * CGFloat(wobble)
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(width: barWidth, height: max(3, height))
                }
            }
            .frame(height: maxHeight + 4)
        }
    }
}

/// Floating capsule, used for the bottom panel and the no-notch top pill fallback.
struct PanelHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 8) {
            if model.mode == .listening {
                WaveformBars(level: model.level, color: .red)
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
        .scaleEffect(model.visible ? 1 : 0.85)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The classic notch-extension outline: flared top corners that blend into the
/// menu bar's black, rounded bottom corners. Reads as "the notch grew".
struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

/// Willow-style notch companion: a compact blob barely wider than the notch,
/// app icon in the left wing, waveform + amber mic pill in the right wing.
/// Grows out of the notch itself.
struct NotchHUDView: View {
    @ObservedObject var model: HUDModel
    var notchWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 20  // top flare + breathing room
            let wing = max((geo.size.width - notchWidth) / 2 - inset, 0)
            ZStack {
                NotchShape()
                    .fill(.black)

                HStack(spacing: 0) {
                    // Left wing: mini app icon.
                    HStack {
                        Spacer(minLength: 0)
                        if let icon = NSApp.applicationIconImage {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 19, height: 19)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: wing)

                    // The physical notch: leave it empty.
                    Spacer()
                        .frame(width: notchWidth)

                    // Right wing: live waveform + state pill.
                    HStack(spacing: 6) {
                        if model.mode == .listening {
                            WaveformBars(level: model.level, color: .white, barCount: 6, barWidth: 2.5, maxHeight: 11)
                            Capsule()
                                .fill(Color(red: 0.96, green: 0.63, blue: 0.24))
                                .frame(width: 30, height: 18)
                                .overlay(
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.72))
                                )
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: wing)
                }
                .padding(.horizontal, inset)
                .frame(height: max(geo.size.height - 10, 0), alignment: .center)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .scaleEffect(model.visible ? 1 : 0.35, anchor: .top)
            .opacity(model.visible ? 1 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: model.visible)
        }
        .environment(\.colorScheme, .dark)
    }
}
