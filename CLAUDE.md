# Goji

Local, private dictation for macOS. Hold Right Option, speak, release, and the transcript pastes into whatever app you're in. Native Swift menu bar app, Parakeet v3 via FluidAudio, everything on-device. Built to eventually distribute inside Canva.

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
- `AudioRecorder.swift`: AVAudioEngine tap, converts to 16 kHz mono Float32.
- `Transcriber.swift`: multi-engine wrapper (actor). Parakeet v2/v3 via AsrManager, Cohere Transcribe via CoherePipeline (pinned to English for now); loads whichever SettingsStore.selectedModel says.
- `ModelCatalog.swift`: SpeechModel catalog (v3 default / v2 English / Cohere) + ModelLibrary (download via DownloadUtils.downloadRepo, remove, size on disk, reveal in Finder). Parakeet JA deliberately excluded: its files stitch together from multiple HF repos.
- `ModelFetcher.swift`: first-run model download as ONE zip from the GitHub `models-v3` release (fast CDN, real progress) into FluidAudio's cache; DictationController falls back to FluidAudio's HuggingFace crawl if it fails. The models-v3 release must be created with `--latest=false` or the site's releases/latest/download/Goji.dmg link breaks.
- `TextInserter.swift`: pasteboard swap + synthetic Cmd+V, restores clipboard after 1 s (Electron paste handlers read it late).
- `HUD.swift`: HUDController, places the indicator (bottom panel, notch extension; synthetic notch island on notchless displays).
- `HUDViews.swift`: the SwiftUI indicator views (capsule + notch shapes).
- `SettingsStore.swift`: user prefs (hotkey, hold/toggle, HUD style, login item, replacements). UserDefaults-backed, applied live, no restart needed.
- `SettingsView.swift`: settings shell — sidebar navigation (General/Microphone/Transcription/Models/History/About) + detail pane.
- `SettingsPanes.swift`: the individual settings panes and the mic test preview.
- `SettingsControls.swift`: card/row/scaffold building blocks the panes are made of.
- `SettingsWindow.swift`: managed NSWindow that hosts SettingsView. Exists because SwiftUI's Settings scene is broken for menu bar apps on macOS 26.
- `WelcomeWindow.swift` / `WelcomeView.swift`: first-run window. Fresh installs (no bundled or cached model) must explicitly approve the one-time ~600 MB model download; shows live progress via AppState.ModelState.downloading.
- `HistoryStore.swift`: recent transcripts, capped at 50, local UserDefaults only.
- `MicDevices.swift`: CoreAudio input-device listing + UID resolution for the mic picker.
- `Cleaner.swift`: optional on-device AI cleanup (Apple Foundation Models, macOS 26+). Returns raw text on any failure.
- `Sounds.swift`: start/stop cues in three packs (Minimal/Wood bundled WAVs, Classic system sounds).
- `SystemAudio.swift`: CoreAudio duck-to-20%/restore of the default output + outputIsActive() check (HDMI/DP monitors often expose no volume control, so ducking falls back to media pause).
- `MediaKeys.swift`: synthetic play/pause media key (F8). Pauses/resumes whatever owns Now Playing while dictating; only sent when audio is flowing because it's a blind toggle.
- `UpdateChecker.swift`: daily check of api.github.com's latest-release tag vs the running version (About toggle, on by default); "Update Available" surfaces in the menu bar + About, download opens releases/latest/download/Goji.dmg.
- `Permissions.swift`: mic + Accessibility helpers.
- `MenuContent.swift`: the status bar menu (paste last, settings, permissions, quit).

## Gotchas

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
- `make-dmg.sh`: Release build + Developer ID signing + DMG with a styled window (dmg-background.png + Finder AppleScript layout: app left, Applications right, drag hint text). First run prompts to let Terminal control Finder. Signs with the "Developer ID Application" cert (team VTMKE23N5G) and strips get-task-allow so notarization passes. `BUNDLE_MODEL=1` copies the Parakeet model from `~/Library/Application Support/FluidAudio/Models/` into `Contents/Resources/FluidAudioModels/` (Transcriber checks there first). `NOTARIZE=1` submits + staples using the `goji-notary` keychain profile (one-time: `xcrun notarytool store-credentials goji-notary --apple-id <Apple ID> --team-id VTMKE23N5G` with an app-specific password).

## Conventions

- Small files, one screen max for views.
- One logical change per commit, conventional messages (feat:, fix:, chore:).
- No analytics, no crash reporters, no telemetry, ever. The whole point is nothing leaves the Mac.
