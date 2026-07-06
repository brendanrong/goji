import AppKit
import SwiftUI

/// The modifier bits Goji can watch (device-dependent left/right + Fn), in
/// display order. The union of held bits forms a custom combo's deviceMask.
enum ModifierBits {
    static let all: [(mask: UInt, symbol: String)] = [
        (NSEvent.ModifierFlags.function.rawValue, "Fn"),
        (0x01, "Left ⌃"), (0x2000, "Right ⌃"),
        (0x20, "Left ⌥"), (0x40, "Right ⌥"),
        (0x08, "Left ⌘"), (0x10, "Right ⌘"),
        (0x02, "Left ⇧"), (0x04, "Right ⇧"),
    ]

    static let unionMask: UInt = all.reduce(0) { $0 | $1.mask }

    static func label(for mask: UInt) -> String {
        all.filter { mask & $0.mask != 0 }.map(\.symbol).joined(separator: " + ")
    }
}

/// Willow-style combo recorder: click Record, hold any mix of modifier keys
/// (left/right specific, Fn included), release, and the combo is saved.
struct HotkeyRecorder: View {
    /// True while a recording session is active. HotkeyMonitor checks this so
    /// holding your current shortcut mid-recording can't start a dictation.
    @MainActor static var isRecording = false

    @ObservedObject private var settings = SettingsStore.shared
    @State private var recording = false
    @State private var capturedMask: UInt = 0
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.callout)
                .foregroundStyle(recording ? Color.accentColor : Color.secondary)
            Button(recording ? "Cancel" : "Record Keys") {
                recording ? finish() : begin()
            }
        }
        .onDisappear { finish() }
    }

    private var statusText: String {
        if recording {
            return capturedMask == 0 ? "Hold the keys you want…" : ModifierBits.label(for: capturedMask)
        }
        if let custom = settings.customHotkey, custom.deviceMask != 0 {
            return custom.label
        }
        return "Nothing recorded yet"
    }

    private func begin() {
        recording = true
        Self.isRecording = true
        capturedMask = 0
        // Local monitor is enough: this row only exists inside the focused
        // settings window. Swallow the events so nothing else reacts.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let held = event.modifierFlags.rawValue & ModifierBits.unionMask
        capturedMask |= held
        if held == 0, capturedMask != 0 {
            // Everything released: commit the biggest set that was held together.
            settings.customHotkey = CustomHotkey(
                deviceMask: capturedMask,
                label: ModifierBits.label(for: capturedMask)
            )
            finish()
        }
    }

    private func finish() {
        recording = false
        Self.isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
