import Foundation

/// Fits a transcript to where the cursor is: leading space, first-letter
/// case, trailing space. Pure function so scripts/formatter-tests.swift can
/// pin it down. `before`/`after` are the text around the insertion point
/// (or around the selection about to be replaced); nil means unknown, which
/// falls back to the old behaviour: text as-is plus a trailing space.
enum InsertionShaper {
    struct Context {
        var before: String
        var after: String
    }

    private static let acronym = try! NSRegularExpression(pattern: #"^[A-Z][A-Z0-9]{1,5}\b"#)

    static func shape(_ text: String, context: Context?, preserveCase: [String] = []) -> String {
        guard let context, !text.isEmpty else { return text + " " }
        var out = text

        // Mid-sentence continuation: lowercase the first letter unless it's
        // "I", an acronym, or one of the user's exact-case terms.
        let beforeTrimmed = context.before.trimmingCharacters(in: .whitespaces)
        let startsSentence = beforeTrimmed.isEmpty
            || beforeTrimmed.hasSuffix("\n")
            || ".!?".contains(beforeTrimmed.last!)
            || "\"“(\u{201C}[".contains(beforeTrimmed.last!)
        if !startsSentence, let first = out.first, first.isUppercase, !keepsCase(out, preserveCase: preserveCase) {
            out = first.lowercased() + out.dropFirst()
        }

        // Leading space: only when glued to a word or closing mark.
        if let last = context.before.last, !last.isWhitespace, !last.isNewline, !"(\"“[/@#-".contains(last) {
            out = " " + out
        }

        // Trailing space: skip when the next character is punctuation or
        // already a space; keep it at end of text so the next dictation flows.
        if let next = context.after.first {
            if next.isWhitespace || next.isNewline || ".,!?;:)\"”]".contains(next) {
                return out
            }
        }
        return out + " "
    }

    private static func keepsCase(_ text: String, preserveCase: [String]) -> Bool {
        let firstWord = text.prefix { !$0.isWhitespace }
        if firstWord == "I" || firstWord.hasPrefix("I'") || firstWord.hasPrefix("I’") { return true }
        if acronym.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
        let lowered = text.lowercased()
        return preserveCase.contains { term in
            !term.isEmpty && lowered.hasPrefix(term.lowercased()) && term.first?.isUppercase == true
        }
    }
}
