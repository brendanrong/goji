import AppKit
import SwiftUI

/// Content of the first-run window: explains the one-time model download,
/// runs it with visible progress, and confirms when Goji is ready.
struct WelcomeView: View {
    @ObservedObject var state: AppState
    let controller: DictationController
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            Text("Welcome to Goji")
                .font(.title.bold())

            Text("Dictation that runs entirely on this Mac. Hold \(settings.hotkeyKey.shortLabel), speak, release, and your words paste where your cursor is.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            stateContent

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 440, height: 400)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state.modelState {
        case .needsDownload:
            VStack(spacing: 10) {
                Button("Download and Get Started") {
                    controller.downloadModels()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("One-time download of the speech model, about 600 MB.\nAfter that Goji works fully offline. Nothing you say ever leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .downloading(let fraction, let label):
            VStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text("\(label) \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("You can close this window; the download keeps going and the menu bar shows progress.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

        case .preparing(let status):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            VStack(spacing: 12) {
                Label("Ready to go", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Hold \(settings.hotkeyKey.shortLabel), speak, release. Grant Microphone and Accessibility if macOS asks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start Dictating") {
                    WelcomeWindow.shared.close()
                }
                .buttonStyle(.borderedProminent)
            }

        case .failed(let message):
            VStack(spacing: 10) {
                Text("Download failed: \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("Retry Download") {
                    controller.downloadModels()
                }
            }
        }
    }
}
