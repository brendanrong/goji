import Foundation

/// Turns a user's transcript fix into learnable word corrections. Diffs the
/// original against the edited text at the word level (LCS) and pairs replaced
/// runs, so editing "talked to Jaken today" into "talked to Jachin today"
/// yields ("Jaken", "Jachin"). Case-only and punctuation-only changes are
/// style, not mishearings, and are ignored.
enum CorrectionLearner {
    static func corrections(from original: String, to corrected: String) -> [(wrong: String, right: String)] {
        let a = tokens(original)
        let b = tokens(corrected)
        guard !a.isEmpty, !b.isEmpty else { return [] }

        // LCS table over normalized tokens.
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                if norm(a[i]) == norm(b[j]) {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var pairs: [(wrong: String, right: String)] = []
        var removed: [String] = []
        var added: [String] = []

        func flush() {
            defer {
                removed = []
                added = []
            }
            // Pure inserts or deletes aren't mishearing pairs.
            guard !removed.isEmpty, !added.isEmpty else { return }
            if removed.count == added.count {
                for (wrong, right) in zip(removed, added) {
                    append(&pairs, wrong: wrong, right: right)
                }
            } else if added.count == 1, (1...3).contains(removed.count) {
                append(&pairs, wrong: removed.joined(separator: " "), right: added[0])
            } else if removed.count == 1, (1...3).contains(added.count) {
                append(&pairs, wrong: removed[0], right: added.joined(separator: " "))
            }
        }

        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if norm(a[i]) == norm(b[j]) {
                flush()
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                removed.append(a[i])
                i += 1
            } else {
                added.append(b[j])
                j += 1
            }
        }
        removed.append(contentsOf: a[i...])
        added.append(contentsOf: b[j...])
        flush()

        return pairs
    }

    private static func append(_ pairs: inout [(wrong: String, right: String)], wrong: String, right: String) {
        let cleanWrong = clean(wrong)
        let cleanRight = clean(right)
        guard cleanWrong.count >= 2, cleanRight.count >= 2,
              cleanWrong.lowercased() != cleanRight.lowercased() else { return }
        pairs.append((cleanWrong, cleanRight))
    }

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func norm(_ token: String) -> String {
        clean(token).lowercased()
    }

    private static func clean(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters)
    }
}
