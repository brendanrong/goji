# Goji PRD

Local dictation for macOS. Hold a key, talk, release. Words appear where your cursor is. Nothing leaves the Mac.

## Why

- Wispr Flow is paid and routes voice to a cloud server. For Canva use that's a data question we don't need to have.
- Local models now beat the cloud round trip on speed. Parakeet v3 on the Apple Neural Engine runs ~190x realtime on M-series (1 hour of audio in ~19 seconds).
- If v1 holds up for Brendan, package it and distribute to the rest of Canva.

## Prior art (steal ideas, not code)

- Wispr Flow: the UX bar. Hold key, HUD, auto-paste, AI cleanup.
- VoiceInk: closest OSS clone, also uses FluidAudio. GPL-3, so reference only, no code reuse.
- Hex (kitlangton): press-and-hold, FluidAudio, paste. Same architecture as ours.
- Handy (handy.computer): push-to-talk vs toggle modes, configurable binding. Simple settings done right.
- OpenWhispr: personal dictionary that learns from corrections, voice commands ("clean this up"), model picker.

Goji's edge: native Swift on the ANE. No Electron, tiny memory footprint, instant cold start, Apache-2.0 dependencies only.

## v1 scope

In:

- Menu bar app, no Dock icon
- Configurable modifier hotkey (default Right Option), Hold or Toggle mode, Esc cancels
- Parakeet v3 (25 European languages + JA + ZH) via FluidAudio, batch transcribe on stop
- Paste into the frontmost app via clipboard swap + synthetic Cmd+V, clipboard restored after
- HUD styles: bottom panel capsule, or notch extension (top pill fallback on external displays)
- Settings window (Cmd+,): shortcut, mode, launch at login, HUD style, replacements, history
- Word replacements: case-insensitive whole-word find/replace applied after transcription
- Transcript history: last 50, stored locally only, Paste Last Transcription in the menu
- First run: mic prompt, Accessibility prompt, one-time ~600 MB model download

Out (v2+ backlog, roughly in order):

1. AI cleanup pass using Apple Foundation Models (on-device, zero extra install on macOS 26)
2. Auto-learned corrections (OpenWhispr-style), building on word replacements
3. Streaming partial transcript in the HUD (FluidAudio SlidingWindowAsrManager)
4. In-app updates

## Decisions

- Right Option over Fn: macOS reserves Fn for system dictation and the emoji picker. A bare right-side modifier doesn't collide with normal typing.
- Batch over streaming for v1: at 190x realtime, transcribing on key release feels instant and is far simpler.
- Paste over per-character keystrokes: instant for long text, works anywhere Cmd+V works.
- No sandbox: synthetic keystrokes require it off. Means no Mac App Store, which we don't need. Distribution is a notarized DMG like Cherry/LiveWall.

## Success criteria

- A 10 s utterance lands as text under 1 s after key release on an M-series Mac
- Works in Slack, Chrome, Notes, Cursor, Xcode
- Zero network traffic after the one-time model download
- Survives sleep/wake and mic device changes without a restart
- Clipboard contents restored after every insert

## Distribution to Canva (later, after v1 proves out)

- Notarized DMG via Brendan's existing Developer ID pipeline
- Model download: bundle the CoreML model in the DMG, or point FluidAudio's `REGISTRY_URL` at an internal mirror if HuggingFace is blocked on the corp network
- Loop in IT/security before wide sharing. The pitch: audio never leaves the machine, no accounts, no telemetry, permissively licensed deps
