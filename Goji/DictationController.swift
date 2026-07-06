import AppKit
import Combine
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

    // Double-tap lock (hold mode): a quick tap-tap locks recording hands-free,
    // the next tap finishes it. State below tracks the tap timing.
    private let doubleTapWindow: TimeInterval = 0.35
    private var locked = false
    private var pressStartedAt: Date?
    private var shortTapReleasedAt: Date?
    private var lockGraceWork: DispatchWorkItem?

    private var lockEnabled: Bool {
        settings.activationMode == .hold && settings.doubleTapLock
    }

    /// True when we sent play/pause at recording start, so we resume after.
    private var pausedMedia = false
    private var cancellables = Set<AnyCancellable>()

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

        // If the chosen model's files were removed outside the app, fall back.
        if !Transcriber.availableLocally(settings.selectedModel), settings.selectedModel != .standard {
            settings.selectedModel = .standard
        }

        // Live model switching from the Models pane.
        settings.$selectedModel
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] model in
                self?.switchModel(to: model)
            }
            .store(in: &cancellables)

        if Transcriber.modelsAvailableLocally || Transcriber.availableLocally(settings.selectedModel) {
            loadModels()
        } else {
            // Fresh install: don't pull 600 MB without asking. The welcome
            // window explains and offers the download.
            state.modelState = .needsDownload
            WelcomeWindow.shared.show(state: state, controller: self)
        }
    }

    private func switchModel(to model: SpeechModel) {
        guard Transcriber.availableLocally(model) else { return }
        state.modelState = .preparing("Loading \(model.displayName)…")
        Task {
            do {
                try await transcriber.prepare(model: model)
                state.modelState = .ready
            } catch {
                state.modelState = .failed(error.localizedDescription)
            }
        }
    }

    /// Quiet path: the model is bundled or already cached, just load it.
    func loadModels() {
        state.modelState = .preparing("Loading speech model…")
        Task {
            do {
                try await transcriber.prepare(model: settings.selectedModel)
                state.modelState = .ready
            } catch {
                state.modelState = .failed(error.localizedDescription)
            }
        }
    }

    /// Explicit path: user approved the one-time model download. Tries the
    /// single-zip GitHub mirror first (fast CDN, real progress), falls back to
    /// FluidAudio's HuggingFace crawl if the mirror is unavailable. Progress
    /// goes into AppState so the welcome window and menu can show it.
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
                if !Transcriber.modelsAvailableLocally {
                    do {
                        try await ModelFetcher.fetch { fraction in
                            Task { @MainActor [weak self] in
                                self?.state.modelState = .downloading(fraction, "Downloading speech model…")
                            }
                        }
                    } catch {
                        try await prepareViaHuggingFace()
                        return
                    }
                }
                state.modelState = .preparing("Optimizing for this Mac…")
                try await transcriber.prepare()
                state.modelState = .ready
            } catch {
                state.modelState = .failed(error.localizedDescription)
            }
        }
    }

    /// FluidAudio's own downloader: sequential, file by file, slower, but it
    /// works even if the GitHub model release is missing.
    private func prepareViaHuggingFace() async throws {
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
            if locked {
                finishRecording()
                return
            }
            if state.phase == .recording {
                // Second tap inside the grace window: lock recording on.
                if lockEnabled, let released = shortTapReleasedAt,
                    Date().timeIntervalSince(released) <= doubleTapWindow {
                    lockGraceWork?.cancel()
                    lockGraceWork = nil
                    shortTapReleasedAt = nil
                    locked = true
                }
                return
            }
            pressStartedAt = Date()
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
        guard settings.activationMode == .hold, !locked else { return }
        guard state.phase == .recording else { return }

        let pressDuration = pressStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard lockEnabled, pressDuration <= doubleTapWindow else {
            finishRecording()
            return
        }
        // Short tap: keep recording briefly in case a lock tap follows. If none
        // arrives, finish normally (sub-0.3s audio is dropped as accidental).
        shortTapReleasedAt = Date()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.locked else { return }
            self.shortTapReleasedAt = nil
            self.finishRecording()
        }
        lockGraceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
    }

    /// Drops exactly one final period. Leaves "?", "!", and "..." alone, and
    /// only touches the very end of the transcript.
    static func strippingTrailingFullStop(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    private func resumeMediaIfPaused() {
        guard pausedMedia else { return }
        pausedMedia = false
        MediaKeys.playPause()
    }

    private func resetLockState() {
        locked = false
        pressStartedAt = nil
        shortTapReleasedAt = nil
        lockGraceWork?.cancel()
        lockGraceWork = nil
    }

    private func beginRecording() {
        guard state.phase == .idle, state.modelState == .ready else { return }
        state.lastError = nil
        do {
            try recorder.start(deviceUID: settings.micDeviceUID)
            switch settings.whileDictating {
            case .nothing:
                break
            case .quieter:
                // Duck where the output has a volume control; otherwise fall
                // back to pausing so the setting still does something useful.
                if !SystemAudio.duckOutput(), SystemAudio.outputIsActive() {
                    MediaKeys.playPause()
                    pausedMedia = true
                }
            case .pause:
                // Only when audio is actually flowing: play/pause is a toggle
                // and would otherwise START playback.
                if SystemAudio.outputIsActive() {
                    MediaKeys.playPause()
                    pausedMedia = true
                }
            }
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
        resetLockState()
        escape.disarm()
        let samples = recorder.stop()
        SystemAudio.restoreOutput()
        resumeMediaIfPaused()

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
                if settings.removeTrailingFullStop {
                    cleaned = Self.strippingTrailingFullStop(cleaned)
                }
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
        resetLockState()
        escape.disarm()
        _ = recorder.stop()
        SystemAudio.restoreOutput()
        resumeMediaIfPaused()
        state.phase = .idle
        hud.hide()
    }
}
