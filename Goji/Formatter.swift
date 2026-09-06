import Foundation

/// Deterministic transcript cleanup. Pure function, no model, runs on every
/// dictation in a few microseconds. Handles the "felt magic" that used to be
/// gated behind Apple Intelligence: spoken commands, filler words, stutters.
///
/// Keep this file Foundation-only: scripts/formatter-tests.swift compiles it
/// standalone.
enum TranscriptFormatter {
    struct Options {
        /// "new line", "new paragraph", "scratch that".
        var spokenCommands = true
        /// Standalone "um", "uh", "erm", and ", you know," / "Like, " openers.
        var removeFillers = true
        /// Immediate repeats: "the the", "I I". Intentional doubles survive.
        var collapseStutters = true

        static let all = Options()
        static let none = Options(spokenCommands: false, removeFillers: false, collapseStutters: false)
    }

    static func format(_ text: String, options: Options = .all) -> String {
        var s = text
        if options.removeFillers { s = removeFillers(s) }
        if options.collapseStutters { s = collapseStutters(s) }
        if options.spokenCommands {
            // Breaks first so "scratch that" stops at a fresh paragraph.
            s = applyLineBreaks(s)
            s = applyScratchThat(s)
        }
        return tidy(s)
    }

    // MARK: Fillers

    private static let fillerWord = regex(#"(?<![\w'])(?:um+|uh+|erm+|uhm+|ah+m)(?![\w'])[,.]?\s*"#)
    private static let youKnow = regex(#",\s*you know,\s*"#)
    private static let likeOpener = regex(#"(^|[.!?]\s+|\n\s*)[Ll]ike,\s+"#)

    private static func removeFillers(_ text: String) -> String {
        var s = fillerWord.stringByReplacingMatches(in: text, range: full(text), withTemplate: "")
        s = youKnow.stringByReplacingMatches(in: s, range: full(s), withTemplate: ", ")
        s = likeOpener.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        return s
    }

    // MARK: Stutters

    /// Doubles people say on purpose. Everything else repeated back to back
    /// is treated as a stutter.
    private static let intentionalDoubles: Set<String> = [
        "had", "that", "very", "no", "so", "really", "bye", "ha", "is", "yeah",
        // Numbers are read out digit by digit: "double oh seven", "one one".
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    ]
    private static let repeatedWord = regex(#"(?<![\w'])([\w']+)(?:,?\s+)\1(?![\w'])"#)

    private static func collapseStutters(_ text: String) -> String {
        var s = text
        // Loop: "the the the" needs two passes.
        for _ in 0..<3 {
            var changed = false
            let ns = s as NSString
            var out = ""
            var cursor = 0
            for match in repeatedWord.matches(in: s, range: full(s)) {
                let word = ns.substring(with: match.range(at: 1))
                if intentionalDoubles.contains(word.lowercased()) { continue }
                out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                out += word
                cursor = match.range.location + match.range.length
                changed = true
            }
            out += ns.substring(from: cursor)
            s = out
            if !changed { break }
        }
        return s
    }

    // MARK: Spoken commands

    private static let scratchThat = regex(#"[,.!?;:]?\s*(?<![\w'])scratch that(?![\w'])[,.!?;:]*\s*"#)

    /// "X, scratch that, Y" keeps Y and drops X back to the previous sentence
    /// boundary. Repeats for every occurrence, left to right.
    private static func applyScratchThat(_ text: String) -> String {
        var s = text
        while let match = scratchThat.firstMatch(in: s, range: full(s)) {
            let ns = s as NSString
            var before = ns.substring(to: match.range.location)
            let after = ns.substring(from: match.range.location + match.range.length)
            // Drop back to the last sentence terminator or line break.
            if let boundary = before.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?\n"), options: .backwards) {
                before = String(before[..<boundary.upperBound])
            } else {
                before = ""
            }
            let joiner = before.isEmpty || before.hasSuffix("\n") ? "" : " "
            s = before + joiner + capitalizingFirst(after)
        }
        return s
    }

    /// Standalone "new line" / "new paragraph" become breaks. "a new line of
    /// products" is content: a preceding article or demonstrative protects it.
    private static let lineBreak = regex(
        #"[,.!?;:]?\s*(?<![\w'])(?<!\b(?:a|the|this|that|another|every|each|brand|whole)\s)new (line|paragraph)(?![\w'])[,.!?;:]*[ \t]*"#
    )

    private static func applyLineBreaks(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in lineBreak.matches(in: text, range: full(text)) {
            var before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            // Keep a sentence terminator that preceded the command, drop a comma.
            let leading = ns.substring(with: match.range).prefix { ",.!?;:".contains($0) }
            if let punct = leading.first, ".!?".contains(punct) {
                before += String(punct)
            }
            let kind = ns.substring(with: match.range(at: 1))
            out += before.trimmingCharacters(in: .whitespaces) + (kind == "paragraph" ? "\n\n" : "\n")
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    // MARK: Tidy

    private static let spaceBeforePunct = regex(#"\s+([,.!?;:])"#)
    private static let doubledPunct = regex(#"([,.!?;:])(?:\s*[,;:])+"#)
    private static let commaThenStop = regex(#",\s*([.!?])"#)
    private static let multiSpace = regex(#"[ \t]{2,}"#)
    private static let spaceAroundBreak = regex(#"[ \t]*\n[ \t]*"#)
    private static let lowercaseSentenceStart = regex(#"(^|[.!?]\s+|\n)(\p{Ll})"#)

    private static func tidy(_ text: String) -> String {
        var s = text
        s = spaceBeforePunct.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        s = doubledPunct.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        s = commaThenStop.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        s = multiSpace.stringByReplacingMatches(in: s, range: full(s), withTemplate: " ")
        s = spaceAroundBreak.stringByReplacingMatches(in: s, range: full(s), withTemplate: "\n")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Uppercase a lowercase letter that now starts a sentence (usually
        // because a filler or "scratch that" was removed in front of it).
        let ns = NSMutableString(string: s)
        for match in lowercaseSentenceStart.matches(in: s, range: full(s)).reversed() {
            let range = match.range(at: 2)
            ns.replaceCharacters(in: range, with: ns.substring(with: range).uppercased())
        }
        return ns as String
    }

    // MARK: Helpers

    private static func capitalizingFirst(_ text: String) -> String {
        let trimmed = text.drop { $0 == " " || $0 == "," }
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst()
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed strings checked by scripts/formatter-tests.swift.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func full(_ s: String) -> NSRange {
        NSRange(s.startIndex..., in: s)
    }
}
