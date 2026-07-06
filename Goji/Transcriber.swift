import FluidAudio
import Foundation

/// Wraps FluidAudio's speech engines. Actor keeps the heavy work off the main
/// thread. Parakeet v2/v3 run through AsrManager; Cohere Transcribe runs
/// through CoherePipeline. Which model loads comes from SettingsStore.
actor Transcriber {
    private var parakeet: AsrManager?
    private var cohere: (pipeline: CoherePipeline, models: CoherePipeline.LoadedModels)?
    private var loadedModel: SpeechModel?

    // Vocabulary boosting: CTC word spotting + constrained rescoring nudges
    // the transcript toward the user's Names & phrases at the acoustic level.
    // Parakeet only; requires the small CTC helper model.
    private var ctcModels: CtcModels?
    private var spotter: CtcKeywordSpotter?
    private var rescorer: VocabularyRescorer?
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
        guard usable != loadedVocabWords || (wantsBoost && rescorer == nil) else { return }
        loadedVocabWords = usable
        vocabContext = nil
        spotter = nil
        rescorer = nil
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

            // Precision over recall: the library's defaults (similarity 0.50,
            // heavy bias) happily turn everyday words into vocabulary terms.
            // A missed boost is mildly annoying; a false one is corrosive.
            let context = CustomVocabularyContext(terms: tokenized, minSimilarity: 0.72)
            let spot = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
            rescorer = try await VocabularyRescorer.create(
                spotter: spot,
                vocabulary: context,
                ctcModelDirectory: cacheDir
            )
            vocabContext = context
            spotter = spot
        } catch {
            // Boosting is best-effort: plain transcription keeps working.
            vocabContext = nil
            spotter = nil
            rescorer = nil
        }
    }

    /// Rescores a Parakeet transcript toward vocabulary terms when the
    /// acoustics support it. Returns the original text when boosting is off
    /// or nothing beat the threshold.
    private func boost(_ text: String, samples: [Float], timings: [TokenTiming]?) async -> String {
        guard let spotter, let rescorer, let vocabContext,
              let timings, !timings.isEmpty else { return text }
        guard let spotResult = try? await spotter.spotKeywordsWithLogProbs(
            audioSamples: samples, customVocabulary: vocabContext, minScore: nil
        ), !spotResult.logProbs.isEmpty else { return text }

        // Conservative dials: default bias weight (not the 4.5 the size-based
        // config suggests) and a high similarity bar.
        let output = rescorer.ctcTokenRescore(
            transcript: text,
            tokenTimings: timings,
            logProbs: spotResult.logProbs,
            frameDuration: spotResult.frameDuration,
            cbw: ContextBiasingConstants.defaultCbw,
            marginSeconds: 0.5,
            minSimilarity: max(0.72, vocabContext.minSimilarity)
        )
        guard output.wasModified else { return text }

        // Sanity guard: if the rescorer wants to rewrite a big chunk of the
        // sentence into vocabulary terms, it has gone rogue. Keep the original.
        let wordCount = max(text.split(whereSeparator: \.isWhitespace).count, 1)
        let replacedCount = output.replacements.filter { $0.shouldReplace }.count
        guard replacedCount <= max(2, wordCount / 5) else { return text }

        return output.text
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
