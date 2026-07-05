import AppKit

/// Subtle audio cues so you know recording state without looking at the HUD.
enum Sounds {
    static func recordingStarted() {
        play("Pop", volume: 0.3)
    }

    static func recordingStopped() {
        play("Tink", volume: 0.25)
    }

    private static func play(_ name: String, volume: Float) {
        guard let sound = NSSound(named: name) else { return }
        // NSSound(named:) returns a cached shared instance; play() on one that
        // is still ringing is a no-op ("Already playing" in the console) and
        // the cue silently drops. Restart it instead.
        if sound.isPlaying {
            sound.stop()
        }
        sound.volume = volume
        sound.play()
    }
}
