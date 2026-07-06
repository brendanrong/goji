import Foundation

/// Shareable bundle of Word replacements + Names & phrases as one JSON file.
/// Agent-authorable and team-shareable; import merges and never deletes.
struct WordPack: Codable {
    struct Rule: Codable {
        var find: String
        var replace: String
    }

    var name: String?
    var format: Int = 1
    var vocabulary: [String] = []
    var replacements: [Rule] = []
}

extension SettingsStore {
    func exportPack() -> WordPack {
        WordPack(
            name: "My Goji Words",
            format: 1,
            vocabulary: vocabularyTerms,
            replacements: replacements
                .filter { !$0.find.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { WordPack.Rule(find: $0.find, replace: $0.replace) }
        )
    }

    /// Merge only: existing rules and words always win. Returns counts for
    /// the confirmation caption.
    func merge(_ pack: WordPack) -> (rules: Int, words: Int, skipped: Int) {
        var rulesAdded = 0
        var wordsAdded = 0
        var skipped = 0

        for rule in pack.replacements {
            let find = rule.find.trimmingCharacters(in: .whitespaces)
            let replace = rule.replace.trimmingCharacters(in: .whitespaces)
            guard !find.isEmpty, !replace.isEmpty else {
                skipped += 1
                continue
            }
            if replacements.contains(where: { $0.find.compare(find, options: .caseInsensitive) == .orderedSame }) {
                skipped += 1
            } else {
                replacements.append(ReplacementRule(find: find, replace: replace))
                rulesAdded += 1
            }
        }

        for word in pack.vocabulary {
            let text = word.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                skipped += 1
                continue
            }
            if vocabulary.contains(where: { $0.text.compare(text, options: .caseInsensitive) == .orderedSame }) {
                skipped += 1
            } else {
                vocabulary.append(VocabWord(text: text))
                wordsAdded += 1
            }
        }

        return (rulesAdded, wordsAdded, skipped)
    }
}
