import AppKit

/// Pastes text into the frontmost app: swap the pasteboard, post a synthetic Cmd+V,
/// then restore whatever string was on the pasteboard. Requires Accessibility.
@MainActor
final class TextInserter {
    func insert(_ text: String) {
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
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // kVK_ANSI_V

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
