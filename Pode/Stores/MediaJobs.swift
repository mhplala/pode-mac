import Foundation
import SwiftUI
import SwiftData

// MARK: - DownloadStore
//
// The audio-download side of the pipeline. Holds one `DownloadJob` per
// `Episode.id` for the lifetime of the download (and a brief moment after
// failure so the error is observable). Lives at the app level — the same
// instance survives view tear-down, so users can navigate away mid-download
// and the work keeps running with progress preserved.
//
// Cooperates with `TranscribeStore`: when a transcribe pipeline starts, it
// calls `downloadIfNeeded(...)` which either reuses an in-flight download
// or starts one — never races two downloads of the same episode.

@MainActor
@Observable
final class DownloadStore {
    /// Active and recently-failed jobs keyed by `Episode.id`. Successful
    /// jobs are removed once the destination has been written to SwiftData
    /// (the `episode.downloaded == true` flag becomes the source of truth
    /// from that point on).
    var jobs: [String: DownloadJob] = [:]

    /// Per-episode awaiters waiting on the *current* in-flight download.
    /// `downloadIfNeeded` puts a continuation here; `_finish` resumes them.
    private var awaiters: [String: [CheckedContinuation<URL, Error>]] = [:]

    func job(for id: String) -> DownloadJob? { jobs[id] }

    /// Kick off a manual download. No-op if the episode is already
    /// downloading (the existing job's progress is what callers will see).
    func startDownload(episode: Episode, ctx: ModelContext) {
        guard jobs[episode.id]?.task == nil else { return }  // already running
        _start(episode: episode, ctx: ctx)
    }

    /// Cancel the in-flight download for an episode. Awaiters get a
    /// `CancellationError`. Used when the user taps "Cancel".
    func cancel(episodeID: String) {
        jobs[episodeID]?.task?.cancel()
        let pending = awaiters[episodeID] ?? []
        awaiters[episodeID] = nil
        jobs.removeValue(forKey: episodeID)
        for cont in pending { cont.resume(throwing: CancellationError()) }
    }

    /// Delete the on-disk file and clear download flags. Used by the
    /// "Remove download" alert.
    func removeDownload(episode: Episode, ctx: ModelContext) {
        if let path = episode.localFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        episode.localFilePath = nil
        episode.downloaded = false
        episode.downloadedAt = nil
        try? ctx.save()
    }

