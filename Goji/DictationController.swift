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

    /// A press (or toggle on/off) shorter than this is an accidental tap and
    /// is dropped before transcription. Judged by hold time, not audio
    /// length: Instant start prepends pre-roll, so even a brush of the key
    /// would otherwise carry enough samples to transcribe.
    private let minimumHold: TimeInterval = 0.3
    /// Below this much audio there is nothing worth transcribing; with a real
    /// hold it means the mic delivered nothing.
    private let minimumSamples = Int(0.3 * AudioRecorder.sampleRate)
    /// Audio kept after key-up so a clipped last syllable still lands.
    private let tailPadding: TimeInterval = 0.2

    // Double-tap lock (hold mode): a quick tap-tap locks recording hands-free,
    // the next tap finishes it. State below tracks the tap timing.
    private let doubleTapWindow: TimeInterval = 0.35
    private var locked = false
    private var pressStartedAt: Date?
    private var shortTapReleasedAt: Date?
    private var lockGraceWork: DispatchWorkItem?
    /// How long the key was physically held (hold mode), for the tap gate.
    private var lastPressDuration: TimeInterval?
    /// The take that is finishing was a locked, hands-free one.
    private var finishedLocked = false

    private var lockEnabled: Bool {
        settings.activationMode == .hold && settings.doubleTapLock
    }

    /// True when we sent play/pause at recording start, so we resume after.
    private var pausedMedia = false
    private var recordingStartedAt: Date?
    /// Bundle ID of the app being dictated into, captured at recording start
    /// (Goji never activates itself, so frontmost == paste target).
    private var targetBundleID: String?
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
    }

    func start() {
        // FluidAudio may not touch the network unless Goji says so. Loading a
        // complete cache or the bundled model needs nothing; a corrupt cache
        // now fails loudly instead of silently re-downloading. The two
        // intentional download paths (first run, Models pane) lift this.
        ModelHub.offlineMode = true
        Permissions.requestMicrophone()

        hotkey.onHotkeyDown = { [weak self] in self?.hotkeyDown() }
        hotkey.onHotkeyUp = { [weak self] in self?.hotkeyUp() }
        hotkey.start()

        escape.onEscape = { [weak self] in self?.cancelRecording() }

        recorder.onLevel = { [weak self] level in
            self?.hud.updateLevel(level)
        }
        // Pre-build the capture session so the first key-down is fast (or,
        // with Instant start, keep it open), and rebuild whenever the mic or
        // that setting changes.
        prepareRecorder()
        settings.$micDeviceUID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.state.phase == .idle else { return }
                self.prepareRecorder()
            }
            .store(in: &cancellables)
        settings.$instantStart
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.state.phase == .idle else { return }
                self.prepareRecorder()
            }
            .store(in: &cancellables)
        // Sleep stops a running capture session. Re-arm on wake so the first
        // dictation of the day gets its pre-roll too (no-op when cold).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state.phase == .idle else { return }
                self.prepareRecorder()
            }
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


        // First AI cleanup of the session shouldn't pay the cold-start.
        if settings.cleanupEnabled {
            Cleaner.prewarm(vocabulary: settings.vocabularyTerms)
        }

        if Transcriber.modelsAvailableLocally || Transcriber.availableLocally(settings.selectedModel) {
            // Returning user: mic is long granted, so this prompt (which only
            // fires when NOT yet trusted) has the stage to itself.
            refreshAccessibility(prompt: true)
            loadModels()
        } else {
            // Fresh install: don't pull 600 MB without asking, and don't stack
            // a third dialog on top of the mic prompt and welcome window. The
            // Accessibility ask comes after the download, when it's needed.
            refreshAccessibility()
            state.modelState = .needsDownload
            WelcomeWindow.shared.show(state: state, controller: self)
        }
    }

    /// Idle recorder state from the current settings: cold session, or the
    /// open mic plus ring buffer when Instant start is on.
    private func prepareRecorder() {
        recorder.prepare(deviceUID: settings.micDeviceUID, instantStart: settings.instantStart)
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
                // The deferred first-run Accessibility ask: model's ready, the
                // welcome window says "Ready to go", one dialog at a time.
                refreshAccessibility(prompt: true)
            } catch {
                state.modelState = .failed(error.localizedDescription)
            }
        }
    }

    /// FluidAudio's own downloader: sequential, file by file, slower, but it
    /// works even if the GitHub model release is missing.
    private func prepareViaHuggingFace() async throws {
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
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
        refreshAccessibility(prompt: true)
    }

    func refreshAccessibility(prompt: Bool = false) {
        if prompt && !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
        }
        state.accessibilityGranted = Permissions.accessibilityGranted
    }

    /// Fix Last Dictation saved: keep the rules, fix History, and swap the
    /// pasted text if the target app is still in front.
    func applyCorrection(of item: HistoryItem, corrected: String, rules: [CorrectionDiff.Suggestion]) {
        let text = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in rules where !settings.replacements.contains(where: { $0.find.lowercased() == rule.find.lowercased() }) {
            settings.replacements.append(ReplacementRule(find: rule.find, replace: rule.replace))
        }
        Log.dictation.notice("correction saved: \(rules.count) new rules, text changed: \(item.text != text)")
        guard item.text != text else { return }
        history.update(item.id, text: text)
        state.lastTranscript = text

        // The correction window took focus. Wait for the target app to be
        // back in front (up to ~1.5 s), then swap the pasted text. If the
        // user moved on, the fixed text is in History for Paste Last.
        let target = inserter.lastTargetBundleID
        var attempts = 0
        func attempt() {
            attempts += 1
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target {
                // Keep the same leading/trailing spacing the original paste had.
                let original = inserter.lastInserted ?? item.text
                let leading = original.hasPrefix(" ") ? " " : ""
                let trailing = original.hasSuffix(" ") ? " " : ""
                if !inserter.replaceLast(with: leading + text + trailing) {
                    fail("Fixed text saved to History", hint: "Use Paste Last Transcription to drop it in.")
                }
            } else if attempts < 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: attempt)
            } else {
                fail("Fixed text saved to History", hint: "Use Paste Last Transcription to drop it in.")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: attempt)
    }

    /// Takes back the last paste (menu action).
    func undoLastInsertion() {
        if !inserter.undoLast() {
            fail("Nothing to undo", hint: "Undo works in the app the text was pasted into.")
        }
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
        lastPressDuration = pressDuration
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

    /// Every user-visible failure goes through here: menu line, red HUD
    /// toast, and the log. Never fail silently.
    private func fail(_ title: String, hint: String, offerMicPicker: Bool = false) {
        Log.dictation.error("\(title, privacy: .public): \(hint, privacy: .public)")
        state.lastError = "\(title). \(hint)"
        hud.showFailure(title: title, hint: hint, offerMicPicker: offerMicPicker)
    }

    private func beginRecording() {
        guard state.phase == .idle else { return }
        guard state.modelState == .ready else {
            Log.dictation.notice("hotkey down ignored, model state \(String(describing: self.state.modelState), privacy: .public)")
            return
        }
        state.lastError = nil
        let pressedAt = Date()
        // Is something playing? Decides both the media pause and whether the
        // pre-roll is safe (audio from before the press predates any pause,
        // so on speakers it would put the song in the transcript). When the
        // open Instant-start mic IS the default output device (combined USB
        // headsets), "running somewhere" is us, so assume silence.
        let outputIsMic = recorder.idleCapturing
            && recorder.deviceUID != nil && recorder.deviceUID == SystemAudio.defaultOutputUID()
        let outputActive = outputIsMic ? false : SystemAudio.outputIsActive()
        do {
            try recorder.start(deviceUID: settings.micDeviceUID, includePreRoll: !outputActive)
            Log.dictation.notice("recording started, capture up in \(Log.ms(since: pressedAt)) ms, pre-roll \(self.recorder.lastPreRollSamples * 1000 / Int(AudioRecorder.sampleRate)) ms")
            switch settings.whileDictating {
            case .nothing:
                break
            case .quieter:
                // Duck where the output has a volume control; otherwise fall
                // back to pausing so the setting still does something useful.
                if !SystemAudio.duckOutput(), outputActive {
                    MediaKeys.playPause()
                    pausedMedia = true
                }
            case .pause:
                // Only when audio is actually flowing: play/pause is a toggle
                // and would otherwise START playback.
                if outputActive {
                    MediaKeys.playPause()
                    pausedMedia = true
                }
            }
            recordingStartedAt = Date()
            targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            state.phase = .recording
            escape.arm()
            hud.show(.listening, style: settings.hudStyle)
            if settings.playSounds {
                Sounds.recordingStarted()
            }
        } catch {
            fail("Mic didn't start", hint: error.localizedDescription, offerMicPicker: true)
        }
    }

    private func finishRecording() {
        guard state.phase == .recording else { return }
        finishedLocked = locked
        resetLockState()
        escape.disarm()
        // People release the key on the last syllable ("three" came out as
        // "through" in testing). Keep capturing briefly, then finish. Phase
        // flips now so a re-press or Esc during the tail is ignored.
        state.phase = .transcribing
        hud.show(.transcribing, style: settings.hudStyle)
        DispatchQueue.main.asyncAfter(deadline: .now() + tailPadding) { [weak self] in
            self?.completeRecording()
        }
    }

    private func completeRecording() {
        let samples = recorder.stop()
        let held = recordingStartedAt.map { Date().timeIntervalSince($0) - tailPadding } ?? 0
        recordingStartedAt = nil
        SystemAudio.restoreOutput()
        resumeMediaIfPaused()
        // Back to the idle state (cold session, or open mic feeding the ring).
        prepareRecorder()

        let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
        Log.dictation.notice("recording stopped: held \(Int(held * 1000)) ms, audio \(String(format: "%.2f", audioSeconds), privacy: .public) s")

        // Accidental tap? Hold mode judges the physical press (a locked take
        // is always deliberate); toggle mode judges the gap between taps.
        let intentional: Bool
        switch settings.activationMode {
        case .hold: intentional = finishedLocked || (lastPressDuration ?? held) >= minimumHold
        case .toggle: intentional = held >= minimumHold
        }
        finishedLocked = false
        lastPressDuration = nil
        guard intentional else {
            Log.dictation.notice("dropped as accidental tap (held \(Int(held * 1000)) ms)")
            state.phase = .idle
            hud.hide()
            return
        }

        guard samples.count >= minimumSamples else {
            // Held long enough to speak but the mic never produced a buffer:
            // the audio device is dead, don't fail silently.
            if held >= 0.5, recorder.deliveredNoAudio {
                fail("No audio from \(recorder.deviceName)", hint: "Reconnect it, or switch mic:", offerMicPicker: true)
            } else {
                Log.dictation.notice("dropped: too little audio")
            }
            state.phase = .idle
            hud.hide()
            return
        }

        if settings.playSounds {
            Sounds.recordingStopped()
        }

        Task {
            defer { state.phase = .idle }
            do {
                let transcribeStart = Date()
                let text = try await transcriber.transcribe(samples)
                Log.dictation.notice("transcribed \(text.count) chars in \(Log.ms(since: transcribeStart)) ms")
                var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else {
                    Log.dictation.notice("empty transcript, nothing to paste")
                    if audioSeconds >= 1.5 {
                        // Plenty of audio, no words: usually a wrong or silent
                        // mic (virtual device, muted headset), not the user.
                        fail("Nothing heard from \(recorder.deviceName)", hint: "Wrong mic? Switch it here:", offerMicPicker: true)
                    } else {
                        hud.hide()
                    }
                    return
                }

                // Deterministic pass first: spoken commands, fillers, stutters.
                // Resolving "scratch that" and "new paragraph" here means the
                // AI pass (if on) only polishes and can't drop or merge them.
                cleaned = TranscriptFormatter.format(cleaned, options: settings.formatterOptions)
                let profile = settings.profile(for: targetBundleID)
                if let profile {
                    Log.dictation.notice("app profile: \(profile.name, privacy: .public)")
                }
                if settings.cleanupEnabled, profile?.aiCleanup ?? true {
                    let cleanupStart = Date()
                    cleaned = await Cleaner.cleanup(cleaned, vocabulary: settings.vocabularyTerms)
                    Log.dictation.notice("AI cleanup in \(Log.ms(since: cleanupStart)) ms")
                }
                cleaned = settings.applyReplacements(to: cleaned)
                let dropFullStop: Bool
                switch profile?.trailingFullStop ?? .inherit {
                case .inherit: dropFullStop = settings.removeTrailingFullStop
                case .drop: dropFullStop = true
                case .keep: dropFullStop = false
                }
                if dropFullStop {
                    cleaned = Self.strippingTrailingFullStop(cleaned)
                }
                let lowercase: Bool
                switch profile?.casing ?? .inherit {
                case .inherit: lowercase = settings.lowercaseEverything
                case .lowercase: lowercase = true
                case .asSpoken: lowercase = false
                }
                if lowercase {
                    cleaned = TranscriptCasing.lowercase(cleaned, preserving: settings.preservedCaseTerms)
                }
                guard !cleaned.isEmpty else {
                    hud.hide()
                    return
                }

                state.lastTranscript = cleaned
                history.add(cleaned)
                StatsStore.shared.record(
                    words: cleaned.split(whereSeparator: \.isWhitespace).count,
                    seconds: audioSeconds
                )
                refreshAccessibility()
                guard state.accessibilityGranted else {
                    // Text is safe in History; tell them why it didn't land.
                    fail("Couldn't paste", hint: "Grant Goji Accessibility in System Settings. Your text is in History.")
                    return
                }
                // Fit the text to the caret: leading space, first-letter case,
                // trailing space, based on what's already in the field.
                let context = CursorContext.read()
                let shaped = InsertionShaper.shape(cleaned, context: context, preserveCase: settings.preservedCaseTerms)
                inserter.insert(shaped)
                Log.paste.notice("pasted \(shaped.count) chars into \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown", privacy: .public) (caret context: \(context == nil ? "unavailable" : "read", privacy: .public))")
                hud.hide()
            } catch {
                fail("Transcription failed", hint: error.localizedDescription)
            }
        }
    }

    private func cancelRecording() {
        guard state.phase == .recording else { return }
        resetLockState()
        finishedLocked = false
        lastPressDuration = nil
        escape.disarm()
        _ = recorder.stop()
        recordingStartedAt = nil
        prepareRecorder()
        Log.dictation.notice("recording cancelled (Esc)")
        SystemAudio.restoreOutput()
        resumeMediaIfPaused()
        state.phase = .idle
        hud.hide()
    }
}
