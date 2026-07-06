import AppKit

/// Synthesizes the keyboard play/pause media key, same as pressing F8. It
/// targets whatever owns the system Now Playing session (Music, Spotify,
/// browser video). It's a toggle, so callers must pair pause with resume and
/// only send it when something is actually playing.
enum MediaKeys {
    private static let playPauseKey: Int32 = 16 // NX_KEYTYPE_PLAY

    static func playPause() {
        post(down: true)
        post(down: false)
    }

    private static func post(down: Bool) {
        let stateByte: Int32 = down ? 0x0A : 0x0B
        let data1 = Int((playPauseKey << 16) | (stateByte << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
