import AppKit

/// Subtle audio cues so you know recording state without looking at the HUD.
/// Custom minimal blips (soft sine pairs, bundled WAVs): rising for start,
/// falling for stop. System sounds like Pop/Tink read as glitchy when a short
/// dictation fires both within a second.
enum Sounds {
    private static let start = bundled("RecordStart") ?? NSSound(named: "Pop")
    private static let stop = bundled("RecordStop") ?? NSSound(named: "Tink")

    static func recordingStarted() {
        play(start, volume: 0.6)
    }

    static func recordingStopped() {
        play(stop, volume: 0.55)
    }

    private static func bundled(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
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
