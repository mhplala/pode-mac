import Foundation
import WhisperKit

/// Local on-device transcription via WhisperKit.
///
/// Mirrors `WhisperService` (cloud) but adds:
/// - explicit per-stage progress (model download, transcription)
/// - streaming segment callback so the UI can render lines as they're decoded
///
/// Models are cached under `~/Library/Application Support/Pode/WhisperKit/`.
/// First call to a fresh model downloads ~244 MB – 1.5 GB; subsequent calls
/// reuse the on-disk copy and start instantly.
enum LocalWhisperModel: String, CaseIterable, Codable {
    case fast = "openai_whisper-small"
    case balanced = "openai_whisper-medium"
    case highest = "openai_whisper-large-v3-turbo"

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .highest: return "Highest"
        }
    }
    var sizeLabel: String {
        switch self {
        case .fast: return "~244 MB"
        case .balanced: return "~769 MB"
        case .highest: return "~1.5 GB"
        }
    }
    var speedLabel: String {
        switch self {
        case .fast: return "~5 min/h"
        case .balanced: return "~12 min/h"
        case .highest: return "~25 min/h"
        }
    }
    var qualityLabel: String {
        switch self {
        case .fast: return "basic"
        case .balanced: return "great"
        case .highest: return "best"
        }
    }
    /// Approximate on-disk size in bytes — used for the pre-flight disk check.
    var approximateBytes: Int64 {
        switch self {
        case .fast: return 244 * 1_048_576
        case .balanced: return 769 * 1_048_576
        case .highest: return 1_536 * 1_048_576
        }
    }
}

enum LocalWhisperError: Error, LocalizedError {
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case modelDownloadFailed(String)
    case transcribeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let need, let have):
            return "Need \(Fmt.bytes(need)) free; only \(Fmt.bytes(have)) available."
        case .modelDownloadFailed(let m): return "Model download failed: \(m)"
        case .transcribeFailed(let m): return "Transcribe failed: \(m)"
        case .cancelled: return "Transcription cancelled."
        }
    }
}

/// State emitted to the UI as the work progresses.
enum LocalWhisperStage: Sendable {
    case checking
    case downloadingModel(progress: Double)   // 0..1
    case loadingModel
    case transcribing(progress: Double)       // 0..1, derived from segment timestamps / audio duration
}

/// Thread-safe monotonic max for progress tracking under parallel callbacks.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value: Double = 0
    func bumpIfLarger(_ new: Double) {
        lock.lock(); defer { lock.unlock() }
        if new > value { value = new }
    }
}

