import FluidAudio
import Foundation

/// Wraps FluidAudio's speech engines. Actor keeps the heavy work off the main
/// thread. Parakeet v2/v3 run through AsrManager; Cohere Transcribe runs
/// through CoherePipeline. Which model loads comes from SettingsStore.
actor Transcriber {
    private var parakeet: AsrManager?
    private var cohere: (pipeline: CoherePipeline, models: CoherePipeline.LoadedModels)?
    private var loadedModel: SpeechModel?

    // Vocabulary boosting: the CTC spotter finds WHERE a Names & phrases term
    // was heard; a word only gets swapped when its TEXT also resembles the
    // term or one of its learned mishearings. (The library's batch rescorer
    // misaligns replacements onto neighboring words, so the confirmation step
    // is ours.) Parakeet only; requires the small CTC helper model.
    private var ctcModels: CtcModels?
    private var spotter: CtcKeywordSpotter?
    private var vocabContext: CustomVocabularyContext?
    private var loadedVocabWords: [VocabWord] = []

    /// True when the CTC helper model for Names & phrases boosting is cached.
    nonisolated static var boosterInstalled: Bool {
        CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory(for: .ctc110m))
    }

    /// Rebuilds the boosting pipeline for the given words. Cheap no-op when
    /// nothing changed; silently degrades to plain transcription on failure.
    func updateVocabulary(_ words: [VocabWord]) async {
        let usable = words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let wantsBoost = !usable.isEmpty && Self.boosterInstalled
        guard usable != loadedVocabWords || (wantsBoost && spotter == nil) else { return }
        loadedVocabWords = usable
        vocabContext = nil
        spotter = nil
        guard wantsBoost else { return }

        do {
            let cacheDir = CtcModels.defaultCacheDirectory(for: .ctc110m)
            let models: CtcModels
            if let ctcModels {
                models = ctcModels
            } else {
                // Files are already cached, so this loads without downloading.
                models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
                ctcModels = models
            }

            let tokenizer = try await CtcTokenizer.load(from: cacheDir)
            let tokenized = usable.compactMap { word -> CustomVocabularyTerm? in
                let text = word.text.trimmingCharacters(in: .whitespaces)
                let ids = tokenizer.encode(text)
                guard !ids.isEmpty else { return nil }
                let aliases = (word.aliases ?? []).filter { !$0.isEmpty }
                return CustomVocabularyTerm(
                    text: text,
                    weight: nil,
                    aliases: aliases.isEmpty ? nil : aliases,
                    tokenIds: nil,
                    ctcTokenIds: ids
                )
            }
            guard !tokenized.isEmpty else { return }

            vocabContext = CustomVocabularyContext(terms: tokenized)
            spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        } catch {
            // Boosting is best-effort: plain transcription keeps working.
            vocabContext = nil
            spotter = nil
        }
    }

    /// Swaps transcript words for vocabulary terms only when BOTH hold: the
    /// spotter heard the term at that moment, and the written word textually
    /// resembles the term or one of its learned mishearings. "ok" can never
    /// pass for "Jachin" no matter what the audio says.
    private func boost(_ text: String, samples: [Float], timings: [TokenTiming]?) async -> String {
        guard let spotter, let vocabContext,
              let timings, !timings.isEmpty else { return text }
        guard let spotResult = try? await spotter.spotKeywordsWithLogProbs(
            audioSamples: samples, customVocabulary: vocabContext, minScore: nil
        ), !spotResult.detections.isEmpty else { return text }

        // Word-level timings from token timings (SentencePiece "▁" marks starts).
        var words: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        for timing in timings {
            let isWordStart = timing.token.hasPrefix("▁") || timing.token.hasPrefix(" ") || words.isEmpty
            let piece = timing.token
                .replacingOccurrences(of: "▁", with: "")
                .trimmingCharacters(in: .whitespaces)
            if isWordStart {
                words.append((piece, timing.startTime, timing.endTime))
            } else {
                words[words.count - 1].text += piece
                words[words.count - 1].end = timing.endTime
            }
        }
        words.removeAll { $0.text.isEmpty }
        guard !words.isEmpty else { return text }

        var replaced = words.map { $0.text }
        var replacements = 0
        let slack: TimeInterval = 0.35

        for detection in spotResult.detections {
            let term = detection.term
            let targets = [term.text] + (term.aliases ?? [])

            // Words overlapping the detection window, with a little slack for
            // timing skew between the two models.
            let windowStart = detection.startTime - slack
            let windowEnd = detection.endTime + slack
            let candidates = words.indices.filter { words[$0].end >= windowStart && words[$0].start <= windowEnd }
            guard !candidates.isEmpty else { continue }

            // Best textual match among runs of 1 to 3 consecutive words.
            var best: (score: Double, range: ClosedRange<Int>)?
            for start in candidates {
                for length in 1...3 {
                    let end = start + length - 1
                    guard end < words.count, candidates.contains(end) else { break }
                    let phrase = replaced[start...end].joined(separator: " ")
                    let score = targets.map { Self.similarity(phrase, $0) }.max() ?? 0
                    if score > (best?.score ?? 0) {
                        best = (score, start...end)
                    }
                }
            }
            guard let best, best.score >= 0.6 else { continue }

            let current = replaced[best.range].joined(separator: " ")
            guard current.compare(term.text, options: .caseInsensitive) != .orderedSame else { continue }

            // Preserve punctuation clinging to the replaced run.
            let leading = String(current.prefix(while: { $0.isPunctuation }))
            let trailing = String(current.reversed().prefix(while: { $0.isPunctuation }).reversed())
            for index in best.range {
                replaced[index] = ""
            }
            replaced[best.range.lowerBound] = leading + term.text + trailing
            replacements += 1
        }

        guard replacements > 0, replacements <= max(2, words.count / 4) else { return text }
        let result = replaced.filter { !$0.isEmpty }.joined(separator: " ")
        return result.isEmpty ? text : result
    }

    /// Normalized Levenshtein similarity, case- and punctuation-insensitive.
    private static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace })
        let y = Array(b.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace })
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var dp = Array(0...y.count)
        for i in 1...x.count {
            var previous = dp[0]
            dp[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                let value = min(dp[j] + 1, dp[j - 1] + 1, previous + cost)
                previous = dp[j]
                dp[j] = value
            }
        }
        return 1.0 - Double(dp[y.count]) / Double(max(x.count, y.count))
    }

    /// True when the given model needs no download: bundled inside the app
    /// (default model only) or already in the FluidAudio cache.
    nonisolated static func availableLocally(_ model: SpeechModel) -> Bool {
        if model == .standard, let bundled = bundledModelURL,
            FileManager.default.fileExists(atPath: bundled.path) {
            return true
        }
        return model.isInstalled
    }

    /// Kept for the fresh-install welcome flow: is the default model present.
    nonisolated static var modelsAvailableLocally: Bool {
        availableLocally(.standard)
    }

    private nonisolated static var bundledModelURL: URL? {
        // Matches Repo.parakeetV3.folderName: FluidAudio drops the -coreml
        // suffix from repo names for its on-disk folders.
        Bundle.main.resourceURL?
            .appendingPathComponent("FluidAudioModels", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    /// Loads the requested model, replacing whatever was loaded before.
    func prepare(model: SpeechModel = .standard, progressHandler: DownloadUtils.ProgressHandler? = nil) async throws {
        guard loadedModel != model else { return }

        switch model {
        case .parakeetV3, .parakeetV2:
            let models = try await Self.loadParakeet(version: model.asrVersion!, progressHandler: progressHandler)
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            parakeet = asr
            cohere = nil
        case .cohere:
            let dir = model.directory
            let loaded = try await CoherePipeline.loadModels(encoderDir: dir, decoderDir: dir, vocabDir: dir)
            cohere = (CoherePipeline(), loaded)
            parakeet = nil
        }
        loadedModel = model
    }

    /// Parakeet loading prefers a copy bundled inside the app (Canva
    /// distribution: no download on first run), then the cache, then the
    /// HuggingFace download path.
    private static func loadParakeet(
        version: AsrModelVersion, progressHandler: DownloadUtils.ProgressHandler?
    ) async throws -> AsrModels {
        if version == .v3, let bundled = bundledModelURL,
            FileManager.default.fileExists(atPath: bundled.path) {
            do {
                return try await AsrModels.load(from: bundled, version: version, progressHandler: progressHandler)
            } catch {
                // Incomplete or stale bundle: fall through to the normal path.
            }
        }
        return try await AsrModels.downloadAndLoad(version: version, progressHandler: progressHandler)
    }

    /// Expects 16 kHz mono Float32 samples.
    func transcribe(_ samples: [Float]) async throws -> String {
        if let parakeet {
            // Fresh decoder state per utterance; every hotkey press is an
            // independent dictation.
            var decoderState = try TdtDecoderState()
            let result = try await parakeet.transcribe(samples, decoderState: &decoderState)
            return await boost(result.text, samples: samples, timings: result.tokenTimings)
        }
        if let cohere {
            let result = try await cohere.pipeline.transcribeLong(audio: samples, models: cohere.models)
            return result.text
        }
        throw GojiError("Model isn't loaded yet.")
    }
}
