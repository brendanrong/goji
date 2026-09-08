import AppKit
import ApplicationServices

/// Pastes text into the frontmost app: swap the pasteboard, post a synthetic Cmd+V,
/// then restore whatever string was on the pasteboard. Requires Accessibility.
@MainActor
final class TextInserter {
    /// Detection of a refused paste is on; the keystroke fallback is off until
    /// the logs show the AX length check never misfires (a stale AXValue in
    /// some Electron field would otherwise mean a double insert). Flip after
    /// a week of "paste not taken" lines that were all real.
    static let typeWhenPasteFails = false

    /// What the last paste put down and where, so it can be taken back.
    private(set) var lastInserted: String?
    private(set) var lastTargetBundleID: String?

    /// `verify` false skips the refused-paste check (a paste over a selection
    /// changes the field length unpredictably).
    func insert(_ text: String, verify: Bool = true) {
        lastInserted = text
        lastTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let lengthBefore = verify ? focusedTextLength() : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount
        postCommandV()

        // Some fields refuse Cmd+V (secure inputs, a few terminals and
        // Electron editors). When the field exposes its text, check that it
        // grew; if it didn't, type the text as keystrokes instead. Fields we
        // can't read are assumed fine: typing blind risks a double insert.
        if let lengthBefore {
            let needed = max(1, (text as NSString).length / 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == self.lastTargetBundleID else { return }
                if let after = self.focusedTextLength(), after - lengthBefore < needed {
                    let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                    if Self.typeWhenPasteFails {
                        Log.paste.error("paste not taken in \(app, privacy: .public) (field grew \(after - lengthBefore) of \(text.count) chars), typing instead")
                        self.typeText(text)
                    } else {
                        Log.paste.error("paste not taken in \(app, privacy: .public) (field grew \(after - lengthBefore) of \(text.count) chars); typing fallback is off")
                    }
                }
            }
        }

        // Restore the original clipboard once the paste has had time to land,
        // but only if nothing newer was copied in the meantime. Electron apps
        // (Cowork, Slack) handle Cmd+V asynchronously and can read the
        // pasteboard hundreds of ms later when their renderer is busy, so give
        // them a full second. Preserves every representation (images, files,
        // RTF), not just plain text.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard pasteboard.changeCount == ourChangeCount else { return }
            pasteboard.clearContents()
            if !saved.isEmpty {
                pasteboard.writeObjects(saved)
            }
        }
    }

    /// Removes the last paste. Returns false when there's nothing to undo or
    /// the user has moved to another app.
    func undoLast() -> Bool {
        guard selectLastInsertion() else { return false }
        lastInserted = nil
        postKey(51, flags: [])  // Delete
        return true
    }

    /// Swaps the last paste for `text` (the correction flow). Returns false if
    /// the last paste couldn't be located.
    func replaceLast(with text: String) -> Bool {
        guard selectLastInsertion() else { return false }
        // Pasting over a selection replaces it in every text field.
        insert(text, verify: false)
        return true
    }

    /// Highlights exactly what the last paste put down. Preferred: confirm via
    /// Accessibility that the text right before the caret is ours, and select
    /// it. Otherwise: Shift+Left once per character, which is exact as long as
    /// the caret hasn't moved since the paste (it hasn't, right after a
    /// dictation). Cmd+Z was tried and is not reliable: Electron editors don't
    /// always treat a paste as one undo step.
    private func selectLastInsertion() -> Bool {
        guard let text = lastInserted else { return false }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == lastTargetBundleID else {
            Log.paste.notice("undo skipped: different app in front")
            return false
        }
        if selectTrailingText(text) {
            Log.paste.notice("selected last paste (\(text.count) chars) via AX")
            return true
        }
        for _ in 0..<text.count {
            postKey(123, flags: .maskShift)  // Left arrow
        }
        Log.paste.notice("selected last paste (\(text.count) chars) via Shift+Left")
        return true
    }

    /// If the focused field ends (at the caret) with `text`, select exactly that.
    private func selectTrailingText(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        let element = focused as! AXUIElement
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return false }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return false }
        var caret = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &caret), caret.length == 0 else { return false }

        let ns = value as NSString
        let length = (text as NSString).length
        guard caret.location >= length, caret.location <= ns.length,
              ns.substring(with: NSRange(location: caret.location - length, length: length)) == text else { return false }

        var target = CFRange(location: caret.location - length, length: length)
        guard let targetValue = AXValueCreate(.cfRange, &target) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, targetValue) == .success
    }

    /// UTF-16 length of the focused field's text, nil if it can't be read.
    private func focusedTextLength() -> Int? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        return (value as NSString).length
    }

    /// Types text as synthetic keystrokes. Line breaks go as Return so
    /// editors treat them as real newlines.
    private func typeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var remaining = Substring(line)
            while !remaining.isEmpty {
                let chunk = remaining.prefix(20)
                remaining = remaining.dropFirst(chunk.count)
                var units = Array(chunk.utf16)
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                down?.post(tap: .cghidEventTap)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                up?.post(tap: .cghidEventTap)
            }
            if index < lines.count - 1 {
                postKey(36, flags: [])  // Return
            }
        }
    }

    /// Deep-copies every item on the pasteboard so it can be put back after we
    /// borrow the clipboard for the paste.
    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func postCommandV() {
        postKey(9, flags: .maskCommand)  // kVK_ANSI_V
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
