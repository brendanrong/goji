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
- `HotkeyMonitor.swift`: global NSEvent monitors. Emits raw down/up for the configured modifier key (read live from SettingsStore), plus Esc.
- `AudioRecorder.swift`: AVAudioEngine tap, converts to 16 kHz mono Float32.
- `Transcriber.swift`: FluidAudio AsrManager wrapper (actor).
- `TextInserter.swift`: pasteboard swap + synthetic Cmd+V, restores clipboard after 0.4 s.
- `HUD.swift`: HUDController, places the indicator (bottom panel, notch extension, or top pill fallback).
- `HUDViews.swift`: the SwiftUI indicator views (capsule + notch shapes).
- `SettingsStore.swift`: user prefs (hotkey, hold/toggle, HUD style, login item, replacements). UserDefaults-backed, applied live, no restart needed.
- `SettingsView.swift`: single-pane grouped Settings window (Cmd+,).
- `HistoryStore.swift`: recent transcripts, capped at 50, local UserDefaults only.
- `MicDevices.swift`: CoreAudio input-device listing + UID resolution for the mic picker.
- `Cleaner.swift`: optional on-device AI cleanup (Apple Foundation Models, macOS 26+). Returns raw text on any failure.
- `Sounds.swift`: start/stop cues (system sounds, low volume).
- `Permissions.swift`: mic + Accessibility helpers.
- `MenuContent.swift`: the status bar menu (paste last, settings, permissions, quit).

## Gotchas

- `project.pbxproj` is hand-written (objectVersion 70, synchronized folder). New `.swift` files dropped into `Goji/` are picked up automatically. Never add per-file PBX entries.
- FluidAudio resolves to 0.15.x (pbxproj says `from: 0.12.4`, upToNextMajor). Their README and docs lag the real API. The exact source Xcode compiles against is snapshotted in `.fluidaudio-src/` (gitignored): grep THAT, not the docs, before touching any FluidAudio call. Refresh the snapshot from `~/Library/Developer/Xcode/DerivedData/Goji-*/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio` after any version bump.
- `AsrManager.transcribe` requires `decoderState: inout TdtDecoderState` (fresh one per utterance). The simpler-looking `UnifiedAsrManager` is a DIFFERENT model (Parakeet Unified, not multilingual v3), don't switch to it casually.
- Accessibility permission is tied to the code signature. After changing signing identity: `tccutil reset Accessibility com.brendanrong.Goji`, then re-grant.
- Sandbox is OFF on purpose (synthetic keystrokes need it off). Hardened runtime is ON with the audio-input entitlement, so notarization works later.
- git from the Cowork sandbox: prefix read commands with `GIT_OPTIONAL_LOCKS=0`.
- `Cleaner.swift` uses the FoundationModels framework (LanguageModelSession). Unlike FluidAudio there's no local source snapshot for it; if it breaks on an SDK update, check Apple's current API before fighting the compiler.
- `make-dmg.sh`: Release build + DMG. `BUNDLE_MODEL=1` copies the Parakeet model from `~/Library/Application Support/FluidAudio/Models/` into `Contents/Resources/FluidAudioModels/` (Transcriber checks there first). `NOTARIZE=1` needs one-time `xcrun notarytool store-credentials goji-notary`.

## Conventions

- Small files, one screen max for views.
- One logical change per commit, conventional messages (feat:, fix:, chore:).
- No analytics, no crash reporters, no telemetry, ever. The whole point is nothing leaves the Mac.
