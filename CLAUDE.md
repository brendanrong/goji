# Goji

Local, private dictation for macOS. Hold Right Option, speak, release, and the transcript pastes into whatever app you're in. Native Swift menu bar app, Parakeet v3 via FluidAudio, everything on-device. Built to eventually share with my team.

Read PRD.md for scope. v1 is the core loop plus a lean settings window. Don't gold-plate.

## Build and run

- Open `Goji.xcodeproj` in Xcode on the Mac. Cmd+R.
- Builds ONLY work on the Mac. Never attempt to build from Cowork's Linux sandbox.
- If signing complains, pick Brendan's team under Signing & Capabilities (automatic signing).
- First run: grant Microphone (system prompt) and Accessibility (System Settings). Model (~600 MB) downloads once from HuggingFace into the user cache.

## Architecture (one line each)

- `GojiApp.swift`: @main, MenuBarExtra scene, app delegate.
- `AppState.swift`: observable state (model status, phase, permissions).
- `DictationController.swift`: the brain. Wires hotkey -> recorder -> transcriber -> inserter.
- `HotkeyMonitor.swift`: global NSEvent monitors. Emits raw down/up for the configured shortcut, a preset modifier key or a recorded modifier combo (read live from SettingsStore).
- `HotkeyRecorder.swift`: the Custom Combo recorder row in Settings (capture any mix of held modifiers, left/right specific) + the ModifierBits table.
- `EscapeInterceptor.swift`: CGEventTap that swallows Esc, armed only while recording, so cancelling a dictation doesn't leak Esc into the frontmost app.
- `AudioRecorder.swift`: AVCaptureSession bound to the chosen mic, capture output set to 16 kHz mono Float32 directly. NOT AVAudioEngine (see Gotchas). `prepare()` pre-builds the idle session so key-down only starts it (~55 ms to first buffer); DictationController keeps 200 ms after key-up (tail padding). First-word clipping when speaking on the instant of the press still happens ~40% of the time; the only real fix is an always-on mic, deliberately not done.
- `Transcriber.swift`: multi-engine wrapper (actor). Parakeet v2/v3 via AsrManager, Cohere Transcribe via CoherePipeline (pinned to English for now); loads whichever SettingsStore.selectedModel says. An acoustic Names & phrases boost (CTC word spotting + rescoring) and a History fix-and-learn loop were built and REMOVED during v1.0.15 development: the library's batch VocabularyRescorer misaligns replacements onto neighboring words, custom confirmation missed true positives, and learned-alias substitution compounded errors on genuinely hard words. Vocabulary corrections run through the Cleaner prompt only; deterministic fixes are the user's Word replacements. Do not revive any learning path without an offline test harness of recorded audio; see git history around v1.0.15.
- `ModelCatalog.swift`: SpeechModel catalog (v3 default / v2 English / Cohere) + ModelLibrary (download via DownloadUtils.downloadRepo, remove, size on disk, reveal in Finder). Parakeet JA deliberately excluded: its files stitch together from multiple HF repos.
- `ModelFetcher.swift`: first-run model download as ONE zip from the GitHub `models-v3` release (fast CDN, real progress) into FluidAudio's cache; DictationController falls back to FluidAudio's HuggingFace crawl if it fails. The models-v3 release must be created with `--latest=false` or the site's releases/latest/download/Goji.dmg link breaks.
- `Formatter.swift`: TranscriptFormatter, deterministic cleanup on every dictation: spoken commands ("new line" / "new paragraph" / "scratch that"), fillers, stutters, NumberWords (spelled-out numbers to digits: 10+, decimals, ordinals, and 1 to 9 after an acronym/counter word or before a unit), spoken punctuation (comma, full stop, quotes, brackets, symbols; a determiner in front keeps the noun). Foundation-only on purpose; `scripts/formatter-tests.sh` compiles it plus AppProfile/InsertionShaper/CorrectionDiff standalone against a fixture table (~95 cases). Runs BEFORE the AI Cleaner, which no longer owns commands or line breaks (it dropped them in testing) and cleans paragraph by paragraph.
- `InsertionShaper.swift` / `CursorContext.swift`: the paste fits the caret. CursorContext reads AXValue + AXSelectedTextRange of the focused element (works in AppKit apps and most Electron apps incl. Slack and Obsidian; not in the Claude desktop composer); InsertionShaper decides leading space, first-letter case (lowercase mid-sentence, keeping I, acronyms, Names & phrases) and trailing space. nil context = old behaviour.
- `CorrectionDiff.swift` / `CorrectionWindow.swift`: "Fix Last Dictation…" menu item. Word-level LCS between what Goji wrote and what the user typed; changed runs of 1 to 3 words become ticked rule suggestions that land in Word replacements on Save; the pasted text is swapped in place via TextInserter.replaceLast.
- `AppProfile.swift`: per-app formatting (casing, trailing full stop, AI cleanup on/off) keyed on the frontmost bundle ID captured at recording start, plus TranscriptCasing.lowercase (keeps acronyms, Names & phrases, replacement outputs). Defaults seeded once via the `appProfilesSeeded` flag.
- `SettingsAppsPane.swift`: the Apps pane; apps are added from the running-apps list because Settings itself is frontmost.
- `Log.swift` / `Diagnostics.swift`: os.Logger under `com.brendanrong.Goji` (use `.notice`, `.info` is not persisted; never log transcript text) and the Copy Diagnostics menu item (env + permissions + last 10 min of our log via OSLogStore).
- `TextInserter.swift`: pasteboard swap + synthetic Cmd+V, restores clipboard after 1 s (Electron paste handlers read it late). Remembers the last paste for Undo Last Dictation / replaceLast: selection prefers AX (confirm the text before the caret is ours), else Shift+Left per character. Cmd+Z is NOT used: Electron editors don't treat a paste as one undo step (learned the hard way, duplicated text). Also detects a refused paste (field didn't grow) and logs the app; the keystroke fallback (`typeText`) exists behind `typeWhenPasteFails = false` until logs prove the AX length check never misfires.
- `HUD.swift`: HUDController, places the indicator (bottom panel, notch extension; synthetic notch island on notchless displays) and the failure toast (`showFailure`, bottom card with a countdown that pauses on hover and an optional inline mic picker; the only HUD panel that accepts clicks). Every user-visible failure goes through `DictationController.fail`.
- `HUDViews.swift`: the SwiftUI indicator views (capsule + notch shapes).
- `SettingsStore.swift`: user prefs (hotkey, hold/toggle, HUD style, login item, replacements). UserDefaults-backed, applied live, no restart needed.
- `SettingsView.swift`: settings shell — sidebar navigation (General/Transcription/Apps/Models/History/About) + detail pane. Microphone lives inside General.
- `SettingsPanes.swift`: the individual settings panes and the mic test preview.
- `SettingsControls.swift`: card/row/scaffold building blocks the panes are made of, plus FlowLayout (deliberately dumb wrapping layout) and SelectableChip.
- `SettingsWindow.swift`: managed NSWindow that hosts SettingsView. Exists because SwiftUI's Settings scene is broken for menu bar apps on macOS 26.
- `WelcomeWindow.swift` / `WelcomeView.swift`: first-run window. Fresh installs (no bundled or cached model) must explicitly approve the one-time ~600 MB model download; shows live progress via AppState.ModelState.downloading, then a live Microphone/Accessibility checklist (PermissionsChecklist polls every second).
- `HistoryStore.swift`: recent transcripts, capped at 500, local UserDefaults only. The pane shows 20 with Show More paging, exports all to a text file, and rows offer "+" to build a replacement rule from a transcript (no learning: creates ordinary visible rules).
- `WordPack.swift`: shareable JSON bundle of replacements + Names & phrases; SettingsStore.exportPack()/merge() (merge-only, never deletes). The Tech Starter Pack lives at docs/tech-starter-pack.json.
- `VariationSuggester.swift`: FoundationModels-generated mishearing suggestions for a word; human approves each before it becomes a rule.
- `StatsStore.swift`: cumulative local dictation stats (words, seconds, streak) for the History header tiles, with a user-facing reset.
- `MicDevices.swift`: CoreAudio input-device listing + UID resolution for the mic picker.
- `Cleaner.swift`: optional on-device AI cleanup (Apple Foundation Models, macOS 26+). Takes the user's Names & phrases vocabulary and nudges close mishearings to exact spellings. Returns raw text on any failure.
- `Sounds.swift`: start/stop cues in three packs (Minimal/Wood bundled WAVs, Classic system sounds).
- `SystemAudio.swift`: CoreAudio duck-to-20%/restore of the default output + outputIsActive() check (HDMI/DP monitors often expose no volume control, so ducking falls back to media pause).
- `MediaKeys.swift`: synthetic play/pause media key (F8). Pauses/resumes whatever owns Now Playing while dictating; only sent when audio is flowing because it's a blind toggle.
- `UpdateChecker.swift`: daily check of api.github.com's latest-release tag vs the running version (About toggle, on by default); "Update to Goji X…" in the menu bar + About installs in-app (download DMG -> quiet mount -> stage -> swap /Applications/Goji.app -> strip quarantine -> relaunch). Falls back to the browser DMG when not running from /Applications or on any failure.
- `Permissions.swift`: mic + Accessibility helpers.
- `MenuContent.swift`: the status bar menu (paste last, settings, permissions, quit).