    /// Used by `TranscribeStore`: get the local audio URL, downloading if
    /// needed. If a download is already in flight for this episode, awaits
    /// its completion instead of starting a duplicate.
    func downloadIfNeeded(episode: Episode, ctx: ModelContext) async throws -> URL {
        if episode.downloaded, let path = episode.localFilePath,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Start a download job if there isn't one already.
        if jobs[episode.id]?.task == nil {
            _start(episode: episode, ctx: ctx)
        }
        // Park until the job resolves.
        let id = episode.id
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            awaiters[id, default: []].append(cont)
        }
    }

    // MARK: Private

    private func _start(episode: Episode, ctx: ModelContext) {
        guard let url = URL(string: episode.audioUrl) else {
            jobs[episode.id] = DownloadJob(error: "Bad audio URL")
            _failAwaiters(for: episode.id, with: AudioJobError.badURL)
            return
        }
        let id = episode.id
        var job = DownloadJob(startedAt: .now)
        let task = Task { @MainActor [weak self] in
            do {
                let dest = try await AudioDownloader.download(from: url) { loaded, total in
                    Task { @MainActor [weak self] in
                        guard var j = self?.jobs[id], j.task != nil else { return }
                        j.loaded = loaded
                        j.total = total
                        self?.jobs[id] = j
                    }
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                episode.localFilePath = dest.path
                episode.downloaded = true
                episode.downloadedAt = .now
                if let size = attrs?[.size] as? NSNumber {
                    episode.audioSize = size.int64Value
                }
                try? ctx.save()
                self?._finish(id: id, success: dest)
            } catch {
                let cancelled = (error as? CancellationError) != nil
                    || (error as NSError).code == NSURLErrorCancelled
                if cancelled {
                    self?._finish(id: id, error: AudioJobError.cancelled)
                } else {
                    let msg = Self.humanize(error)
                    self?._failJob(id: id, message: msg)
                    self?._failAwaiters(for: id, with: error)
                }
            }
        }
        job.task = task
        jobs[id] = job
    }

    private func _finish(id: String, success url: URL) {
        // Success — clear job entry and resume awaiters.
        jobs.removeValue(forKey: id)
        let pending = awaiters[id] ?? []
        awaiters[id] = nil
        for cont in pending { cont.resume(returning: url) }
    }

    private func _finish(id: String, error: Error) {
        // Cancellation path: no error UI, just resume awaiters with throw.
        jobs.removeValue(forKey: id)
        let pending = awaiters[id] ?? []
        awaiters[id] = nil
        for cont in pending { cont.resume(throwing: error) }
    }

    private func _failJob(id: String, message: String) {
        // Keep the job around with an error so the view can render a retry
        // button. The job has no live task at this point.
        var j = jobs[id] ?? DownloadJob()
        j.task = nil
        j.error = message
        jobs[id] = j
    }

    private func _failAwaiters(for id: String, with error: Error) {
        let pending = awaiters[id] ?? []
        awaiters[id] = nil
        for cont in pending { cont.resume(throwing: error) }
    }

    private static func humanize(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut:                   return "Network timed out. Try again."
        case NSURLErrorNotConnectedToInternet:     return "No internet connection."
        case NSURLErrorNetworkConnectionLost:      return "Connection lost mid-download. Tap retry."
        case NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost:        return "Couldn't reach the host. The feed may be down."
        case NSURLErrorBadServerResponse:          return "The server returned a bad response."
        case NSURLErrorDataNotAllowed:             return "Downloads are blocked on this network."
        default:                                   return error.localizedDescription
        }
    }
}

@MainActor
struct DownloadJob {
    var loaded: Int64 = 0
    var total: Int64 = 0
    var startedAt: Date = .now
    var error: String? = nil
    /// `nil` once the job terminates. Live → cancellable.
    var task: Task<Void, Never>? = nil

    /// 0..1 fraction. Returns 0 before the first byte is reported.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(loaded) / Double(total)))
    }

    /// Bytes/second over the run lifetime. Returns 0 in the first 0.5s.
    var bytesPerSecond: Double {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0.5, loaded > 0 else { return 0 }
        return Double(loaded) / elapsed
    }
}

