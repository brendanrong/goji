import AppKit
import FluidAudio

/// The brain. Wires hotkey -> recorder -> transcriber -> inserter and keeps AppState in sync.
@MainActor
final class DictationController {
    private let state: AppState
    private let settings = SettingsStore.shared
    private let history = HistoryStore.shared
    private let hotkey = HotkeyMonitor()
    private let escape = EscapeInterceptor()
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

        hotkey.onHotkeyDown = { [weak self] in self?.hotkeyDown() }
        hotkey.onHotkeyUp = { [weak self] in self?.hotkeyUp() }
        hotkey.start()

        escape.onEscape = { [weak self] in self?.cancelRecording() }

        recorder.onLevel = { [weak self] level in
            self?.hud.updateLevel(level)
        }

        if Transcriber.modelsAvailableLocally {
            loadModels()
        } else {
            // Fresh install: don't pull 600 MB without asking. The welcome
            // window explains and offers the download.
            state.modelState = .needsDownload
            WelcomeWindow.shared.show(state: state, controller: self)
        }
    }

    /// Quiet path: the model is bundled or already cached, just load it.
    func loadModels() {
        state.modelState = .preparing("Loading speech model…")
        Task {
            do {
                try await transcriber.prepare()
                state.modelState = .ready
            } catch {
                state.modelState = .failed(error.localizedDescription)
            }
        }
    }

    /// Explicit path: user approved the one-time model download. Reports
    /// progress into AppState so the welcome window and menu can show it.
    func downloadModels() {
        switch state.modelState {
        case .ready, .downloading, .preparing:
            return
        case .needsDownload, .failed:
            break
        }
        state.modelState = .downloading(0, "Contacting server…")
        Task {
            do {
                try await transcriber.prepare { progress in
                    let label: String
                    switch progress.phase {
                    case .listing:
                        label = "Contacting server…"
                    case .downloading(let done, let total):
                        label = "Downloading speech model (file \(min(done + 1, total)) of \(total))…"
                    case .compiling:
                        label = "Optimizing for this Mac…"
                    }
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        self?.state.modelState = .downloading(fraction, label)
                    }
                }
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

    /// Re-inserts the most recent transcript at the cursor.
    func insertLast() {
        guard let last = history.last else { return }
        inserter.insert(last.text + " ")
    }

    private func hotkeyDown() {
        switch settings.activationMode {
        case .hold:
            beginRecording()
        case .toggle:
            if state.phase == .recording {
                finishRecording()
            } else {
                beginRecording()
            }
        }
    }

    private func hotkeyUp() {
        guard settings.activationMode == .hold else { return }
        finishRecording()
    }

    private func beginRecording() {
        guard state.phase == .idle, state.modelState == .ready else { return }
        state.lastError = nil
        do {
            try recorder.start(deviceUID: settings.micDeviceUID)
            state.phase = .recording
            escape.arm()
            hud.show(.listening, style: settings.hudStyle)
            if settings.playSounds {
                Sounds.recordingStarted()
            }
        } catch {
            state.lastError = "Mic failed: \(error.localizedDescription)"
        }
    }

    private func finishRecording() {
        guard state.phase == .recording else { return }
        escape.disarm()
        let samples = recorder.stop()

        guard samples.count >= minimumSamples else {
            state.phase = .idle
            hud.hide()
            return
        }

        state.phase = .transcribing
        hud.show(.transcribing, style: settings.hudStyle)
        if settings.playSounds {
            Sounds.recordingStopped()
        }

        Task {
            defer {
                state.phase = .idle
                hud.hide()
            }
            do {
                let text = try await transcriber.transcribe(samples)
                var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }

                if settings.cleanupEnabled {
                    cleaned = await Cleaner.cleanup(cleaned)
                }
                cleaned = settings.applyReplacements(to: cleaned)
                guard !cleaned.isEmpty else { return }

                state.lastTranscript = cleaned
                history.add(cleaned)
                refreshAccessibility()
                inserter.insert(cleaned + " ")
            } catch {
                state.lastError = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func cancelRecording() {
        guard state.phase == .recording else { return }
        escape.disarm()
        _ = recorder.stop()
        state.phase = .idle
        hud.hide()
    }
}