actor LocalWhisperService {
    static let shared = LocalWhisperService()

    private var pipeline: WhisperKit?
    private var loadedModel: LocalWhisperModel?

    /// Returns the application support directory we cache WhisperKit models in.
    private static func modelsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Pode/WhisperKit", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the on-disk folder for the variant if it's already downloaded.
    /// WhisperKit lays out models under `<cache>/<repo>/<variant>/`.
    static func cachedModelFolder(_ model: LocalWhisperModel) -> URL? {
        guard let dir = try? modelsDirectory() else { return nil }
        guard let enumerator = FileManager.default.enumerator(at: dir,
                                                              includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == model.rawValue {
                // Sanity check: must contain at least one mlmodelc / model file.
                if let kids = try? FileManager.default.contentsOfDirectory(atPath: url.path),
                   kids.contains(where: { $0.hasSuffix(".mlmodelc") || $0.hasSuffix(".bin") || $0.hasSuffix(".json") }) {
                    return url
                }
            }
        }
        return nil
    }

    /// Whether the chosen model has already been downloaded.
    static func isModelCached(_ model: LocalWhisperModel) -> Bool {
        cachedModelFolder(model) != nil
    }

    /// Pre-flight disk space check. Throws `insufficientDiskSpace` if there
    /// isn't `model size + 500 MB` head-room.
    static func checkDiskSpace(for model: LocalWhisperModel) throws {
        if isModelCached(model) { return }
        let need = model.approximateBytes + 500 * 1_048_576
        let dir = try modelsDirectory()
        let values = try dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        if available < need {
            throw LocalWhisperError.insufficientDiskSpace(needed: need, available: available)
        }
    }

    /// Downloads the model if needed, then loads the pipeline.
    /// `onStage` fires on the **main actor** so the UI can update directly.
    func prepare(
        model: LocalWhisperModel,
        onStage: @MainActor @Sendable @escaping (LocalWhisperStage) -> Void
    ) async throws {
        if let loadedModel, loadedModel == model, pipeline != nil { return }

        await onStage(.checking)
        try Self.checkDiskSpace(for: model)

        let modelsDir = try Self.modelsDirectory()
        var modelFolder: URL? = Self.cachedModelFolder(model)

        if modelFolder == nil {
            await onStage(.downloadingModel(progress: 0))
            do {
                modelFolder = try await WhisperKit.download(
                    variant: model.rawValue,
                    downloadBase: modelsDir,
                    progressCallback: { progress in
                        let f = progress.fractionCompleted
                        Task { @MainActor in onStage(.downloadingModel(progress: f)) }
                    }
                )
            } catch {
                throw LocalWhisperError.modelDownloadFailed(error.localizedDescription)
            }
        }

        await onStage(.loadingModel)
        do {
            // WhisperKit needs the *folder path* to load model files. Without
            // `modelFolder`, init throws "folder not set". `download: false`
            // tells it not to re-download — we already have the bits.
            let config = WhisperKitConfig(
                model: model.rawValue,
                downloadBase: modelsDir,
                modelFolder: modelFolder?.path,
                verbose: false,
                logLevel: .error,
                load: true,
                download: false
            )
            self.pipeline = try await WhisperKit(config)
            self.loadedModel = model
        } catch {
            throw LocalWhisperError.transcribeFailed("Pipeline init: \(error.localizedDescription)")
        }
    }

    /// Runs the audio file through the pipeline.
    ///
    /// `onStage` fires for each pipeline phase (download / load / transcribe);
    /// while transcribing it carries a 0..1 progress fraction taken from the
    /// running maximum segment end timestamp seen across parallel workers.
    /// `onSegment` is intentionally NOT used to populate the UI live — VAD
    /// chunking emits chunk-local timestamps that aren't absolute until
    /// WhisperKit's `updateSeekOffsetsForResults` runs at the end. The caller
    /// should rely on the returned `WhisperResult.lines` for accurate `t`.
    func transcribe(
        audioFileURL: URL,
        model: LocalWhisperModel,
        language: String? = nil,
        audioDuration: Double,
        onStage: @MainActor @Sendable @escaping (LocalWhisperStage) -> Void
    ) async throws -> WhisperResult {
        try await prepare(model: model, onStage: onStage)
        guard let pipe = pipeline else {
            throw LocalWhisperError.transcribeFailed("Pipeline not loaded")
        }

        // Progress tracking. With VAD chunking + parallel workers, segments
        // arrive out of order with chunk-local start/end timestamps. We use
        // `seg.seek` (which IS adjusted to absolute by WhisperKit before being
        // passed to us) divided by sampleRate as a monotonic indicator. Take
        // the running max so progress only ever moves forward.
        let progressBox = ProgressBox()
        let sampleRate = Double(WhisperKit.sampleRate)
        pipe.segmentDiscoveryCallback = { segments in
            if audioDuration > 0, let maxSeek = segments.map(\.seek).max() {
                let absSec = Double(maxSeek) / sampleRate
                progressBox.bumpIfLarger(absSec)
                let frac = max(0, min(1, progressBox.value / audioDuration))
                Task { @MainActor in onStage(.transcribing(progress: frac)) }
            }
        }
        pipe.transcriptionStateCallback = { state in
            if state == .transcribing {
                Task { @MainActor in onStage(.transcribing(progress: 0)) }
            }
        }

        // - `language == nil` → run WhisperKit's dedicated language-detection
        //   step on the first audio chunk; with `usePrefillPrompt: true` the
        //   detected language is fed back into the decoder's prefix tokens
        //   so the model can't silently translate to English.
        // - `language == "zh"` etc. → pin the language from the start.
        // `skipSpecialTokens: true` strips `<|zh|>`, `<|transcribe|>` etc.
        // from the line text.
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )

        do {
            let results: [TranscriptionResult] = try await pipe.transcribe(
                audioPath: audioFileURL.path,
                decodeOptions: options
            )
            // Flatten segments across windows (chunking can produce multiple results).
            var lines: [WhisperLine] = []
            var fullText = ""
            for r in results {
                fullText += r.text
                for seg in r.segments {
                    lines.append(WhisperLine(
                        t: floor(Double(seg.start)),
                        text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        speaker: nil
                    ))
                }
            }
            // Sort by timestamp + de-dupe the rare overlap a chunk boundary can
            // produce.
            lines.sort { $0.t < $1.t }
            var deduped: [WhisperLine] = []
            for line in lines {
                if deduped.last?.text == line.text { continue }
                deduped.append(line)
            }
            return WhisperResult(
                lines: deduped,
                language: results.first?.language,
                text: fullText
            )
        } catch is CancellationError {
            throw LocalWhisperError.cancelled
        } catch {
            throw LocalWhisperError.transcribeFailed(error.localizedDescription)
        }
    }
}