enum AudioJobError: LocalizedError {
    case badURL
    case cancelled
    var errorDescription: String? {
        switch self {
        case .badURL:    return "Bad audio URL"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - TranscribeStore
//
// One `TranscribeJob` per `Episode.id`. The stage drives a unified progress
// bar that covers the entire pipeline:
//
//   fetching audio → (loading | downloading) model → transcribing → speakers
//
// `overall` maps each stage to a slice of [0,1] so the bar fills smoothly
// rather than flashing 0% three times in a row. The fetching-audio stage
// listens to the matching `DownloadStore` job, so progress comes through
// without TranscribeStore having to know about URLSession bytes.

@MainActor
@Observable
final class TranscribeStore {
    var jobs: [String: TranscribeJob] = [:]

    private let downloadStore: DownloadStore

    init(downloadStore: DownloadStore) {
        self.downloadStore = downloadStore
    }

    func job(for id: String) -> TranscribeJob? { jobs[id] }

    /// Cancel an in-flight transcribe pipeline. Also cancels the audio
    /// download underneath if we're in the fetching stage (so the user
    /// doesn't pay for bytes they no longer want).
    func cancel(episodeID: String) {
        if let j = jobs[episodeID] {
            j.task?.cancel()
            if j.stage == .fetchingAudio {
                downloadStore.cancel(episodeID: episodeID)
            }
        }
        jobs.removeValue(forKey: episodeID)
    }

    func startTranscribe(
        episode: Episode,
        settings: AppSettings,
        ctx: ModelContext,
        onAnalyze: ((Episode) -> Void)? = nil,
        toast: @escaping (String) -> Void
    ) {
        guard jobs[episode.id]?.task == nil else { return }  // already running
        var job = TranscribeJob()
        let id = episode.id

        // Drive a TaskCenter pill for the sidebar.
        let center = TaskCenter.shared
        let kind: TaskItem.Kind = settings.transcribeEngine == "local"
            ? .transcribeLocal : .transcribeCloud
        let centerId = center.add(TaskItem(
            kind: kind,
            title: String(episode.title.prefix(40)),
            subtitle: "Preparing…",
            progress: 0,
            status: .running,
            onCancel: nil,
            episodeID: episode.id
        ))

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // 1) Audio
                self.update(id) { $0.stage = .fetchingAudio }
                center.setSubtitle(centerId, "Fetching audio…")
                let audioURL = try await self.fetchAudioWithProgress(
                    episode: episode, ctx: ctx, jobID: id, centerId: centerId
                )

                if settings.transcribeEngine == "local" {
                    try await self.runLocal(
                        episode: episode, audioURL: audioURL,
                        settings: settings, ctx: ctx, jobID: id,
                        centerId: centerId, toast: toast
                    )
                } else {
                    try await self.runCloud(
                        episode: episode, audioURL: audioURL,
                        settings: settings, ctx: ctx, jobID: id,
                        centerId: centerId, toast: toast
                    )
                }

                // Success — drop the job entry (transcript is now in
                // SwiftData; view reads `episode.transcribed`).
                self.jobs.removeValue(forKey: id)

                // Optional follow-up: AI summary / takeaways.
                onAnalyze?(episode)
            } catch is CancellationError {
                toast("Transcription cancelled")
                center.cancel(centerId)
                self.jobs.removeValue(forKey: id)
            } catch let LocalWhisperError.cancelled {
                toast("Transcription cancelled")
                center.cancel(centerId)
                self.jobs.removeValue(forKey: id)
            } catch {
                // KEEP the job entry alive on failure — `task = nil` flips
                // the page from "running" UI back to a Retry CTA, while
                // `error` populates the inline error line. Without this,
                // the view sees `jobs[id] == nil` and renders the idle
                // "Transcribe" state, hiding what just went wrong.
                let msg = error.localizedDescription
                self.update(id) {
                    $0.error = msg
                    $0.task = nil
                }
                center.fail(centerId, msg)
            }
        }
        job.task = task
        jobs[id] = job

        // Wire cancel from TaskCenter pill to our store.
        center.update(centerId) { item in
            item.onCancel = { [weak self] in
                Task { @MainActor in self?.cancel(episodeID: id) }
            }
        }
    }

    // MARK: Pipeline stages

    private func fetchAudioWithProgress(
        episode: Episode, ctx: ModelContext, jobID: String, centerId: UUID
    ) async throws -> URL {
        // If already on disk, skip the whole stage.
        if episode.downloaded, let path = episode.localFilePath,
           FileManager.default.fileExists(atPath: path) {
            update(jobID) { $0.stageProgress = 1 }
            return URL(fileURLWithPath: path)
        }

        // Start a side observer that mirrors the DownloadStore job's
        // progress into our stage progress + the TaskCenter pill, until
        // the download completes or the transcribe job goes away.
        let observer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.jobs[jobID] != nil else { return }
                if let dj = self.downloadStore.job(for: jobID) {
                    self.update(jobID) { $0.stageProgress = dj.progress }
                    TaskCenter.shared.setProgress(
                        centerId,
                        TranscribeJob(stage: .fetchingAudio, stageProgress: dj.progress).overall,
                        subtitle: "Fetching audio · \(Int(dj.progress * 100))%"
                    )
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { observer.cancel() }

        let url = try await downloadStore.downloadIfNeeded(episode: episode, ctx: ctx)
        update(jobID) { $0.stageProgress = 1 }
        return url
    }

    private func runCloud(
        episode: Episode, audioURL: URL,
        settings: AppSettings, ctx: ModelContext, jobID: String,
        centerId: UUID, toast: @escaping (String) -> Void
    ) async throws {
        guard let key = settings.openaiKey, !key.isEmpty else {
            throw NSError(domain: "Pode", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Add your OpenAI API key in Settings to transcribe"
            ])
        }
        update(jobID) { $0.stage = .transcribing; $0.stageProgress = 0 }
        TaskCenter.shared.setSubtitle(centerId, "Transcribing…")

        let result = try await WhisperService.transcribe(
            audioFileURL: audioURL,
            apiKey: key,
            model: settings.whisperModel
        )
        // Persist transcript lines.
        for old in episode.transcriptLines { ctx.delete(old) }
        for (idx, line) in result.lines.enumerated() {
            let text = settings.simplifiedChinese
                ? Fmt.toSimplifiedChinese(line.text) : line.text
            let m = TranscriptLineModel(t: line.t, text: text, speaker: line.speaker, lineIndex: idx)
            m.episode = episode
            ctx.insert(m)
        }
        episode.transcribed = true
        episode.transcribedAt = .now
        try? ctx.save()
        update(jobID) { $0.stage = .finalizing; $0.stageProgress = 1 }
        TaskCenter.shared.succeed(centerId, subtitle: "Done · \(result.lines.count) segments")
        toast("Transcribed · \(result.lines.count) segments")
    }

    private func runLocal(
        episode: Episode, audioURL: URL,
        settings: AppSettings, ctx: ModelContext, jobID: String,
        centerId: UUID, toast: @escaping (String) -> Void
    ) async throws {
        let modelChoice = LocalWhisperModel(rawValue: settings.localWhisperModel) ?? .highest
        let dur = max(episode.duration, 1)
        let lang = settings.transcribeLanguage.isEmpty ? nil : settings.transcribeLanguage

        // Wipe any partial / previous transcript before streaming new lines in.
        for old in episode.transcriptLines { ctx.delete(old) }
        episode.transcribed = false
        try? ctx.save()

        // Streaming state. Lives across the onSegment callbacks below.
        // Dedup keys are `(seek, startMillis)` — `seek` alone is shared
        // by every segment within a chunk, so using it as a unique key
        // would silently drop all-but-one segment per chunk (the original
        // streaming bug). `(seek, startMillis)` is unique per segment.
        struct SegmentKey: Hashable { let seek: Int; let startMillis: Int }
        let seenLock = NSLock()
        nonisolated(unsafe) var seenKeys: Set<SegmentKey> = []

        let result: WhisperResult
        do {
            result = try await LocalWhisperService.shared.transcribe(
                audioFileURL: audioURL,
                model: modelChoice,
                language: lang,
                audioDuration: dur,
                onStage: { [weak self] stage in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch stage {
                        case .checking:
                            self.update(jobID) {
                                $0.stage = .loadingModel; $0.stageProgress = 0
                            }
                            TaskCenter.shared.setSubtitle(centerId, "Checking model…")
                        case .downloadingModel(let p):
                            self.update(jobID) {
                                $0.stage = .downloadingModel; $0.stageProgress = p
                            }
                            TaskCenter.shared.setProgress(
                                centerId,
                                TranscribeJob(stage: .downloadingModel, stageProgress: p).overall,
                                subtitle: "Downloading model · \(Int(p * 100))%"
                            )
                        case .loadingModel:
                            self.update(jobID) {
                                $0.stage = .loadingModel; $0.stageProgress = 1
                            }
                            TaskCenter.shared.setSubtitle(centerId, "Loading model…")
                        case .transcribing(let p):
                            self.update(jobID) {
                                $0.stage = .transcribing; $0.stageProgress = p
                            }
                            TaskCenter.shared.setProgress(
                                centerId,
                                TranscribeJob(stage: .transcribing, stageProgress: p).overall,
                                subtitle: "Transcribing · \(Int(p * 100))%"
                            )
                        }
                    }
                },
                onSegment: { [weak self] segments in
                    // Filter to segments we haven't seen yet. Compound
                    // key (seek + start) is unique per segment; using
                    // seek alone collapses chunks.
                    let fresh: [StreamingSegment] = {
                        seenLock.lock(); defer { seenLock.unlock() }
                        var out: [StreamingSegment] = []
                        for s in segments {
                            let key = SegmentKey(seek: s.seek,
                                                 startMillis: Int(s.start * 1000))
                            if seenKeys.insert(key).inserted {
                                out.append(s)
                            }
                        }
                        return out
                    }()
                    guard !fresh.isEmpty else { return }

                    // Convert to in-memory StreamLine rows and append to
                    // the job's sorted buffer. NO SwiftData writes during
                    // streaming — they were the source of the main-thread
                    // melt (each insert kicked the @Query, every observer
                    // re-rendered, sortedTranscriptLines re-sorted, etc).
                    let toInsert: [StreamLine] = fresh.map { seg in
                        let text = settings.simplifiedChinese
                            ? Fmt.toSimplifiedChinese(seg.text) : seg.text
                        let lineId = seg.seek &* 10_000 &+ Int(seg.start * 1000)
                        return StreamLine(id: lineId, t: seg.t,
                                          text: text, speaker: nil)
                    }
                    self?.update(jobID) { job in
                        job.appendStreaming(toInsert)
                    }
                }
            )
        } catch {
            // Cancellation or pipeline failure: drop any streamed rows
            // so the episode doesn't end up in a half-transcribed state.
            // SwiftData is untouched during streaming (Phase B), so the
            // only thing to clear is the in-memory job buffer.
            update(jobID) { $0.streamingLines = [] }
            for line in episode.transcriptLines { ctx.delete(line) }
            try? ctx.save()
            throw error
        }

        // ── Persist phase ────────────────────────────────────────────
        // Single batch insert into SwiftData. WhisperKit's `result.lines`
        // is canonical (post-merge, post-offset-adjustment), so we
        // persist from that — no per-segment inserts, no @Query refresh
        // storm. One save at the end is dramatically cheaper than the
        // previous "save per onSegment batch" pattern.
        update(jobID) { $0.stage = .finalizing; $0.stageProgress = 0.2 }

        // Drop any pre-existing rows (e.g. from a previously-failed
        // attempt that left orphans).
        for line in episode.transcriptLines { ctx.delete(line) }

        // Insert + dedup-by-text-adjacent in the same pass, so we
        // don't have to run a separate cleanup query afterwards. VAD
        // can emit two segments with identical text at a chunk
        // boundary; we keep the first.
        var prevText: String? = nil
        for (idx, line) in result.lines.enumerated() {
            let text = settings.simplifiedChinese
                ? Fmt.toSimplifiedChinese(line.text) : line.text
            if let pt = prevText, pt == text { continue }
            let m = TranscriptLineModel(
                t: line.t, text: text, speaker: line.speaker,
                lineIndex: idx
            )
            m.episode = episode
            ctx.insert(m)
            prevText = text
        }

        episode.transcribed = true
        episode.transcribedAt = .now
        try? ctx.save()

        // Streaming buffer no longer needed — UI will source from
        // SwiftData via the cached @State in EpisodeView from here on.
        update(jobID) { $0.streamingLines = [] }

        let lineCount = episode.transcriptLines.count

        // Speaker inference was removed — it never produced reliable
        // tags for short / single-host conversations and ate AI tokens
        // for no real signal. The `speaker` field on TranscriptLineModel
        // is kept for backward-compat with any rows that already had
        // tags assigned, but no new tags are generated.
        TaskCenter.shared.succeed(centerId, subtitle: "Done · \(lineCount) lines")
        toast("Transcribed · \(lineCount) lines")

        update(jobID) { $0.stage = .finalizing; $0.stageProgress = 1 }
    }

