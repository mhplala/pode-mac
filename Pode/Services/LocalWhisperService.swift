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
    // WhisperKit's HF repo uses a versioned variant name for turbo —
    // the bare "openai_whisper-large-v3-turbo" does NOT exist there.
    case highest = "openai_whisper-large-v3-v20240930_turbo"

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
    /// Rough wall-clock minutes to transcribe one hour of audio on an
    /// M1/M2/M3 Mac with WhisperKit's ANE acceleration + parallel VAD
    /// workers. Real numbers vary by chip, but the ordering is correct:
    /// `highest` is **faster** than `balanced` because large-v3-turbo's
    /// decoder is 4 layers vs medium's 24 — it's a speed-tuned variant
    /// of large, not a heavier model.
    var speedLabel: String {
        switch self {
        case .fast:     return "~3 min/h"
        case .balanced: return "~6 min/h"
        case .highest:  return "~4 min/h"
        }
    }
    var qualityLabel: String {
        switch self {
        case .fast:     return "basic"
        case .balanced: return "great"
        case .highest:  return "best"
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

/// One transcript line emitted live during transcription (before the
/// pipeline fully completes).
///
/// Time model — important and easy to get wrong:
/// - `seek` is the **chunk's** start sample position in the source
///   audio. WhisperKit's VAD pipeline cuts audio into chunks; every
///   segment that comes out of a single chunk shares the same `seek`
///   value. **`seek` is NOT a unique per-segment key.**
/// - `start` is the segment's start time **relative to the chunk** (in
///   seconds). Different segments within a chunk have different `start`s.
/// - `t` is the segment's absolute start time in the source audio,
///   precomputed here as `Double(seek)/sampleRate + start` so callers
///   don't have to remember the math.
///
/// Dedup-safe key is the composite `(seek, startMillis)`. Using `seek`
/// alone collapses every chunk down to a single segment — which is
/// exactly the bug that made early streaming look broken.
struct StreamingSegment: Sendable, Hashable {
    let seek: Int
    let start: Double
    let t: Double
    let text: String
}

/// How many parallel decoder workers to run inside WhisperKit's VAD
/// pipeline. More workers = faster transcription, more RAM. We size it
/// against the user's machine so a 4-core MacBook Air doesn't try to
/// pretend it's an M3 Max.
///
/// Apple Silicon cores are a mix of performance + efficiency cores, all
/// reported as "active processors". Half the active count, clamped to
/// [2, 8], gives a sane default: M1 (8) → 4, M3 Pro (11) → 5, M3 Max
/// (14) → 7. The 8 ceiling protects RAM on the largest models.
private func recommendedWorkerCount() -> Int {
    let cores = ProcessInfo.processInfo.activeProcessorCount
    return max(2, min(cores / 2, 8))
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

    /// CoreML graph directories WhisperKit needs at runtime. A model
    /// folder missing any of these is an incomplete download and must
    /// be re-fetched — WhisperKit will otherwise blow up partway through
    /// pipeline init looking for the missing piece.
    private static let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
        "MelSpectrogram.mlmodelc"
    ]

    /// Returns the on-disk folder for the variant if it's already downloaded.
    /// WhisperKit lays out models under `<cache>/<repo>/<variant>/`.
    static func cachedModelFolder(_ model: LocalWhisperModel) -> URL? {
        guard let dir = try? modelsDirectory() else { return nil }
        guard let enumerator = FileManager.default.enumerator(at: dir,
                                                              includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == model.rawValue,
               isFolderComplete(url) {
                return url
            }
        }
        return nil
    }

    /// True iff every required CoreML model bundle exists under `folder`.
    /// Used both for cache lookup and for the post-download integrity check.
    private static func isFolderComplete(_ folder: URL) -> Bool {
        var isDir: ObjCBool = false
        for name in requiredCoreMLBundles {
            let path = folder.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                return false
            }
        }
        return true
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
    ///
    /// Self-heals incomplete caches: if pipeline init fails because the
    /// on-disk folder is missing required `.mlmodelc` bundles (interrupted
    /// download, killed mid-write, etc.), it wipes the folder and tries
    /// once more from scratch instead of leaving the user permanently
    /// stuck behind a broken cache.
    func prepare(
        model: LocalWhisperModel,
        onStage: @MainActor @Sendable @escaping (LocalWhisperStage) -> Void
    ) async throws {
        if let loadedModel, loadedModel == model, pipeline != nil { return }

        await onStage(.checking)
        try Self.checkDiskSpace(for: model)

        let modelsDir = try Self.modelsDirectory()
        var triedRedownload = false

        while true {
            // Fetch (or re-fetch) the model folder.
            let modelFolder: URL = try await ensureDownloaded(
                model: model, modelsDir: modelsDir, onStage: onStage
            )

            await onStage(.loadingModel)
            do {
                // WhisperKit needs the *folder path* to load model files.
                // `download: false` tells it not to re-download — we
                // already have the bits.
                let config = WhisperKitConfig(
                    model: model.rawValue,
                    downloadBase: modelsDir,
                    modelFolder: modelFolder.path,
                    verbose: false,
                    logLevel: .error,
                    load: true,
                    download: false
                )
                self.pipeline = try await WhisperKit(config)
                self.loadedModel = model
                return
            } catch {
                // Treat a load failure as cache corruption — but only
                // give it one self-heal attempt to avoid an infinite
                // download/fail loop on genuinely broken environments.
                if triedRedownload {
                    throw LocalWhisperError.transcribeFailed(
                        "Pipeline init: \(error.localizedDescription)"
                    )
                }
                triedRedownload = true
                // Wipe the partial cache so `ensureDownloaded` re-fetches.
                try? FileManager.default.removeItem(at: modelFolder)
            }
        }
    }

    /// Guarantee the model folder exists on disk and contains all required
    /// CoreML bundles. Downloads (or re-downloads) on miss; verifies the
    /// integrity of the result so the caller can trust the path.
    private func ensureDownloaded(
        model: LocalWhisperModel,
        modelsDir: URL,
        onStage: @MainActor @Sendable @escaping (LocalWhisperStage) -> Void
    ) async throws -> URL {
        if let cached = Self.cachedModelFolder(model) {
            return cached
        }
        await onStage(.downloadingModel(progress: 0))
        let folder: URL
        do {
            folder = try await WhisperKit.download(
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
        // Defend against the download "succeeding" but actually missing
        // a required bundle (network flakiness, partial writes).
        guard Self.isFolderComplete(folder) else {
            try? FileManager.default.removeItem(at: folder)
            throw LocalWhisperError.modelDownloadFailed(
                "Download finished but is missing required model files. Try again."
            )
        }
        return folder
    }

    /// Runs the audio file through the pipeline.
    ///
    /// `onStage` fires for each pipeline phase (download / load / transcribe).
    /// While transcribing it carries a 0..1 progress fraction taken from the
    /// running maximum segment end timestamp seen across parallel workers.
    ///
    /// `onSegment` (new) emits batches of `StreamingSegment` as the VAD
    /// pipeline discovers them. `seg.seek` is already absolute (in source-
    /// audio sample counts) by the time WhisperKit fires the callback, so
    /// `seek / sampleRate` is a trustworthy timestamp for live display.
    /// `seg.start` / `seg.end` are chunk-local and shouldn't be used here.
    /// Callers should dedupe by `seek` and treat the streamed lines as
    /// progressive — the post-call `WhisperResult.lines` is the same data,
    /// passed through `updateSeekOffsetsForResults` for safety.
    func transcribe(
        audioFileURL: URL,
        model: LocalWhisperModel,
        language: String? = nil,
        audioDuration: Double,
        onStage: @MainActor @Sendable @escaping (LocalWhisperStage) -> Void,
        onSegment: (@MainActor @Sendable ([StreamingSegment]) -> Void)? = nil
    ) async throws -> WhisperResult {
        try await prepare(model: model, onStage: onStage)
        guard let pipe = pipeline else {
            throw LocalWhisperError.transcribeFailed("Pipeline not loaded")
        }

        // Bridge the silent gap between "model loaded" and the first real
        // `.transcribing` callback from WhisperKit (audio decode + VAD
        // chunking can run for many seconds with no events). Without this,
        // the UI sticks on "Loading model…" and looks hung.
        await onStage(.transcribing(progress: 0))

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

            // Stream segments to the UI. `seg.seek` gives the **chunk's**
            // absolute start (in samples); `seg.start` is chunk-local
            // seconds. The segment's absolute time is the sum.
            //
            // Earlier versions stored just `seg.seek/sampleRate` as the
            // line time, which made every segment in a single chunk
            // share an identical t and visually pile up on one point of
            // the timeline. The dedup key was also `seg.seek` alone —
            // so 7 out of 8 segments per chunk got dropped at the
            // dedup stage. Both bugs are fixed by carrying `seg.start`
            // through the StreamingSegment.
            if let onSegment {
                let lines: [StreamingSegment] = segments.compactMap { seg in
                    let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    let chunkStartSec = Double(seg.seek) / sampleRate
                    let segStart = Double(seg.start)
                    return StreamingSegment(
                        seek: seg.seek,
                        start: segStart,
                        t: chunkStartSec + segStart,
                        text: trimmed
                    )
                }
                if !lines.isEmpty {
                    Task { @MainActor in onSegment(lines) }
                }
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
        // - `concurrentWorkerCount` set from machine: more workers ⇒ faster
        //   on long episodes, at the cost of RAM (each holds decoder state).
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            concurrentWorkerCount: recommendedWorkerCount(),
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
