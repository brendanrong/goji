import AppKit
import AVFoundation
import OSLog

/// "Copy Diagnostics": one text block that explains a broken dictation without
/// a screen-share. Environment + permissions + the last few minutes of Goji's
/// own log lines (no transcript text is ever logged). Goes to the clipboard only.
enum Diagnostics {
    @MainActor
    static func copyToClipboard(state: AppState) {
        let text = report(state: state)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.dictation.notice("diagnostics copied (\(text.count) chars)")
    }

    @MainActor
    static func report(state: AppState) -> String {
        let settings = SettingsStore.shared
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let mic = settings.micDeviceUID.map { uid in
            MicDevices.inputDevices().first { $0.uid == uid }?.name ?? "\(uid) (not connected)"
        } ?? "System Default"
        let systemDefault = MicDevices.systemDefaultInput()?.name ?? "none"
        let micAuth: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micAuth = "granted"
        case .denied: micAuth = "DENIED"
        case .restricted: micAuth = "restricted"
        case .notDetermined: micAuth = "not asked yet"
        @unknown default: micAuth = "unknown"
        }

        var lines: [String] = []
        lines.append("Goji \(UpdateChecker.currentVersion) diagnostics, \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("macOS \(os)")
        lines.append("Model: \(settings.selectedModel.displayName), state: \(state.modelState)")
        lines.append("Mic setting: \(mic)")
        lines.append("System default input: \(systemDefault)")
        lines.append("Microphone permission: \(micAuth)")
        lines.append("Accessibility (paste): \(Permissions.accessibilityGranted ? "granted" : "NOT granted")")
        lines.append("Hotkey: \(settings.hotkeyDisplay), mode: \(settings.activationMode)")
        lines.append("AI cleanup: \(settings.cleanupEnabled ? "on" : "off")")
        lines.append("Last error: \(state.lastError ?? "none")")
        lines.append("")
        lines.append("Log (last 10 minutes):")
        lines.append(contentsOf: recentLogLines(minutes: 10))
        return lines.joined(separator: "\n")
    }

    /// This process's own unified-log entries for our subsystem.
    private static func recentLogLines(minutes: Int) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = store.position(date: Date().addingTimeInterval(-Double(minutes) * 60))
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            let entries = try store.getEntries(at: since, matching: predicate)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            var lines: [String] = []
            for entry in entries {
                guard let log = entry as? OSLogEntryLog else { continue }
                let level: String
                switch log.level {
                case .error, .fault: level = "ERR "
                case .info: level = "info"
                case .debug: level = "dbg "
                default: level = "    "
                }
                lines.append("\(formatter.string(from: log.date)) \(level) [\(log.category)] \(log.composedMessage)")
            }
            return lines.isEmpty ? ["(no entries)"] : lines.suffix(200).map { $0 }
        } catch {
            return ["(couldn't read log: \(error.localizedDescription))"]
        }
    }
}
