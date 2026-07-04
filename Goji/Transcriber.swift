import FluidAudio
import Foundation

/// Wraps FluidAudio's Parakeet v3 pipeline. Actor keeps the heavy work off the main thread.
/// Models load from a copy bundled into the app if present, otherwise download once
/// from HuggingFace into the user cache.
actor Transcriber {
    private var manager: AsrManager?

    func prepare() async throws {
        guard manager == nil else { return }
        let models = try await Self.loadModels()
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
    }

    /// Prefers a model bundled inside the app (Canva distribution: no download on
    /// first run), falls back to the download-and-cache path.
    private static func loadModels() async throws -> AsrModels {
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("FluidAudioModels", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true),
            FileManager.default.fileExists(atPath: bundled.path) {
            do {
                return try await AsrModels.load(from: bundled, version: .v3)
            } catch {
                // Incomplete or stale bundle: fall through to the normal path.
            }
        }
        return try await AsrModels.downloadAndLoad(version: .v3)
    }

    /// Expects 16 kHz mono Float32 samples.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else {
            throw GojiError("Model isn't loaded yet.")
        }
        // Fresh decoder state per utterance; every hotkey press is an independent dictation.
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text
    }
}
