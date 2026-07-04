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

/// Willow-style notch wrap: a black shape that hugs the physical notch, with the
/// app icon in the left wing and a live waveform + amber mic pill in the right wing.
/// Slides down from behind the notch with a spring.
struct NotchHUDView: View {
    @ObservedObject var model: HUDModel
    var notchWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let wing = max((geo.size.width - notchWidth) / 2, 0)
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous)
                    .fill(.black)

                HStack(spacing: 0) {
                    // Left wing: mini app icon, Willow-style.
                    HStack {
                        if let icon = NSApp.applicationIconImage {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: wing)

                    // The physical notch: leave it empty.
                    Spacer()
                        .frame(width: notchWidth)

                    // Right wing: live waveform + state pill.
                    HStack(spacing: 8) {
                        if model.mode == .listening {
                            WaveformBars(level: model.level, color: .white, barCount: 8, barWidth: 2.5, maxHeight: 12)
                            Capsule()
                                .fill(Color(red: 0.96, green: 0.63, blue: 0.24))
                                .frame(width: 36, height: 21)
                                .overlay(
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.72))
                                )
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: wing)
                }
                .frame(height: max(geo.size.height - 8, 0))
            }
            .offset(y: model.visible ? 0 : -geo.size.height)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.visible)
        }
        .environment(\.colorScheme, .dark)
    }
}
