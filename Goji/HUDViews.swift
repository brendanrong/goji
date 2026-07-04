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

/// Black extension that slides out from under the physical notch.
struct NotchHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if model.mode == .listening {
                        WaveformBars(level: model.level, color: .white, barCount: 21, barWidth: 3, maxHeight: 15)
                    } else {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Transcribing…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                    .fill(.black)
            )
            .offset(y: model.visible ? 0 : -geo.size.height)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.visible)
        }
        .environment(\.colorScheme, .dark)
    }
}