    // Note: `cleanupAfterStream` and `reconcileWithFinalResult` were
    // removed alongside Phase B's batch-persist rewrite. With
    // `result.lines` (WhisperKit's canonical post-merge output) as the
    // single persistence source, both passes are redundant — adjacent
    // duplicate-text dedup happens inline in the batch insert above,
    // and there's nothing to reconcile against because streaming no
    // longer touches SwiftData.

    private func update(_ id: String, mutate: (inout TranscribeJob) -> Void) {
        guard var j = jobs[id] else { return }
        mutate(&j)
        jobs[id] = j
    }
}

/// Lightweight value type for an in-flight transcript row. During
/// streaming the UI binds directly to `TranscribeJob.streamingLines`,
/// avoiding the SwiftData @Query refresh storm that hit every body
/// re-eval when each segment was being inserted live. Once the stream
/// finishes the canonical `WhisperResult.lines` is batch-persisted
/// into SwiftData in a single transaction.
struct StreamLine: Identifiable, Equatable, Sendable {
    let id: Int            // stable unique row identity (= old `lineIndex`)
    let t: Double          // absolute seconds in the audio
    let text: String
    let speaker: String?

    /// Backward-compat alias so call sites that still think in terms
    /// of `lineIndex` (highlight ids, scroll target keys) keep working.
    var lineIndex: Int { id }
}

