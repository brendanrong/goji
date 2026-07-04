import AppKit

/// The brain. Wires hotkey -> recorder -> transcriber -> inserter and keeps AppState in sync.
@MainActor
final class DictationController {
    private let state: AppState
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let inserter = TextInserter()
    private let hud = HUDController()

    /// Recordings shorter than this are treated as accidental taps and dropped.
    private let minimumSamples = Int(0.3 * AudioRecorder.sampleRate)

    init(state: AppState) {
        self.state = state
    }

    func start() {
        Permissions.requestMicrophone()
        refreshAccessibility(prompt: true)

        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.start()

        loadModels()
    }

    func loadModels() {
        state.modelState = .preparing("Downloading model (one-time, ~600 MB)…")
        Task {
            do {
                try await transcriber.prepare()
                state.modelState = .ready
            } catch {
                state.modelState = .failed(error.localizedDescription)
            }
        }
    }

    func refreshAccessibility(prompt: Bool = false) {
        if prompt && !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
        }
        state.accessibilityGranted = Permissions.accessibilityGranted
    }

    private func beginRecording() {
        guard state.phase == .idle, state.modelState == .ready else { return }
        do {
            try recorder.start()
            state.phase = .recording
            hud.show(.listening)
        } catch {
            state.lastError = "Mic failed: \(error.localizedDescription)"
        }
    }

    private func finishRecording() {
        guard state.phase == .recording else { return }
        let samples = recorder.stop()

        guard samples.count >= minimumSamples else {
            state.phase = .idle
            hud.hide()
            return
        }

        state.phase = .transcribing
        hud.show(.transcribing)

        Task {
            defer {
                state.phase = .idle
                hud.hide()
            }
            do {
                let text = try await transcriber.transcribe(samples)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                state.lastTranscript = trimmed
                refreshAccessibility()
                inserter.insert(trimmed + " ")
            } catch {
                state.lastError = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func cancelRecording() {
        guard state.phase == .recording else { return }
        _ = recorder.stop()
        state.phase = .idle
        hud.hide()
    }
}