## Gotchas

- Never capture the mic through `AVAudioEngine.inputNode`. On macOS it wraps the *system default* input in a `CADefaultDeviceAggregate` the moment it's created, before `kAudioOutputUnitProperty_CurrentDevice` can redirect it, so every recording wakes the default device even when Goji is set to another mic. With Bluetooth headphones as the default that spins up the HFP mic each time; once the Bluetooth audio stack wedges (`BTAudioXpcConnection::SendStartMsg null values`, `HALS_IOContext Initialize failed` in coreaudiod), the IO thread never starts and every mic delivers zero buffers until a reboot (restarting coreaudiod is NOT enough). `AudioRecorder` uses `AVCaptureSession` + `AVCaptureAudioDataOutput` bound to the device by UID instead. Repro/verify with `swift scripts/mic-probe.swift BuiltInMicrophoneDevice` (engine path) vs `swift scripts/mic-probe-capture.swift BuiltInMicrophoneDevice` (capture path).
- `scripts/install-local.sh`: Release build + Developer ID sign + swap into /Applications + relaunch, for testing a fix on this Mac. Debug builds from Xcode/xcodebuild carry a different signature, so Accessibility silently fails for them (hotkey may work, paste won't) until re-granted.

- SwiftUI's `Settings` scene / `openSettings()` / `SettingsLink` silently no-op for menu-bar-only apps on macOS 26 (Tahoe) — no window render tree to resolve against (see steipete.me post from Jun 2025). That's why `SettingsWindow.swift` manages a plain NSWindow. Don't reintroduce a `Settings` scene.
- A grouped SwiftUI `Form` (List-backed) inside an NSHostingView window sends the macOS 26 layout engine into an exponential re-measure: window paints once, then the main thread pegs (beachball, dead controls). Confirmed via `sample`. Settings panes use the hand-rolled cards in `SettingsControls.swift` instead — don't swap them back to `Form`.
- NSEvent global monitors are observe-only. Anything that must CONSUME a key (Esc during recording) needs a CGEventTap — see `EscapeInterceptor.swift`. Keep taps armed only while recording; a stalled always-on tap degrades typing system-wide.
- `project.pbxproj` is hand-written (objectVersion 70, synchronized folder). New `.swift` files dropped into `Goji/` are picked up automatically. Never add per-file PBX entries.
- FluidAudio resolves to 0.15.x (pbxproj says `from: 0.12.4`, upToNextMajor). Their README and docs lag the real API. The exact source Xcode compiles against is snapshotted in `.fluidaudio-src/` (gitignored): grep THAT, not the docs, before touching any FluidAudio call. Refresh the snapshot from `~/Library/Developer/Xcode/DerivedData/Goji-*/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio` after any version bump.
- `AsrManager.transcribe` requires `decoderState: inout TdtDecoderState` (fresh one per utterance). The simpler-looking `UnifiedAsrManager` is a DIFFERENT model (Parakeet Unified, not multilingual v3), don't switch to it casually.
- Accessibility permission is tied to the code signature. After changing signing identity: `tccutil reset Accessibility com.brendanrong.Goji`, then re-grant.
- Sandbox is OFF on purpose (synthetic keystrokes need it off). Hardened runtime is ON with the audio-input entitlement, so notarization works later.
- git from the Cowork sandbox: prefix read commands with `GIT_OPTIONAL_LOCKS=0`.
- `Cleaner.swift` uses the FoundationModels framework (LanguageModelSession). Unlike FluidAudio there's no local source snapshot for it; if it breaks on an SDK update, check Apple's current API before fighting the compiler.
- Distribution: `scripts/release.sh` builds two DMGs (`Goji.dmg` slim, the update link and the cask point here; `Goji-with-model.dmg` with the model bundled) and updates the Homebrew tap when `~/Developer/homebrew-goji` is cloned (template in `homebrew/goji.rb.template`, `brew install --cask brendanrong/goji/goji`). `make-dmg.sh` takes `DMG_NAME`.
- `make-dmg.sh`: Release build + Developer ID signing + DMG with a styled window (dmg-background.png + Finder AppleScript layout: app left, Applications right, drag hint text). First run prompts to let Terminal control Finder. Signs with the "Developer ID Application" cert (team VTMKE23N5G) and strips get-task-allow so notarization passes. `BUNDLE_MODEL=1` copies the Parakeet model from `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3` (NO -coreml suffix: FluidAudio strips it from repo names for cache folders) into `Contents/Resources/FluidAudioModels/` (Transcriber checks there first). `NOTARIZE=1` submits + staples using the `goji-notary` keychain profile (one-time: `xcrun notarytool store-credentials goji-notary --apple-id <Apple ID> --team-id VTMKE23N5G` with an app-specific password).

## Conventions

- Small files, one screen max for views.
- One logical change per commit, conventional messages (feat:, fix:, chore:).
- No analytics, no crash reporters, no telemetry, ever. The whole point is nothing leaves the Mac.