@MainActor
struct TranscribeJob {
    enum Stage: String, Equatable {
        /// The pipeline is fetching the audio file (uses DownloadStore).
        case fetchingAudio
        /// Local engine: bringing model into memory.
        case loadingModel
        /// Local engine: model isn't cached on disk yet.
        case downloadingModel
        /// Whisper is producing text.
        case transcribing
        /// Persisting + clean-up. Briefly shown to avoid a flash of empty UI.
        case finalizing
    }

    var stage: Stage = .fetchingAudio
    /// 0..1 within the current stage.
    var stageProgress: Double = 0
    var error: String? = nil
    /// `nil` once the pipeline terminates.
    var task: Task<Void, Never>? = nil
    /// In-memory streamed transcript rows, kept sorted by `t`. The
    /// transcript pane binds to this directly while the job is alive,
    /// so segments don't have to round-trip through SwiftData (which
    /// previously triggered a @Query refresh per segment, melting the
    /// main thread). Cleared in `.finalizing` once persisted.
    var streamingLines: [StreamLine] = []

    /// Insertion-sorted append. `segments` arrives out of order from
    /// parallel VAD workers, so we walk an O(log n) binary search to
    /// find the slot and splice in. Batches of segments are typically
    /// 1-30 rows, so the overall pass is cheap.
    mutating func appendStreaming(_ rows: [StreamLine]) {
        for row in rows {
            // Skip dupes by lineIndex — defence against the rare case
            // where WhisperKit emits a post-merge segment with the same
            // (seek, start) we've already accepted.
            if streamingLines.contains(where: { $0.id == row.id }) { continue }
            // Binary search for insertion point by t.
            var lo = 0, hi = streamingLines.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if streamingLines[mid].t < row.t { lo = mid + 1 } else { hi = mid }
            }
            streamingLines.insert(row, at: lo)
        }
    }

    /// Unified 0..1 progress across the whole pipeline. Each stage owns a
    /// slice so the bar fills monotonically from start to finish.
    var overall: Double {
        switch stage {
        case .fetchingAudio:     return 0.00 + 0.30 * stageProgress
        case .loadingModel:      return 0.30 + 0.05 * stageProgress
        case .downloadingModel:  return 0.30 + 0.20 * stageProgress
        case .transcribing:      return 0.50 + 0.50 * stageProgress
        case .finalizing:        return 1.0
        }
    }

    var stageLabelKey: String {
        switch stage {
        case .fetchingAudio:     return "Fetching audio…"
        case .loadingModel:      return "Loading model…"
        case .downloadingModel:  return "Downloading model…"
        case .transcribing:      return "Transcribing…"
        case .finalizing:        return "Finalizing…"
        }
    }
}
