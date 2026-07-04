import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    @Published var mode: HUDController.Mode = .listening
}

/// Shared indicator content: pulsing red dot while listening, spinner while transcribing.
struct HUDIndicator: View {
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
    }
}

/// Floating capsule, used for the bottom panel and the no-notch top pill fallback.
struct PanelHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HUDIndicator(model: model)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Black extension hanging under the physical notch.
struct NotchHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HUDIndicator(model: model)
                .padding(.bottom, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
                .fill(.black)
        )
        .environment(\.colorScheme, .dark)
    }
}
