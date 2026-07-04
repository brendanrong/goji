# Rubric

Local, private dictation for macOS. Hold Right Option, speak, release, and the transcript pastes into whatever app you're in. Native Swift menu bar app, Parakeet v3 via FluidAudio, everything on-device. Built to eventually distribute inside Canva.

Read PRD.md for scope. v1 is the core loop only. Don't gold-plate.

## Build and run

- Open `Rubric.xcodeproj` in Xcode on the Mac. Cmd+R.
- Builds ONLY work on the Mac. Never attempt to build from Cowork's Linux sandbox.
- If signing complains, pick Brendan's team under Signing & Capabilities (automatic signing).
- First run: grant Microphone (system prompt) and Accessibility (System Settings). Model (~600 MB) downloads once from HuggingFace into the user cache.

## Architecture (one line each)

- `RubricApp.swift`: @main, MenuBarExtra scene, app delegate.
- `AppState.swift`: observable state (model status, phase, permissions).
- `DictationController.swift`: the brain. Wires hotkey -> recorder -> transcriber -> inserter.
- `HotkeyMonitor.swift`: global NSEvent monitors. Right Option (keyCode 61) hold-to-talk, Esc cancels.
- `AudioRecorder.swift`: AVAudioEngine tap, converts to 16 kHz mono Float32.
- `Transcriber.swift`: FluidAudio AsrManager wrapper (actor).
- `TextInserter.swift`: pasteboard swap + synthetic Cmd+V, restores clipboard after 0.4 s.
- `HUD.swift`: floating Listening/Transcribing capsule (non-activating NSPanel).
- `Permissions.swift`: mic + Accessibility helpers.
- `MenuContent.swift`: the status bar menu.

## Gotchas

- `project.pbxproj` is hand-written (objectVersion 70, synchronized folder). New `.swift` files dropped into `Rubric/` are picked up automatically. Never add per-file PBX entries.
- FluidAudio is pinned `from: 0.12.4`. If `AsrManager`/`AsrModels` APIs drift on a version bump, check their README before fighting the compiler.
- Accessibility permission is tied to the code signature. After changing signing identity: `tccutil reset Accessibility com.brendanrong.Rubric`, then re-grant.
- Sandbox is OFF on purpose (synthetic keystrokes need it off). Hardened runtime is ON with the audio-input entitlement, so notarization works later.
- git from the Cowork sandbox: prefix read commands with `GIT_OPTIONAL_LOCKS=0`.

## Conventions

- Small files, one screen max for views.
- One logical change per commit, conventional messages (feat:, fix:, chore:).
- No analytics, no crash reporters, no telemetry, ever. The whole point is nothing leaves the Mac.
