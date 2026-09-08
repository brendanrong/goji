import AppKit
import AVFoundation
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
                Label("Speech model ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                PermissionsChecklist(controller: controller)
                Text("Hold \(settings.hotkeyKey.shortLabel), speak, release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

/// The two permissions Goji can't work without, with live ticks. Polls while
/// visible so granting in System Settings flips the row without a relaunch.
struct PermissionsChecklist: View {
    let controller: DictationController
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = Permissions.accessibilityGranted
    private let tick = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(granted: micGranted, title: "Microphone", hint: "So Goji can hear you.") {
                Permissions.requestMicrophone()
                if AVCaptureDevice.authorizationStatus(for: .audio) == .denied,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            row(granted: axGranted, title: "Accessibility", hint: "So Goji can paste where your cursor is.") {
                Permissions.promptAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary))
        .onReceive(tick) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            axGranted = Permissions.accessibilityGranted
            controller.refreshAccessibility()
        }
    }

    private func row(granted: Bool, title: String, hint: String, grant: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: grant).controlSize(.small)
            }
        }
    }
}
