import Foundation

@MainActor
final class AppState: ObservableObject {
    enum ModelState: Equatable {
        /// Fresh install: no bundled or cached model, waiting for the user to
        /// approve the one-time download.
        case needsDownload
        /// Actively downloading/compiling: progress 0...1 plus a phase label.
        case downloading(Double, String)
        case preparing(String)
        case ready
        case failed(String)
    }

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published var modelState: ModelState = .preparing("Starting…")
    @Published var phase: Phase = .idle
    @Published var accessibilityGranted = false
    @Published var lastTranscript: String?
    @Published var lastError: String?
}
