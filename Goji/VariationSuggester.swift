import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates plausible speech-to-text mishearings of a word, for the user to
/// approve as replacement rules. Suggestions only: every rule that gets
/// created passes through a human click first, so creative junk costs nothing.
enum VariationSuggester {
    static func suggestions(for word: String) async -> [String] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await generate(word)
        }
        #endif
        return []
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func generate(_ word: String) async -> [String] {
        guard SystemLanguageModel.default.isAvailable else { return [] }
        let instructions = """
            You predict how dictation software mishears words. Given a word or \
            name, list 8 plausible ways a speech-to-text model might write it \
            when spoken aloud: similar-sounding real words, phonetic spellings, \
            and split-word forms. One suggestion per line. No numbering, no \
            punctuation, no commentary. Never output the given word itself.
            """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Word: \(word)",
                options: GenerationOptions(temperature: 0.7)
            )
            let lowered = word.lowercased()
            var seen = Set<String>()
            let lines = response.content
                .split(whereSeparator: \.isNewline)
                .map {
                    $0.trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: .punctuationCharacters)
                }
                .filter { !$0.isEmpty && $0.lowercased() != lowered && $0.count < 40 }
                .filter { seen.insert($0.lowercased()).inserted }
            return Array(lines.prefix(10))
        } catch {
            return []
        }
    }
    #endif
}
