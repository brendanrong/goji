import Foundation

/// Turns "what Goji wrote" vs "what you meant" into replacement-rule
/// suggestions. Word-level LCS; each changed run where both sides are short
/// (1 to 3 words) becomes a candidate rule. Pure, Foundation-only, tested in
/// scripts/formatter-tests.swift.
enum CorrectionDiff {
    struct Suggestion: Equatable, Hashable {
        let find: String
        let replace: String
    }

    static func suggestions(original: String, corrected: String) -> [Suggestion] {
        let a = words(original)
        let b = words(corrected)
        guard !a.isEmpty, !b.isEmpty, a != b else { return [] }

        // LCS table on the words. Exact comparison, so a pure case fix still
        // shows up as a change (it's a legitimate rule: "figma" -> "Figma").
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var out: [Suggestion] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                i += 1; j += 1
                continue
            }
            // Collect a changed run: advance both sides until they re-sync.
            var oldRun: [String] = []
            var newRun: [String] = []
            while i < n || j < m {
                if i < n, j < m, a[i] == b[j] { break }
                if j >= m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
                    oldRun.append(a[i]); i += 1
                } else {
                    newRun.append(b[j]); j += 1
                }
            }
            let find = strip(oldRun.joined(separator: " "))
            let replace = strip(newRun.joined(separator: " "))
            guard !find.isEmpty, !replace.isEmpty,
                  (1...3).contains(oldRun.count), (1...3).contains(newRun.count),
                  find != replace else { continue }
            let suggestion = Suggestion(find: find, replace: replace)
            if !out.contains(suggestion) { out.append(suggestion) }
        }
        return out
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Drop punctuation hugging the edges so "pod," becomes "pod".
    private static func strip(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:\"'()[]“”‘’…"))
    }
}
