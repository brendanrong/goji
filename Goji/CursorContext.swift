import AppKit
import ApplicationServices

/// Reads the text around the caret in the focused field via Accessibility so
/// the paste can be shaped to fit (see InsertionShaper). Returns nil when the
/// app doesn't expose its text (secure fields, some custom editors), in which
/// case the paste behaves as before.
enum CursorContext {
    /// How much text either side is worth looking at.
    private static let window = 200

    static func read() -> InsertionShaper.Context? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }

        // AX ranges are UTF-16 offsets, so work in NSString.
        let ns = value as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return nil }
        let beforeStart = max(0, range.location - window)
        let before = ns.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart))
        let afterStart = range.location + range.length
        let after = ns.substring(with: NSRange(location: afterStart, length: min(window, ns.length - afterStart)))
        return InsertionShaper.Context(before: before, after: after)
    }
}
