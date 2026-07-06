import FluidAudio
import Foundation

/// Wraps FluidAudio's speech engines. Actor keeps the heavy work off the main
/// thread. Parakeet v2/v3 run through AsrManager; Cohere Transcribe runs
/// through CoherePipeline. Which model loads comes from SettingsStore.
actor Transcriber {
    private var parakeet: AsrManager?
    private var cohere: (pipeline: CoherePipeline, models: CoherePipeline.LoadedModels)?
    private var loadedModel: SpeechModel?

    // NOTE: A decoder-level "Enhanced recognition" boost (CTC word spotting +
    // rescoring) and a fix-and-learn loop were built and removed during
    // v1.0.15 development; see the gotcha in CLAUDE.md. Names & phrases
    // corrections run through the AI cleanup prompt only. Revisit learning
    // only with an offline test harness of recorded audio (git history).

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
            return result.text
        }
        if let cohere {
            let result = try await cohere.pipeline.transcribeLong(audio: samples, models: cohere.models)
            return result.text
        }
        throw GojiError("Model isn't loaded yet.")
    }
}
