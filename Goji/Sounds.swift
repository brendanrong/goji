import AppKit

/// Subtle audio cues so you know recording state without looking at the HUD.
/// Three packs: Minimal (soft sine blips), Wood (marimba-ish taps), Classic
/// (the macOS Pop/Tink system sounds). Rising pair for start, falling for stop.
@MainActor
enum Sounds {
    private static var cache: [String: NSSound] = [:]

    static func recordingStarted() {
        play(cue(start: true), volume: 0.6)
    }

    static func recordingStopped() {
        play(cue(start: false), volume: 0.55)
    }

    private static func cue(start: Bool) -> NSSound? {
        switch SettingsStore.shared.soundPack {
        case .minimal:
            return bundled(start ? "RecordStart" : "RecordStop")
        case .wood:
            return bundled(start ? "WoodStart" : "WoodStop")
        case .classic:
            return NSSound(named: start ? "Pop" : "Tink")
        }
    }

    private static func bundled(_ name: String) -> NSSound? {
        if let cached = cache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return nil }
        cache[name] = sound
        return sound
    }

    private static func play(_ sound: NSSound?, volume: Float) {
        guard let sound else { return }
        // play() on a sound that is still ringing is a no-op and the cue
        // silently drops. Restart it instead.
        if sound.isPlaying {
            sound.stop()
        }
        sound.volume = volume
        sound.play()
    }
}
