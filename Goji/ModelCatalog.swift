import AppKit
import FluidAudio

/// The speech models Goji can run. Parakeet v3 is the default and what fresh
/// installs download; the others are opt-in from Settings > Models.
enum SpeechModel: String, CaseIterable, Identifiable {
    case parakeetV3
    case parakeetV2
    case cohere

    var id: String { rawValue }
    static let standard: SpeechModel = .parakeetV3

    var displayName: String {
        switch self {
        case .parakeetV3: return "Parakeet v3"
        case .parakeetV2: return "Parakeet v2"
        case .cohere: return "Cohere Transcribe"
        }
    }

    var detail: String {
        switch self {
        case .parakeetV3: return "Fast multilingual dictation on the Neural Engine. The default, and the best pick for most people."
        case .parakeetV2: return "English-only sibling of v3. Try it if your dictation is always English."
        case .cohere: return "Larger encoder-decoder model, strongest accuracy. Slower, and Goji runs it in English for now."
        }
    }

    var languagesLabel: String {
        switch self {
        case .parakeetV3: return "25 languages"
        case .parakeetV2: return "English"
        case .cohere: return "English (14 soon)"
        }
    }

    var approxDownload: String {
        switch self {
        case .parakeetV3, .parakeetV2: return "~600 MB"
        case .cohere: return "~2 GB"
        }
    }

    /// FluidAudio's Parakeet version for the TDT engine, nil for Cohere.
    var asrVersion: AsrModelVersion? {
        switch self {
        case .parakeetV3: return .v3
        case .parakeetV2: return .v2
        case .cohere: return nil
        }
    }

    var repo: Repo {
        switch self {
        case .parakeetV3: return .parakeetV3
        case .parakeetV2: return .parakeetV2
        case .cohere: return .cohereTranscribeCoreml
        }
    }

    /// Root of FluidAudio's model cache (~/Library/Application Support/FluidAudio/Models).
    static var modelsRoot: URL {
        AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
    }

    /// Where the model's files live in FluidAudio's cache.
    var directory: URL {
        Self.modelsRoot.appendingPathComponent(repo.folderName, isDirectory: true)
    }

    var isInstalled: Bool {
        switch self {
        case .parakeetV3, .parakeetV2:
            return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: asrVersion!), version: asrVersion!)
        case .cohere:
            let fm = FileManager.default
            return fm.fileExists(atPath: directory.appendingPathComponent(ModelNames.CohereTranscribe.encoderCompiledFile).path)
                && fm.fileExists(atPath: directory.appendingPathComponent(ModelNames.CohereTranscribe.decoderCacheExternalV2CompiledFile).path)
                && fm.fileExists(atPath: directory.appendingPathComponent(ModelNames.CohereTranscribe.vocab).path)
        }
    }
}

/// Download/remove/measure state for the Models pane. Downloads go through
/// FluidAudio's HuggingFace path; the default model's first-run download still
/// uses the faster GitHub mirror via ModelFetcher.
@MainActor
final class ModelLibrary: ObservableObject {
    static let shared = ModelLibrary()

    /// Fraction + label per model currently downloading.
    @Published private(set) var downloading: [SpeechModel: (fraction: Double, label: String)] = [:]
    @Published private(set) var lastError: String?
    /// Bumped whenever install state changes so views re-read isInstalled.
    @Published private(set) var revision = 0

    func download(_ model: SpeechModel) {
        guard downloading[model] == nil else { return }
        lastError = nil
        downloading[model] = (0, "Starting…")
        Task {
            do {
                try await DownloadUtils.downloadRepo(model.repo, to: SpeechModel.modelsRoot) { progress in
                    let label: String
                    switch progress.phase {
                    case .listing:
                        label = "Contacting server…"
                    case .downloading(let done, let total):
                        label = "File \(min(done + 1, total)) of \(total)"
                    case .compiling:
                        label = "Optimizing…"
                    }
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        self?.downloading[model] = (fraction, label)
                    }
                }
            } catch {
                lastError = "\(model.displayName): \(error.localizedDescription)"
            }
            downloading[model] = nil
            revision += 1
        }
    }

    /// Deletes the model's files. The currently selected model can't be
    /// removed (the UI disables it), so no live reload is needed here.
    func remove(_ model: SpeechModel) {
        try? FileManager.default.removeItem(at: model.directory)
        revision += 1
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([SpeechModel.modelsRoot])
    }

    /// Human-readable size of everything under the models folder.
    func totalSizeOnDisk() -> String {
        let root = SpeechModel.modelsRoot
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return "0 MB" }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
