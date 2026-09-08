import AppKit
import ApplicationServices

/// Pastes text into the frontmost app: swap the pasteboard, post a synthetic Cmd+V,
/// then restore whatever string was on the pasteboard. Requires Accessibility.
@MainActor
final class TextInserter {
    /// What the last paste put down and where, so it can be taken back.
    private(set) var lastInserted: String?
    private(set) var lastTargetBundleID: String?

    func insert(_ text: String) {
        lastInserted = text
        lastTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount
        postCommandV()

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

    /// Removes the last paste. Preferred path: confirm via Accessibility that
    /// the text right before the caret is exactly what we pasted, select it,
    /// and delete. Fallback: a single Cmd+Z, which most apps treat a paste as.
    /// Returns false when there's nothing to undo or the user has moved to
    /// another app.
    func undoLast() -> Bool {
        guard let text = lastInserted else { return false }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == lastTargetBundleID else {
            Log.paste.notice("undo skipped: different app in front")
            return false
        }
        lastInserted = nil
        if selectTrailingText(text) {
            postKey(51, flags: [])  // Delete
            Log.paste.notice("undo: selected \(text.count) chars via AX and deleted")
        } else {
            postKey(6, flags: .maskCommand)  // Z
            Log.paste.notice("undo: fell back to Cmd+Z")
        }
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
