import FluidAudio

/// Wraps FluidAudio's Parakeet v3 pipeline. Actor keeps the heavy work off the main thread.
/// Models download once from HuggingFace into the user cache, then load from disk.
actor Transcriber {
    private var manager: AsrManager?

    func prepare() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
    }

    /// Expects 16 kHz mono Float32 samples.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else {
            throw GojiError("Model isn't loaded yet.")
        }
        let result = try await manager.transcribe(samples)
        return result.text
    }
}
