# Goji

Local, private dictation for macOS. Hold Right Option, talk, release, and your words paste wherever your cursor is. Slack, Chrome, Xcode, terminals, anything.

Everything runs on your Mac. The speech model, the cleanup, the history. Nothing you say ever leaves your computer.

## Install

Download the latest `Goji.dmg` from the [Releases page](https://github.com/brendanrong/goji/releases), open it, drag Goji into Applications. Signed and notarized, so it opens without Gatekeeper drama.

First launch: grant Microphone (macOS asks), grant Accessibility (needed to paste), and approve the one-time speech model download (about 600 MB, comes down fast). After that it works fully offline.

From then on Goji updates itself: one click in the menu bar when a new version is out.

## Use

- Hold Right Option, speak, release. Or pick another key, or record your own combo (Fn + Right Control if that's your thing).
- Hold or Toggle mode. In Hold, double-tap locks recording hands-free. Esc cancels.
- The listening indicator lives in the notch (or a bottom panel if you prefer, or on displays without a notch it draws its own).
- Switch microphones straight from the menu bar.
- While you dictate, Goji can duck your music to 20% or pause it entirely. Your call.

## Teach it your words

The speech model has never heard of your teammates or your stack. Three ways to fix that, all in Settings:

- **Names & phrases**: add a word once and AI cleanup nudges close mishearings to the exact spelling (needs Apple Intelligence).
- **Word replacements**: literal find and replace, every time, no AI. Type "Jira" into the box and hit Suggest Variations to approve the likely mishearings as rules in one go.
- **History**: spot a wrong word in a past transcript, hit +, click the word, type the fix. Done forever.

Rules and words export as one JSON file you can share. Start with the [Tech Starter Pack](https://brendanrong.github.io/goji/tech-starter-pack.json): "git hub" → GitHub, "a sink" → async, "Cooper Netties" → Kubernetes, and friends.

## Models

Parakeet v3 (multilingual, fast, the default) ships the show. Parakeet v2 (English-only) and Cohere Transcribe (bigger, strongest accuracy, English for now) are one click to download, switch, or remove in Settings > Models. All on-device, all on the Neural Engine.

## Privacy

No accounts, no telemetry, no analytics, free. The only network calls Goji ever makes:

- The one-time model download (GitHub, falling back to HuggingFace).
- Optional extra models, if you download them.
- A daily check of GitHub's releases feed for updates (toggle in Settings > About).

That's the whole list. Transcripts, settings, and stats live in your user defaults and nowhere else.

## Build from source

Open `Goji.xcodeproj` in Xcode, pick your signing team, Cmd+R. macOS 14+, Apple Silicon strongly recommended (the models run on the Neural Engine).

`make-dmg.sh` does the release dance: Release build, Developer ID signing, styled DMG, optional notarization.

## Caveats

- AI cleanup needs macOS 26 with Apple Intelligence enabled. Everything else works without it.
- Cohere Transcribe is pinned to English until a language picker lands.
- Accessibility permission is tied to the code signature. If you build from source over an installed copy, macOS may make you re-grant it.

## License

MIT. Tweak away.

---

Built by [Brendan Rong](https://github.com/brendanrong). Speech recognition by [FluidAudio](https://github.com/FluidInference/FluidAudio) and NVIDIA's Parakeet models.
