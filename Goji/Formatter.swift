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
        /// "eighty kilos" -> "80 kilos", "five point one" -> "5.1", "fifteenth" -> "15th".
        /// One to nine stay as words. Parakeet is inconsistent about this on its own.
        var numbersAsDigits = true
        /// "comma", "full stop", "question mark", "open quote" ... become the marks.
        var spokenPunctuation = true

        static let all = Options()
        static let none = Options(spokenCommands: false, removeFillers: false, collapseStutters: false, numbersAsDigits: false, spokenPunctuation: false)
    }

    static func format(_ text: String, options: Options = .all) -> String {
        var s = text
        if options.removeFillers { s = removeFillers(s) }
        if options.collapseStutters { s = collapseStutters(s) }
        if options.numbersAsDigits { s = NumberWords.normalize(s) }
        if options.spokenPunctuation {
            s = applyWebAddresses(s)
            s = applySpokenPunctuation(s)
        }
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

    // MARK: Web addresses

    /// "X dot Y" only becomes "X.Y" when it ends in one of these, so "polka dot
    /// dress" and "dot dot dot" stay words.
    private static let tlds = "com|net|org|io|ai|dev|app|new|co|au|uk|nz|us|ca|so|me|xyz|gg|tv|fm|sh|ly|to|edu|gov|info|biz|site|design|page|link"
    /// Spoken "dot" plus whatever Parakeet wrapped it in: "bolt dot new",
    /// "Bolt. Dot. New", "Bolt.dot.new".
    private static let dotSep = #"\s*[.,]?\s*(?<![\w'])dot(?![\w'])\s*[.,]?\s*"#
    private static let label = #"[A-Za-z0-9][A-Za-z0-9-]*"#
    private static let dotSepRegex = regex(dotSep)
    private static let address = regex(
        #"(?<![\w'@.-])"# + label + #"(?:"# + dotSep + label + #")*"# + dotSep + #"(?:"# + tlds + #")(?![\w-])"#
    )
    /// "brendan at canva.com" -> "brendan@canva.com". Runs after `address`, so
    /// the domain is already written. The local part may hold spoken dots too.
    private static let email = regex(
        #"(?<![\w'@.-])("# + label + #"(?:"# + dotSep + label + #")*)\s+at\s+((?:[a-z0-9-]+\.)+(?:"# + tlds + #"))(?![\w-])"#
    )
    /// Words that end "... at site.com" in normal speech: "sign up at", "find us
    /// at", "I work at". These keep the "at".
    private static let notEmailLocal: Set<String> = [
        "up", "me", "us", "them", "him", "her", "it", "you", "out", "back", "in", "on", "here", "there",
        "look", "home", "work", "works", "live", "find", "see", "meet", "stay", "be", "is", "are", "was",
        "were", "now", "online", "available", "only", "just", "free", "today", "site", "page", "link", "app",
    ]

    private static func applyWebAddresses(_ text: String) -> String {
        var s = replacing(address, in: text) { ns, match in
            let raw = ns.substring(with: match.range)
            return dotSepRegex.stringByReplacingMatches(in: raw, range: full(raw), withTemplate: ".").lowercased()
        }
        s = replacing(email, in: s) { ns, match in
            let rawLocal = ns.substring(with: match.range(at: 1))
            let local = dotSepRegex.stringByReplacingMatches(in: rawLocal, range: full(rawLocal), withTemplate: ".").lowercased()
            let spokenDot = local != rawLocal.lowercased()
            if !spokenDot, notEmailLocal.contains(local) || local.hasSuffix("ed") || local.hasSuffix("ing") {
                return nil
            }
            return local + "@" + ns.substring(with: match.range(at: 2)).lowercased()
        }
        return s
    }

    /// Replace each match with `transform`'s result; nil leaves the match as is.
    private static func replacing(_ re: NSRegularExpression, in text: String, _ transform: (NSString, NSTextCheckingResult) -> String?) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in re.matches(in: text, range: full(text)) {
            guard let replacement = transform(ns, match) else { continue }
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += replacement
            cursor = match.range.location + match.range.length
        }
        return out + ns.substring(from: cursor)
    }

    // MARK: Spoken punctuation

    /// Placeholder quote/bracket marks so tidy can tell openers from closers;
    /// they become straight characters at the very end.
    private static let openQuote = "\u{201C}"
    private static let closeQuote = "\u{201D}"

    /// A determiner in front ("the comma", "my period", "this quote") means the
    /// word is a noun, not a command.
    private static let notAfterDeterminer = #"(?<!\b(?:the|a|an|this|that|my|your|his|her|its|our|their|each|every|of|first|second|last|next|one)\s)"#

    private enum Attach { case left, right, none }

    private struct Mark {
        let phrase: String
        let output: String
        /// left: sticks to the word before (",", ")") and absorbs punctuation
        /// Parakeet already put next to the spoken word. right: sticks to the
        /// word after ("(", "#"). none: keeps the spaces around it ("&", "-").
        let attach: Attach
    }

    private static let marks: [Mark] = [
        Mark(phrase: "full stop", output: ".", attach: .left),
        Mark(phrase: "period", output: ".", attach: .left),
        Mark(phrase: "comma", output: ",", attach: .left),
        Mark(phrase: "question mark", output: "?", attach: .left),
        Mark(phrase: "exclamation (?:mark|point)", output: "!", attach: .left),
        Mark(phrase: "semicolon", output: ";", attach: .left),
        Mark(phrase: "colon", output: ":", attach: .left),
        Mark(phrase: "(?:ellipsis|dot dot dot)", output: "\u{2026}", attach: .left),
        Mark(phrase: "(?:close|end) (?:quote|quotation)(?: marks?)?", output: closeQuote, attach: .left),
        Mark(phrase: "unquote", output: closeQuote, attach: .left),
        Mark(phrase: "(?:open|begin|start) (?:quote|quotation)(?: marks?)?", output: openQuote, attach: .right),
        Mark(phrase: "(?:close|end) (?:bracket|paren|parenthesis|parentheses)", output: ")", attach: .left),
        Mark(phrase: "open (?:bracket|paren|parenthesis|parentheses)", output: "(", attach: .right),
        Mark(phrase: "at sign", output: "@", attach: .left),
        Mark(phrase: "hashtag", output: "#", attach: .right),
        Mark(phrase: "ampersand", output: "&", attach: .none),
        Mark(phrase: "(?:forward )?slash", output: "/", attach: .left),
        Mark(phrase: "hyphen", output: "-", attach: .left),
        Mark(phrase: "dash", output: "-", attach: .none),
    ]

    private static let markRegexes: [(NSRegularExpression, Mark)] = marks.map { mark in
        // Optional punctuation on either side: Parakeet often writes "comma," or ". Full stop."
        // The determiner guard only applies to marks that read as nouns
        // ("the comma", "my period"); "this open quote" is a command.
        let pattern: String
        switch mark.attach {
        case .left:
            pattern = #"[,.!?;:]?\s*(?<![\w'])"# + notAfterDeterminer + mark.phrase + #"(?![\w'])[,.!?;:]?"#
        case .right:
            pattern = #"(?<![\w'])"# + mark.phrase + #"(?![\w'])[,.!?;:]?\s*"#
        case .none:
            pattern = #"(?<![\w'])"# + notAfterDeterminer + mark.phrase + #"(?![\w'])"#
        }
        return (regex(pattern), mark)
    }

    private static func applySpokenPunctuation(_ text: String) -> String {
        var s = text
        for (re, mark) in markRegexes {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: NSRegularExpression.escapedTemplate(for: mark.output))
        }
        return s
    }

    // MARK: Tidy

    // ICU wants \x{...} for code points inside these raw patterns.
    private static let spaceBeforePunct = regex(#"\s+([,.!?;:\x{2026}\x{201D})@/])"#)
    private static let spaceAfterOpener = regex(#"([\x{201C}(#@/])\s+"#)
    private static let spaceBeforeOpener = regex(#"(\w)([\x{201C}(])"#)
    private static let spaceAfterCloser = regex(#"([\x{201D})])(\w)"#)
    private static let doubledMark = regex(#"([,.!?;:])\1+"#)
    private static let doubledPunct = regex(#"([,.!?;:])(?:\s*[,;:])+"#)
    private static let commaThenStop = regex(#",\s*([.!?])"#)
    private static let multiSpace = regex(#"[ \t]{2,}"#)
    private static let spaceAroundBreak = regex(#"[ \t]*\n[ \t]*"#)
    private static let lowercaseSentenceStart = regex(#"(^|[.!?]\s+|\n)(\p{Ll})"#)

    private static func tidy(_ text: String) -> String {
        var s = text
        s = spaceBeforePunct.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        s = spaceAfterOpener.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        s = spaceBeforeOpener.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1 $2")
        s = spaceAfterCloser.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1 $2")
        s = doubledMark.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
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
        // Placeholder curly quotes become plain ones (safe in code and chat).
        return (ns as String)
            .replacingOccurrences(of: openQuote, with: "\"")
            .replacingOccurrences(of: closeQuote, with: "\"")
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

/// Spelled-out numbers to digits. Runs of number words (with hyphens, "and"
/// after hundred, "a hundred", "point" decimals, ordinals) are parsed and
/// replaced when the value is 10 or more, a decimal, or an ordinal of 10+.
enum NumberWords {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = ["hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]
    private static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13,
        "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50,
        "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90,
        "hundredth": 100, "thousandth": 1_000,
    ]

    private static let token = try! NSRegularExpression(pattern: #"[A-Za-z]+|[^A-Za-z]+"#)

    private static let letterNumber = try! NSRegularExpression(pattern: #"\b([QqVv]) (\d+)\b"#)

    // MARK: Digit runs

    /// Four or more single digits in a row are a code, card or phone number:
    /// "four one two three" -> "4123". Fewer stay words, so "two three people"
    /// and "zero zero seven" are untouched. An "Oh," with a comma is a word.
    private static let digitWord = #"(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|\d)"#
    private static let digitUnit = #"(?:(?:double|triple)\s+)?"# + digitWord
    private static let digitRun = try! NSRegularExpression(
        pattern: #"(?<![\w'])(?!oh,)"# + digitUnit + #"(?:(?:[,.]?\s+|-)"# + digitUnit + #"){3,}(?![\w'])"#,
        options: [.caseInsensitive]
    )
    private static let digitToken = try! NSRegularExpression(pattern: #"[A-Za-z]+|\d"#)
    private static let digitValues: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    private static func joinDigitRuns(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in digitRun.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let run = ns.substring(with: match.range)
            let rns = run as NSString
            var digits = ""
            var repeatCount = 1
            for t in digitToken.matches(in: run, range: NSRange(location: 0, length: rns.length)) {
                let w = rns.substring(with: t.range).lowercased()
                if w == "double" { repeatCount = 2; continue }
                if w == "triple" { repeatCount = 3; continue }
                digits += String(repeating: digitValues[w] ?? w, count: repeatCount)
                repeatCount = 1
            }
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + digits
            cursor = match.range.location + match.range.length
        }
        return out + ns.substring(from: cursor)
    }

    static func normalize(_ input: String) -> String {
        let text = joinDigitRuns(input)
        let ns = text as NSString
        let tokens = token.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        var out = ""
        var i = 0
        while i < tokens.count {
            if let (consumed, replacement) = parseRun(tokens, from: i) {
                out += replacement
                i += consumed
            } else {
                out += tokens[i]
                i += 1
            }
        }
        // "Q 3" -> "Q3", "v 2" -> "v2".
        return letterNumber.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1$2")
    }

    /// Try to read a number starting at tokens[start]. Returns how many tokens
    /// it used and the digit string, or nil if it isn't a number worth converting.
    private static func parseRun(_ tokens: [String], from start: Int) -> (Int, String)? {
        var i = start
        var total = 0
        var current = 0
        var sawNumber = false
        var decimals: String?
        var ordinal: Int?
        var lastWordEnd = start  // index just past the last token that belongs to the number
        var pendingSeparator = ""

        func isSeparator(_ t: String) -> Bool { t == " " || t == "-" }

        while i < tokens.count {
            let raw = tokens[i]
            let w = raw.lowercased()
            if isSeparator(raw) {
                if !sawNumber && i == start { return nil }
                pendingSeparator = raw
                i += 1
                continue
            }
            if decimals != nil {
                // After "point": single digits only.
                if let d = units[w], d <= 9 {
                    decimals! += String(d)
                    sawNumber = true
                    lastWordEnd = i + 1
                    i += 1
                    continue
                }
                break
            }
            if w == "a", !sawNumber, i + 2 < tokens.count, isSeparator(tokens[i + 1]), scales[tokens[i + 2].lowercased()] != nil {
                current = 1
                i += 1
                continue
            }
            if w == "and", sawNumber, (current > 0 && current % 100 == 0) || (current == 0 && total > 0), i + 2 < tokens.count, isSeparator(tokens[i + 1]),
               (units[tokens[i + 2].lowercased()] != nil || tens[tokens[i + 2].lowercased()] != nil || ordinalUnits[tokens[i + 2].lowercased()] != nil) {
                i += 1
                continue
            }
            if w == "point", sawNumber, i + 2 < tokens.count, isSeparator(tokens[i + 1]), let d = units[tokens[i + 2].lowercased()], d <= 9 {
                decimals = ""
                i += 1
                continue
            }
            if let n = units[w] {
                // "two three" is two numbers, not 23: a unit after a unit ends the run.
                if current % 10 != 0 || (current >= 10 && current < 20) { break }
                current += n
            } else if let n = tens[w] {
                if current % 100 >= 10 { break }
                current += n
            } else if let n = scales[w] {
                // A bare "million" (or "3.5 million" after a decimal) stays a word.
                if !sawNumber && current == 0 { return nil }
                if n == 100 {
                    current = (current == 0 ? 1 : current) * 100
                } else {
                    total += (current == 0 ? 1 : current) * n
                    current = 0
                }
            } else if let n = ordinalUnits[w] {
                if n >= 100 { current = (current == 0 ? 1 : current) * n } else { current += n }
                ordinal = total + current
                sawNumber = true
                lastWordEnd = i + 1
                i += 1
                break
            } else {
                break
            }
            sawNumber = true
            lastWordEnd = i + 1
            i += 1
        }
        guard sawNumber else { return nil }
        // Don't swallow a separator or a dangling "a"/"and"/"point" after the number.
        let consumed = lastWordEnd - start
        _ = pendingSeparator

        if let ordinal {
            guard ordinal >= 10 else { return nil }
            return (consumed, "\(ordinal)\(ordinalSuffix(ordinal))")
        }
        let value = total + current
        if let decimals, !decimals.isEmpty {
            return (consumed, "\(value).\(decimals)")
        }
        if value >= 10 || smallNumberWanted(tokens, before: start, after: lastWordEnd) {
            return (consumed, String(value))
        }
        return nil
    }

    /// Words that take digits even for one to nine: "version 2", "step 3".
    private static let counters: Set<String> = [
        "version", "step", "chapter", "page", "section", "part", "phase", "round", "week",
        "day", "level", "stage", "tier", "gen", "season", "episode", "option", "item",
        "number", "no", "figure", "table", "room", "floor", "grade", "year", "quarter",
        "sprint", "iteration", "attempt", "take", "point", "rule", "lesson", "unit",
    ]
    /// Units that take digits: "8 kilos", "5 percent", "3 pm".
    private static let unitsAfter: Set<String> = [
        "percent", "kilos", "kilo", "kg", "kgs", "km", "kilometers", "kilometres", "meters", "metres",
        "cm", "mm", "grams", "g", "pounds", "lbs", "lb", "ounces", "oz", "litres", "liters", "ml",
        "hours", "hour", "hrs", "minutes", "minute", "mins", "min", "seconds", "sec", "secs", "ms",
        "days", "weeks", "months", "years", "dollars", "bucks", "cents", "am", "pm", "degrees",
        "reps", "sets", "x", "px", "pt", "gb", "mb", "tb", "mph", "kph", "fps",
    ]

    /// Context check for a value below 10 spanning tokens[before..<after].
    private static func smallNumberWanted(_ tokens: [String], before start: Int, after end: Int) -> Bool {
        // Previous word, skipping one separator token.
        var p = start - 1
        while p >= 0, tokens[p].trimmingCharacters(in: .whitespaces).isEmpty || tokens[p] == "-" { p -= 1 }
        if p >= 0 {
            let prev = tokens[p]
            let isAcronym = prev.count >= 1 && prev.count <= 6 && prev == prev.uppercased() && prev.rangeOfCharacter(from: .letters) != nil
            let isCamelProduct = prev.first?.isLowercase == true && prev.dropFirst().contains { $0.isUppercase }  // iOS, macOS
            if isAcronym || isCamelProduct || counters.contains(prev.lowercased()) { return true }
        }
        var n = end
        while n < tokens.count, tokens[n].trimmingCharacters(in: .whitespaces).isEmpty || tokens[n] == "-" { n += 1 }
        if n < tokens.count, unitsAfter.contains(tokens[n].lowercased()) { return true }
        return false
    }

    private static func ordinalSuffix(_ n: Int) -> String {
        let last2 = n % 100
        if (11...13).contains(last2) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
