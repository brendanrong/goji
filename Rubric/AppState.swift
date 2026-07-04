import Foundation

@MainActor
final class AppState: ObservableObject {
    enum ModelState: Equatable {
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
