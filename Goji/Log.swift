import Foundation
import os

/// Unified-log loggers, one per area. The log is the only store: nothing on
/// disk, nothing off the Mac. Read it with
///   log show --last 5m --predicate 'subsystem == "com.brendanrong.Goji"'
/// or Copy Diagnostics in the menu bar.
///
/// Never log transcript text. Lengths, durations, device names, and errors only.
/// Use .notice (persisted, shows in `log show` without --info) for phase lines;
/// .info is dropped from the store and invisible in Copy Diagnostics.
enum Log {
    static let subsystem = "com.brendanrong.Goji"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let dictation = Logger(subsystem: subsystem, category: "dictation")
    static let paste = Logger(subsystem: subsystem, category: "paste")
    static let model = Logger(subsystem: subsystem, category: "model")

    /// Whole milliseconds since `start`, for timing lines.
    static func ms(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
