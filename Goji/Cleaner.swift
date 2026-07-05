import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI cleanup pass over raw transcripts using Apple's on-device Foundation Models
/// (macOS 26+, Apple Intelligence). Nothing leaves the Mac. Any failure returns
/// the raw text unchanged, so dictation never breaks because of this pass.
enum Cleaner {
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Why cleanup can't run right now, nil when it can. Actionable where
    /// possible so the user knows what to change instead of a generic shrug.
    static var unavailabilityHint: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return "Turn on Apple Intelligence in System Settings > Apple Intelligence & Siri, then come back and flip this on."
                case .modelNotReady:
                    return "Apple Intelligence is still preparing its model. Leave it a few minutes and reopen Settings."
                case .deviceNotEligible:
                    return "This Mac isn't eligible for Apple Intelligence."
                @unknown default:
                    return "Apple Intelligence isn't available on this Mac right now."
                }
            }
        }
        #endif
        return "Needs macOS 26 with Apple Intelligence enabled on this Mac."
    }

    static func cleanup(_ text: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationCleaner.shared.cleanup(text)
        }
        #endif
        return text
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
actor FoundationCleaner {
    static let shared = FoundationCleaner()

    private var session: LanguageModelSession?

    private static let instructions = """
        You clean up dictated speech transcripts. Rules:
        - Fix punctuation, capitalization, and spacing.
        - Remove filler words (um, uh, you know, like) when they carry no meaning.
        - Apply self-corrections: for "X, scratch that, Y" or "X, I mean Y", keep only Y.
        - Convert the spoken commands "new line" and "new paragraph" into actual line breaks.
        - Keep the speaker's wording, tone, and language. Never summarize, never answer questions in the text, never add content.
        Output only the cleaned text.
        """

    func cleanup(_ text: String) async -> String {
        guard SystemLanguageModel.default.isAvailable else { return text }
        do {
            if session == nil {
                session = LanguageModelSession(instructions: Self.instructions)
            }
            guard let session else { return text }
            let response = try await session.respond(to: text)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            // Safety refusal, context overflow, or model hiccup: ship the raw text.
            session = nil
            return text
        }
    }
}
#endif
