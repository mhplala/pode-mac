import SwiftUI
import SwiftData

struct EpisodeView: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @Environment(TranscribeStore.self) private var transcribes
    @Environment(\.modelContext) private var modelContext

    let episodeId: String
    @Query private var episodes: [Episode]

    enum EpTab: String, CaseIterable, Hashable { case description, transcript, highlights }
    enum AITab: String, CaseIterable, Hashable { case summary, takeaways, ask }

    @State private var tab: EpTab = .description
    @State private var aiTab: AITab = .summary

    /// View-only convenience reads. Source of truth lives in the stores —
    /// these survive page navigation; previously they were `@State` and
    /// dropped on every view tear-down.
    private var downloadJob: DownloadJob? { downloads.job(for: episodeId) }
    private var transcribeJob: TranscribeJob? { transcribes.job(for: episodeId) }
    private var downloading: Bool { (downloadJob?.task) != nil }
    private var transcribing: Bool { (transcribeJob?.task) != nil }

    @State private var analyzing: Bool = false
    @State private var pickingModel: Bool = false
    @State private var pickerSelection: LocalWhisperModel = .highest

    @State private var askValue: String = ""
    @State private var askLoading: Bool = false
    @State private var askAnswer: String? = nil
    @State private var askCitations: [(line: Int, t: Double)] = []
    @State private var askError: String? = nil

    // Content-aware suggested questions for the Ask pane. We fetch these
    // lazily the first time the user enters the Ask tab on a transcribed
    // episode, and again whenever the analysis (summary/takeaways) updates.
    // `suggestionsLoadedKey` carries the episode id + a hash of the summary
    // so we know when to refetch; an empty array falls back to the generic
    // defaults at render time.
    @State private var suggestedQuestions: [String] = []
    @State private var suggestionsLoading: Bool = false
    @State private var suggestionsLoadedKey: String? = nil

    @State private var confirmDeleteTranscript = false
    @State private var confirmRemoveDownload = false

    // ─── Perf: cached transcript display state ────────────────────────
    // The transcript pane used to read `ep.sortedTranscriptLines` and
    // `activeLineKey(...)` directly inside body, both of which re-sorted
    // / re-scanned the whole array on every body re-eval. With 300+ rows
    // × 60fps player ticks that produced 6-8 ms of main-thread work per
    // frame — visible playback jitter and a frozen UI during streaming.
    //
    // Now: we cache the sorted SwiftData rows in @State (refreshed only
    // when the row count actually changes), and the "current active
    // line" is updated by an .onChange off player.currentTime — keeping
    // the body's tracked Observable set clean of per-tick deps so it
    // re-renders only when the active line actually crosses.
    @State private var sortedCache: [StreamLine] = []
    @State private var activeLineIdx: Int = -1
    /// Wall-clock time of the last auto-scroll. We skip back-to-back
    /// scrollTo calls within the animation window so a fast burst of
    /// active-line transitions doesn't stack into a fighting set of
    /// animations inside the ScrollView.
    @State private var lastScrollAt: Date = .distantPast

    /// Detects user scrolling. `.scrollPosition(id:)` binds the
    /// currently-anchored row id. We compare against the row we LAST
    /// programmatically scrolled to: if they diverge outside our own
    /// animation settling window, the user moved the ScrollView and
    /// we should stop yanking them back to the playhead.
    @State private var observedAnchor: Int? = nil
    /// Timestamp of our last programmatic scrollTo. `observedAnchor`
    /// changes during the ~300-500ms animation that follows — those
    /// changes are NOT user-driven, so we ignore anchor diffs within
    /// this settling window.
    @State private var lastProgrammaticScrollAt: Date = .distantPast
    /// When the user last manually scrolled. While `now - this < 5s`
    /// we suppress auto-scroll entirely so the user can read where
    /// they scrolled to.
    @State private var userScrolledAt: Date = .distantPast

    init(episodeId: String) {
        self.episodeId = episodeId
        _episodes = Query(filter: #Predicate<Episode> { $0.id == episodeId })
    }

    /// Live height of the tab content area. Updated from a GeometryReader
    /// that wraps the body — lets each tab content view (description /
    /// transcript / highlights) size itself to "the rest of the page",
    /// rather than the previous hard-coded 560pt that left a strip of
    /// empty space on tall windows.
    @State private var tabContentHeight: CGFloat = 560

    var body: some View {
        GeometryReader { geo in
            // Subtract the rough size of the page chrome that lives ABOVE
            // the tabs card (back button, header card with cover/buttons,
            // breathing room) plus just enough room for the floating
            // dock at the bottom — previously the bottom margin was way
            // over-estimated, which left a strip of empty space below
            // the tab card on tall windows.
            let chromeAbove: CGFloat = 300
            let chromeBelow: CGFloat = 110
            let height = max(420, geo.size.height - chromeAbove - chromeBelow)
            content
                .onAppear {
                    tabContentHeight = height
                    // Land on the transcript tab if this episode is
                    // already transcribed; otherwise stay on the
                    // description default. EpisodeView's @State resets
                    // on every navigation, so this only runs as the
                    // user enters — manual tab switches afterward are
                    // never overridden.
                    if let ep = episodes.first, !ep.transcriptLines.isEmpty {
                        tab = .transcript
                    }
                }
                .onChange(of: geo.size.height) { _, _ in
                    tabContentHeight = height
                }
                // Back button stays pinned at the page's top-left
                // regardless of scroll position — sits above the
                // GlassScroll so it never disappears as the user
                // scrolls long descriptions / transcripts.
                .overlay(alignment: .topLeading) {
                    Button {
                        store.back()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 11))
                            Text(L10n.t("Back", language: lang))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Ink.secondary)
                    .font(.sans(12.5, weight: .medium))
                    // Liquid-glass chip so the button stays legible
                    // when scrolled-through cover art passes under it.
                    .glass(.chip)
                    .padding(.leading, 32)
                    .padding(.top, 12)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Bump body re-eval counter — surfaces in PerfHUD top-right.
        let _ = PerfCounters.shared.bodyEval()
        // Time the body construction. `measureBody` is a no-op-ish
        // wrapper that brackets the build with DispatchTime.now().
        // It does NOT capture render time (that's GPU/SwiftUI), but
        // it does capture every sort/scan/predicate/alloc done inline,
        // which is where most hidden cost lives.
        measureBody(.episode) {
        // Outer container is intentionally NOT scrollable. Each inner
        // pane (transcript / description / highlights / AI inspector)
        // handles its own internal scrolling, so the page itself stays
        // fixed at viewport height. This eliminates the class of bug
        // where outer-scroll layout work competed with in-pane
        // animations + ScrollViews on the main thread.
        VStack(alignment: .leading, spacing: 0) {
            // Back button is rendered as a fixed-position overlay
            // below — leaving an empty top spacer here so the rest
            // of the page content doesn't slide under it.
            Color.clear.frame(height: 32)

            if let ep = episodes.first, let show = ep.show {
                // Always 2-column. Window has a minimum width that
                // guarantees this layout fits, so we don't flip to a
                // stacked variant — switching tabs won't shuffle the
                // overall page structure.
                VStack(spacing: 16) {
                    headerCard(ep: ep, show: show)
                    HStack(alignment: .top, spacing: 20) {
                        tabsCard(ep: ep, show: show)
                            .frame(maxWidth: .infinity)
                        aiInspector(ep: ep, show: show)
                            .frame(width: 380)
                    }
                }
                .padding(.top, 8)
            } else {
                Text(t("Episode not found.", lang))
                    .font(.serif(16))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                    .padding(.top, 32)
            }
        }
        .frame(maxWidth: 1240, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .alert(t("Delete transcript?", lang), isPresented: $confirmDeleteTranscript) {
            Button(t("Cancel", lang), role: .cancel) {}
            Button(t("Delete", lang), role: .destructive) { deleteTranscript() }
        } message: {
            Text(t("AI summaries will be cleared too.", lang))
        }
        .alert(t("Remove downloaded audio?", lang), isPresented: $confirmRemoveDownload) {
            Button(t("Cancel", lang), role: .cancel) {}
            Button(t("Remove", lang), role: .destructive) { removeDownload() }
        }
        // Live perf HUD — top-right corner, only on this view. Numbers
        // are events/sec for the EpisodeView body, the dock's
        // ScrubberRow, player ticks, scroll triggers, and active-line
        // changes. Anything turning red is above a "this should be
        // quiet" threshold.
        .overlay(alignment: .topTrailing) {
            PerfHUD()
                .padding(.top, 56)
                .padding(.trailing, 24)
        }
        }   // closes measureBody { ... }
    }

    // MARK: - Header card

    @ViewBuilder
    private func headerCard(ep: Episode, show: Show) -> some View {
        HStack(alignment: .top, spacing: 22) {
            CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 140, radius: 18, playing: isPlaying(ep))
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: "\(show.title) · \(Fmt.date(ep.pubDate))")
                    .padding(.bottom, 6)
                Text(ep.title)
                    .font(.serif(30, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 12)

                HStack(spacing: 8) {
                    Button {
                        store.togglePlay(ep)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isPlaying(ep) ? "pause.fill" : "play.fill")
                            Text(isPlaying(ep)
                                 ? L10n.t("Pause", language: lang)
                                 : L10n.t(ep.played > 0 ? "Resume" : "Play", language: lang))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 78)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    downloadButton(ep: ep)
                    transcribeButton(ep: ep)

                    Spacer()
                }
                .padding(.bottom, 16)

                if pickingModel {
                    modelPickerCard(ep: ep)
                        .padding(.bottom, 12)
                }

                // Single, stage-aware progress strip. The transcribe
                // pipeline takes priority — its `fetchingAudio` stage already
                // mirrors the underlying download progress, so we don't show
                // two bars when transcribe owns the download.
                unifiedStatus(ep: ep)
            }
        }
        .padding(24)
        .glass(.panel)
    }

    @ViewBuilder
    private func downloadButton(ep: Episode) -> some View {
        Button {
            if downloading {
                downloads.cancel(episodeID: ep.id)
                return
            }
            if ep.downloaded {
                confirmRemoveDownload = true
                return
            }
            downloads.startDownload(episode: ep, ctx: modelContext)
        } label: {
            HStack(spacing: 6) {
                if ep.downloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Success.primary)
                    Text(L10n.t("Downloaded", language: lang)).lineLimit(1)
                } else if let job = downloadJob, job.task != nil {
                    let pct = Int(job.progress * 100)
                    Text(pct > 0 ? "Cancel · \(pct)%" : "Cancel").lineLimit(1)
                } else {
                    Image(systemName: "arrow.down.circle")
                    Text(L10n.t("Download", language: lang)).lineLimit(1)
                }
            }
            .frame(minWidth: 130)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(GhostButtonStyle())
        // Disable manual download while the transcribe pipeline is in its
        // fetching-audio stage — that pipeline owns the download.
        .disabled(transcribeJob?.stage == .fetchingAudio)
    }

    @ViewBuilder
    private func transcribeButton(ep: Episode) -> some View {
        Button {
            if transcribing {
                transcribes.cancel(episodeID: ep.id)
                return
            }
            handleTranscribeTap(ep: ep)
        } label: {
            HStack(spacing: 6) {
                if ep.transcribed {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(Success.primary)
                    Text(L10n.t("Transcribed", language: lang))
                        .foregroundColor(Success.primary).lineLimit(1)
                } else if let job = transcribeJob, job.task != nil {
                    DotPulse()
                    Text(t(job.stageLabelKey, lang)).lineLimit(1)
                } else {
                    Image(systemName: "text.alignleft")
                    Text(L10n.t("Transcribe", language: lang)).lineLimit(1)
                }
            }
            .frame(minWidth: 130)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(GhostButtonStyle())
    }

    /// First-time user with the local engine sees an inline model picker;
    /// everyone else jumps straight into transcription.
    private func handleTranscribeTap(ep: Episode) {
        if store.settings.transcribeEngine == "local",
           !store.settings.localWhisperPicked {
            // Pre-select what's saved (default Balanced).
            pickerSelection = LocalWhisperModel(rawValue: store.settings.localWhisperModel) ?? .highest
            pickingModel = true
            return
        }
        startTranscribe(ep: ep)
    }

    @ViewBuilder
    private func modelPickerCard(ep: Episode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundColor(accent).font(.system(size: 11))
                EyebrowText(text: "Set up transcription · one-time")
                Spacer()
                Button {
                    pickingModel = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Ink.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }

            ForEach(LocalWhisperModel.allCases, id: \.self) { m in
                modelOptionRow(m)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Use cloud instead") {
                    var s = store.settings
                    s.transcribeEngine = "openai"
                    store.saveSettings(s)
                    pickingModel = false
                    startTranscribe(ep: ep)
                }
                .buttonStyle(GhostSmallButtonStyle())
                Button {
                    var s = store.settings
                    s.localWhisperModel = pickerSelection.rawValue
                    s.localWhisperPicked = true
                    s.transcribeEngine = "local"
                    store.saveSettings(s)
                    pickingModel = false
                    startTranscribe(ep: ep)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 11))
                        Text(t("Download & Go", lang))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(GlassBackground(variant: .deep))
    }

    @ViewBuilder
    private func modelOptionRow(_ m: LocalWhisperModel) -> some View {
        let selected = pickerSelection == m
        Button {
            pickerSelection = m
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? accent : Ink.tertiary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(m.displayName)
                            .font(.serif(14, weight: .medium))
                            .foregroundColor(Ink.primary)
                        if m == .highest {
                            Text(t("Recommended", lang))
                                .font(.mono(9.5, weight: .semibold))
                                .foregroundColor(accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(accent.opacity(0.12))
                                )
                        }
                    }
                    Text("\(m.sizeLabel) · \(m.speedLabel) · \(m.qualityLabel)")
                        .font(.mono(11))
                        .foregroundColor(Ink.tertiary)
                }
                Spacer()
                if LocalWhisperService.isModelCached(m) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Success.primary)
                        Text(t("Cached", lang))
                    }
                    .font(.mono(10))
                    .foregroundColor(Ink.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? accent.opacity(0.06) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selected ? accent.opacity(0.25) : Color.black.opacity(0.05),
                                    lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One progress widget covering download AND transcribe. Renders one
    /// of three modes:
    /// - Transcribe pipeline active → stage-aware bar covering audio fetch
    ///   through speaker tagging.
    /// - Standalone download active → bytes / speed / ETA bar.
    /// - Idle but downloaded → static "downloaded · N MB" line.
    /// - Otherwise → nothing.
    /// Errors from either store get surfaced inline with a Retry button.
    @ViewBuilder
    private func unifiedStatus(ep: Episode) -> some View {
        if let job = transcribeJob {
            transcribeStatus(ep: ep, job: job)
        } else if let job = downloadJob {
            downloadStatus(ep: ep, job: job)
        } else if ep.downloaded {
            staticDownloadedRow(ep: ep)
        }
    }

    @ViewBuilder
    private func transcribeStatus(ep: Episode, job: TranscribeJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Failed jobs keep their entry around (so the view can render
            // the error + retry) but skip the progress bar — a half-full
            // bar next to a red error line is confusing.
            if job.task != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.07)).frame(height: 6)
                        Capsule().fill(accent.opacity(0.85))
                            .frame(width: max(0, geo.size.width * job.overall), height: 6)
                            .animation(.easeOut(duration: 0.25), value: job.overall)
                    }
                }
                .frame(height: 6)
                HStack(spacing: 8) {
                    Text(t(job.stageLabelKey, lang))
                        .font(.mono(11))
                        .foregroundColor(Ink.secondary)
                    Spacer()
                    Text("\(Int(job.overall * 100))%")
                        .font(.mono(11))
                        .foregroundColor(Ink.tertiary)
                }
            }
            if let err = job.error {
                errorLine(message: err) {
                    handleTranscribeTap(ep: ep)
                }
            }
        }
    }

    @ViewBuilder
    private func downloadStatus(ep: Episode, job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let pct = job.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07)).frame(height: 6)
                    Capsule().fill(accent.opacity(0.85))
                        .frame(width: max(0, geo.size.width * pct), height: 6)
                        .animation(.easeOut(duration: 0.25), value: pct)
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                Text(downloadLeftText(job: job))
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
                Spacer()
                Text(downloadRightText(ep: ep, job: job))
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
            }
            if let err = job.error {
                errorLine(message: err) {
                    downloads.startDownload(episode: ep, ctx: modelContext)
                }
            }
        }
    }

    @ViewBuilder
    private func staticDownloadedRow(ep: Episode) -> some View {
        HStack(spacing: 8) {
            Text("downloaded · \(Fmt.bytes(ep.audioSize))")
                .font(.mono(11))
                .foregroundColor(Ink.tertiary)
            Spacer()
            Text(Fmt.dur(ep.duration))
                .font(.mono(11))
                .foregroundColor(Ink.tertiary)
        }
    }

    @ViewBuilder
    private func errorLine(message: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Danger.primary)
                .font(.system(size: 11))
                .padding(.top, 2)
            Text(message)
                .font(.sans(12))
                .foregroundColor(Danger.primary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                retry()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text(L10n.t("Retry", language: lang))
                }
            }
            .buttonStyle(GhostSmallButtonStyle())
        }
        .padding(.top, 4)
    }

    private func downloadLeftText(job: DownloadJob) -> String {
        if job.total > 0 {
            let loadedMB = Double(job.loaded) / 1_048_576
            let totalMB  = Double(job.total) / 1_048_576
            return String(format: "%.1f / %.1f MB · %d%%",
                          loadedMB, totalMB, Int(job.progress * 100))
        }
        let loadedMB = Double(job.loaded) / 1_048_576
        return String(format: "%.1f MB", loadedMB)
    }

    private func downloadRightText(ep: Episode, job: DownloadJob) -> String {
        let bps = job.bytesPerSecond
        guard bps > 0 else { return "starting…" }
        let speedMBs = bps / 1_048_576
        if job.total > 0 {
            let remaining = Double(job.total - job.loaded) / bps
            return String(format: "%.1f MB/s · %@ left", speedMBs, etaString(remaining))
        }
        return String(format: "%.1f MB/s", speedMBs)
    }

    private func etaString(_ seconds: Double) -> String {
        if !seconds.isFinite || seconds < 0 { return "—" }
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m \(s % 60)s" }
        let h = m / 60
        return "\(h)h \(m % 60)m"
    }

    // MARK: - Tabs card

    private func tabsCard(ep: Episode, show: Show) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(EpTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(label(for: t, ep: ep))
                            .font(.sans(13, weight: tab == t ? .semibold : .medium))
                            .foregroundColor(tab == t ? Ink.primary : Ink.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(tab == t ? Color.black.opacity(0.06) : .clear)
                            )
                            // CRITICAL: without an explicit content shape,
                            // hit-test on inactive tabs (clear background)
                            // falls back to the text-glyph shape — clicks
                            // landing in the padded space around letters
                            // get dropped, which feels like dead zones.
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if ep.transcribed {
                    Text("\(ep.transcriptLines.count) lines")
                        .font(.mono(11))
                        .foregroundColor(Ink.tertiary)
                    Button {
                        confirmDeleteTranscript = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Ink.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1),
                alignment: .bottom
            )

            switch tab {
            case .transcript: transcriptTab(ep: ep)
            case .description: descriptionTab(ep: ep)
            case .highlights: highlightsTab(ep: ep)
            }
        }
        .glass(.panel)
        // Lock outer height so this card lines up with aiInspector
        // (which is also `.frame(height: tabContentHeight)`). The
        // inner panes now fill the remaining space via their own
        // ScrollViews — no more dual-mode height calculation.
        .frame(height: tabContentHeight)
    }

    private func label(for tab: EpTab, ep: Episode) -> String {
        switch tab {
        case .transcript:  return t("Transcript", lang)
        case .description: return t("Description", lang)
        case .highlights:  return "\(t("Highlights", lang)) · \(ep.highlights.count)"
        }
    }

    @ViewBuilder
    private func transcriptTab(ep: Episode) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if ep.transcriptLines.isEmpty && !transcribing {
                    VStack(spacing: 18) {
                        Text(t("No transcript yet. Generate one to enable AI summaries, search, and concept extraction.", lang))
                            .font(.serif(16))
                            .italic()
                            .foregroundColor(Ink.tertiary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                        Button {
                            startTranscribe(ep: ep)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "text.alignleft")
                                Text(t("Transcribe this episode", lang))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(36)
                }
                if let job = transcribeJob, job.task != nil {
                    TranscribingBanner(
                        stage: job.stage,
                        progress: job.overall,
                        modelLabel: activeTranscribeModelLabel,
                        accent: accent
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }

                // Display layer.
                //
                // Backend transcribes in parallel via WhisperKit's VAD
                // pipeline — chunks finish out of order, so a naive
                // "render everything sorted by t" yields scattered text
                // (chunk 0 lines, gap, chunk 5 lines, bigger gap, chunk
                // 12 lines …). That feels broken even though the data
                // is correct.
                //
                // Source the display list from the right place:
                //   1. If the streaming buffer has content, it's the
                //      authoritative live view (mid-transcribe).
                //   2. Otherwise fall through to the cached persisted
                //      rows. This covers post-persist (speaker
                //      inference / finalizing) when streamingLines has
                //      been cleared but the cache holds the canonical
                //      result — without this fallback the UI went
                //      blank for the entire speaker-inference window.
                let visible: [StreamLine] = {
                    if let job = transcribeJob, !job.streamingLines.isEmpty {
                        return contiguousPrefix(of: job.streamingLines)
                    }
                    return sortedCache
                }()
                let totalCount: Int = {
                    if let job = transcribeJob, !job.streamingLines.isEmpty {
                        return job.streamingLines.count
                    }
                    return sortedCache.count
                }()
                ForEach(visible, id: \.id) { line in
                    TranscriptRow(
                        time: line.t,
                        speaker: line.speaker,
                        text: line.text,
                        isActive: line.id == activeLineId(in: visible),
                        onTap: {
                            if store.player.currentEpisodeID != ep.id {
                                store.startPlaying(ep)
                            }
                            store.player.commitSeek(to: line.t)
                        },
                        onSaveHighlight: {
                            store.saveHighlight(episode: ep, at: line.t, quote: line.text)
                        }
                    )
                    .equatable()
                    .transition(.asymmetric(
                        // New lines slide up and fade in from below. The
                        // ForEach insertion animation only fires when the
                        // parent has a value-driven `.animation(value:)`
                        // modifier (added below) — without that the
                        // transition is a no-op.
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                }
                // Skeleton placeholders while we're waiting for either
                // (a) the very first lines, or (b) earlier chunks to fill
                // in behind a contiguous-prefix gap. Strictly gated on
                // `transcribing` so no shimmer animation outlives the
                // pipeline.
                if transcribing {
                    if visible.isEmpty {
                        // Whole first stretch is still decoding — 4 rows.
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { _ in
                                TranscriptLineSkeleton()
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .transition(.opacity)
                    } else if visible.count < totalCount {
                        // Some lines arrived but a later batch hasn't.
                        VStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { _ in
                                TranscriptLineSkeleton()
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 24)
            // Padding key derived from cache + streaming state, NOT
            // from ep.transcriptLines (which would put the relationship
            // in body's observation set and cause re-evals on every
            // SwiftData speaker write during inference).
            .padding(.vertical,
                     (sortedCache.isEmpty && (transcribeJob?.streamingLines.isEmpty ?? true)) ? 0 : 24)
            // Drives the row-level insertion animations + skeleton
            // fade-outs. Key on the active source's count so the
            // animation actually fires on inserts.
            .animation(.easeOut(duration: 0.28),
                       value: (transcribeJob?.streamingLines.isEmpty ?? true)
                           ? sortedCache.count
                           : (transcribeJob?.streamingLines.count ?? 0))
            // Mark this stack as the scroll target so .scrollPosition(id:)
            // can observe which row is anchored. Lets us distinguish
            // user-driven scrolls from our own proxy.scrollTo settling.
            .scrollTargetLayout()
        }
        // Two-way binding of "which row id is at the center anchor".
        // We only READ from this — we never write to it (programmatic
        // scrolling stays on proxy.scrollTo so we control timing /
        // animation). When it changes outside our scroll settling
        // window, the user moved the ScrollView themselves.
        .scrollPosition(id: $observedAnchor, anchor: .center)
        // Cache refresh triggers. The cache is the ONLY sorted list we
        // build; body never sorts.
        //   - count change: persist phase inserted/deleted rows.
        //   - transcribing flip: start (clear stale) or end (pick up
        //     speakers + any post-stream writes).
        //   - first appear: cold load.
        .onChange(of: ep.transcriptLines.count) { _, _ in refreshSortedCache(ep: ep) }
        .onChange(of: transcribing) { _, isNow in
            if isNow {
                // Starting a new transcription on an already-transcribed
                // episode: drop the stale cache so the streaming buffer
                // (not last session's rows) drives the live display.
                sortedCache = []
                activeLineIdx = -1
            } else {
                refreshSortedCache(ep: ep)
            }
        }
        .onAppear { refreshSortedCache(ep: ep) }
        // Active-line tracking: update @State once when the player
        // crosses a line boundary. By moving this OUT of body we stop
        // tracking player.currentTime as a body dep, which is the main
        // reason the view used to re-render 60×/sec during playback.
        .onChange(of: store.player.currentTime) { _, _ in
            PerfCounters.shared.tick()
            updateActiveLine(proxy: proxy, ep: ep)
        }
        .onChange(of: activeLineIdx) { _, _ in
            PerfCounters.shared.activeLineChanged()
            // Active line changed → fire one throttled scroll.
            performAutoScroll(proxy: proxy, ep: ep)
        }
        // User-scroll detection. `observedAnchor` changes for two
        // reasons: (a) our own proxy.scrollTo animation settling
        // (ignored — `lastProgrammaticScrollAt` was just set), or
        // (b) the user moved the ScrollView themselves. The latter
        // stamps `userScrolledAt`, which suppresses auto-scroll for
        // 5 seconds so they can read where they scrolled to.
        .onChange(of: observedAnchor) { _, _ in
            let now = Date()
            // Wider window than the animation itself (0.55s) — anchor
            // changes can ripple a beat after the animation visually
            // ends as ScrollView's layout settles.
            if now.timeIntervalSince(lastProgrammaticScrollAt) < 0.9 {
                return
            }
            userScrolledAt = now
        }
        // Fill the remaining height inside the parent tabsCard. The
        // tabsCard outer locks to `tabContentHeight`; this inner pane
        // soaks up whatever's left after the tab strip.
        .frame(maxHeight: .infinity)
        }
    }

    /// Pull the current sorted snapshot from SwiftData once and stash
    /// it as a value-type [StreamLine]. Called only on count change /
    /// transcribing flip / first appearance — never per frame.
    private func refreshSortedCache(ep: Episode) {
        let rows = ep.transcriptLines.sorted { $0.t < $1.t }
        sortedCache = rows.map { m in
            StreamLine(id: m.lineIndex, t: m.t,
                       text: m.text, speaker: m.speaker)
        }
        // Reset active so the next currentTime tick recomputes against
        // the fresh list.
        activeLineIdx = -1
    }

    /// Binary-search the active line for the current player time.
    /// O(log n) per call instead of the old `last(where:)` linear scan.
    /// Writes to `@State` so body re-renders only when the index
    /// actually changes (i.e. when audio crosses a line boundary, not
    /// every player tick).
    private func updateActiveLine(proxy: ScrollViewProxy, ep: Episode) {
        guard store.player.currentEpisodeID == ep.id else {
            if activeLineIdx != -1 { activeLineIdx = -1 }
            return
        }
        let lines: [StreamLine] = transcribing
            ? (transcribeJob?.streamingLines ?? [])
            : sortedCache
        guard !lines.isEmpty else {
            if activeLineIdx != -1 { activeLineIdx = -1 }
            return
        }
        let now = store.player.currentTime
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].t <= now { lo = mid + 1 } else { hi = mid }
        }
        let idx = lo - 1
        if idx != activeLineIdx { activeLineIdx = idx }
    }

    /// Throttled auto-scroll. Called on activeLineIdx change. Skips
    /// the scroll if we just animated within the last 0.4 s — back-to-
    /// back animations on the same ScrollView fight each other and
    /// produce visible jitter.
    private func performAutoScroll(proxy: ScrollViewProxy, ep: Episode) {
        guard activeLineIdx >= 0,
              store.player.currentEpisodeID == ep.id else { return }
        let now = Date()
        // 1. Animation-throttle: don't fire faster than the animation
        //    itself can finish. Throttle (0.6s) > animation (0.4s) so
        //    we never have two overlapping in-flight animations on the
        //    same ScrollView — that was the "scroll war" producing
        //    visible jitter on fast-talking podcasts.
        if now.timeIntervalSince(lastScrollAt) < 0.6 { return }
        // 2. User-scroll respect: if the user moved the ScrollView in
        //    the last 5 seconds, leave them where they are. Resumes
        //    automatically once the grace period elapses without new
        //    user activity.
        if now.timeIntervalSince(userScrolledAt) < 5.0 { return }

        let lines: [StreamLine] = transcribing
            ? (transcribeJob?.streamingLines ?? [])
            : sortedCache
        guard activeLineIdx < lines.count else { return }
        let key = lines[activeLineIdx].id
        lastScrollAt = now
        // Stamp BEFORE triggering the animation so the impending
        // `observedAnchor` changes (caused by our own scroll) fall
        // inside the settling window and don't get classified as
        // user activity.
        lastProgrammaticScrollAt = now
        PerfCounters.shared.scrollFired()
        // Shorter animation (0.4s) so it ends well within the throttle
        // window. Less time for the ScrollView to compete with any
        // user gesture that lands during the animation.
        withAnimation(.smooth(duration: 0.4, extraBounce: 0)) {
            proxy.scrollTo(key, anchor: .center)
        }
    }

    /// Helper for the row's `isActive` — accepts the visible list so
    /// it works against either streaming or cached source.
    private func activeLineId(in visible: [StreamLine]) -> Int? {
        guard activeLineIdx >= 0, activeLineIdx < visible.count else { return nil }
        return visible[activeLineIdx].id
    }

    /// Human-readable model label for the transcribing banner. Cloud
    /// engine shows the OpenAI Whisper model id; local engine shows
    /// the WhisperKit variant name. Previously the banner always read
    /// "STREAMING · whisper-1" regardless of engine — wrong for local.
    private var activeTranscribeModelLabel: String {
        if store.settings.transcribeEngine == "local" {
            let m = LocalWhisperModel(rawValue: store.settings.localWhisperModel) ?? .highest
            return m.displayName.uppercased()
        }
        return store.settings.whisperModel
    }

    @ViewBuilder
    private func descriptionTab(ep: Episode) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let desc = ep.episodeDescription, !desc.isEmpty {
                    // AttributedString routes through NSDataDetector so
                    // bare URLs in the description (no markdown brackets
                    // needed) become real clickable links. `.textSelection
                    // (.enabled)` makes the body selectable + copyable
                    // with the standard ⌘C shortcut.
                    Text(linkifiedDescription(desc))
                        .font(.serif(16))
                        .foregroundColor(Ink.secondary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .tint(accent)
                } else {
                    Text(t("No description in the feed.", lang))
                        .font(.serif(16))
                        .italic()
                        .foregroundColor(Ink.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(36)
                }
            }
            .padding(24)
        }
        .frame(maxHeight: .infinity)
    }

    /// Build an `AttributedString` from a podcast description: paragraph-
    /// segmented (existing logic), then run through `NSDataDetector` to
    /// promote bare URLs (`https://…`, `www.…`) to live `.link`
    /// attributes. SwiftUI's `Text(AttributedString)` handles the click
    /// → open behaviour for free.
    private func linkifiedDescription(_ raw: String) -> AttributedString {
        let segmented = Fmt.segmented(raw)
        let mut = NSMutableAttributedString(string: segmented)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: mut.length)
            detector.enumerateMatches(in: segmented, options: [], range: range) { match, _, _ in
                guard let match, let url = match.url else { return }
                mut.addAttribute(.link, value: url, range: match.range)
            }
        }
        return AttributedString(mut)
    }

    @ViewBuilder
    private func highlightsTab(ep: Episode) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if ep.highlights.isEmpty {
                    Text(t("No highlights yet. Right-click any transcript line to save it as a highlight.", lang))
                        .font(.serif(15))
                        .italic()
                        .foregroundColor(Ink.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(36)
                }
                ForEach(ep.highlights.sorted(by: { $0.createdAt > $1.createdAt })) { h in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 13))
                            .foregroundColor(accent)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\"\(h.quote)\"")
                                .font(.serif(17))
                                .italic()
                                .foregroundColor(Ink.primary)
                                .lineSpacing(3)
                            HStack(spacing: 12) {
                                Button {
                                    if store.player.currentEpisodeID != ep.id { store.startPlaying(ep) }
                                    store.player.seek(to: h.at)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "play.fill").font(.system(size: 9))
                                        Text(Fmt.time(h.at))
                                    }
                                }
                                .buttonStyle(TextButtonStyle())
                                Button("Remove") {
                                    store.deleteHighlight(h)
                                }
                                .buttonStyle(TextButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(24)
        }
        .frame(maxHeight: .infinity)
    }

    /// Truncate a sorted-by-t streaming list to the longest contiguous
    /// prefix — useful while transcription is still streaming, so users
    /// see lines fill in linearly from the start rather than scattered
    /// across the timeline as parallel VAD workers report out of order.
    ///
    /// Threshold tuning: 22s sits comfortably under the default 30s
    /// chunk window (so a missing chunk's gap correctly blocks the
    /// display) while leaving enough room for natural in-chunk silences
    /// — long conversational pauses, theme-music interludes, breath
    /// gaps in slow podcasts. The earlier 8s threshold was too tight:
    /// any 8-30s in-chunk silence would falsely halt the display at a
    /// position like "15:37" with the rest of the chunk already decoded.
    ///
    /// If the prefix is artificially truncated by a still-decoding gap,
    /// the cut content reappears once `transcribing == false` (caller
    /// shows the full cached list then).
    private func contiguousPrefix(
        of sorted: [StreamLine],
        maxGapSeconds: Double = 22
    ) -> [StreamLine] {
        guard let first = sorted.first else { return [] }
        // If the earliest emitted line is already deep into the audio
        // (chunks 0..N haven't reported back, but chunk N+k has), don't
        // render a "transcript" that secretly skips the opening minute.
        // 45s buffer covers normal VAD-stripped intros without false
        // positives on legit late starts.
        if first.t > 45 { return [] }
        var out: [StreamLine] = [first]
        var prevT = first.t
        for line in sorted.dropFirst() {
            if line.t - prevT > maxGapSeconds { break }
            out.append(line)
            prevT = line.t
        }
        return out
    }

    // MARK: - AI Inspector

    @ViewBuilder
    private func aiInspector(ep: Episode, show: Show) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed top — header row + tab pill bar. Stays in place
            // regardless of which pane is selected or how long the
            // content is.
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(accent)
                EyebrowText(text: "Steve · listening")
                Spacer()
                Text(modelShortName())
                    .font(.mono(10))
                    .foregroundColor(Ink.tertiary)
            }
            .padding(.bottom, 14)

            PillBar(
                items: [
                    (AITab.summary,   t("Summary", lang)),
                    (AITab.takeaways, t("Takeaways", lang)),
                    (AITab.ask,       t("Ask", lang)),
                ],
                selection: $aiTab
            )
            .padding(.bottom, 16)

            // Scrollable pane content. Without this the takeaways list
            // (10-20+ items on dense episodes) extended the panel past
            // the viewport and forced the outer GlassScroll to scroll
            // — which fought any in-flight animations on the page and
            // produced visible jitter. Now: panel is locked to the
            // same height as the left tabs card, content scrolls
            // internally.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !ep.transcribed {
                        Text(t("Transcribe first to enable AI.", lang))
                            .font(.serif(14))
                            .italic()
                            .foregroundColor(Ink.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        switch aiTab {
                        case .summary: summaryPane(ep: ep, show: show)
                        case .takeaways: takeawaysPane(ep: ep, show: show)
                        case .ask: askPane(ep: ep)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Small bottom pad so the last item doesn't kiss the
                // glass edge when scrolled to the bottom.
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .padding(22)
        .glass(.panel)
        // Match the left tabs card's height so the two columns line
        // up. The inner ScrollView soaks up any overflow.
        .frame(height: tabContentHeight)
    }

    /// AI provider config for the *summary* operations. Resolves provider,
    /// key, model, and base URL from `AppSettings.summaryProvider`.
    private var summaryConfig: AIClientConfig {
        AIClientConfig(settings: store.settings)
    }

    /// True when the active summary provider has both a key and a model set.
    /// Replaces the old `anthropicKey != nil` gating throughout the AI panes.
    private var summaryConfigured: Bool {
        !summaryConfig.apiKey.isEmpty && !summaryConfig.model.isEmpty
    }

    private func modelShortName() -> String {
        let m = summaryConfig.model
        if m.contains("haiku")  { return "haiku" }
        if m.contains("sonnet") { return "sonnet" }
        if m.contains("opus")   { return "opus" }
        if m.contains("flash")  { return "flash" }
        if m.contains("pro")    { return "pro" }
        if m.contains("mini")   { return "mini" }
        // Final fallback: trim provider/version noise. e.g.
        // "gpt-4o-mini" → "gpt-4o", "deepseek-chat" → "deepseek"
        let parts = m.split(separator: "-")
        return parts.prefix(2).joined(separator: "-")
    }

    @ViewBuilder
    private func summaryPane(ep: Episode, show: Show) -> some View {
        if analyzing && (ep.aiSummary?.isEmpty ?? true) {
            HStack(spacing: 6) {
                Text(t("Analyzing", lang)).italic()
                Text("…")
            }
            .font(.serif(14))
            .foregroundColor(Ink.tertiary)
        } else if let summary = ep.aiSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(summary)
                    .font(.serif(16))
                    .foregroundColor(Ink.primary)
                    .lineSpacing(4)
                    .padding(.bottom, 14)
                if let concepts = ep.aiConcepts, !concepts.isEmpty {
                    EyebrowText(text: "Concepts surfaced").padding(.bottom, 8)
                    FlowLayout(spacing: 6) {
                        ForEach(concepts, id: \.self) { c in
                            Text(c)
                                .font(.sans(12, weight: .medium))
                                .foregroundColor(Ink.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.6))
                                        .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                                )
                        }
                    }
                }
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.vertical, 16)
                Button {
                    runAnalysis(ep: ep, show: show)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        Text(analyzing ? "Re-analyzing…" : "Re-analyze")
                    }
                }
                .buttonStyle(TextButtonStyle())
                .disabled(analyzing || !summaryConfigured)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(summaryConfigured
                     ? "Run analysis to extract a summary, takeaways, and concepts."
                     : "Add your \(summaryConfig.provider.displayName) key in Settings to enable AI.")
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                Button {
                    if !summaryConfigured {
                        store.navigate(to: .settings)
                    } else {
                        runAnalysis(ep: ep, show: show)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 11))
                        Text("\(t("Analyze with", lang)) \(summaryConfig.provider.displayName)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func takeawaysPane(ep: Episode, show: Show) -> some View {
        if analyzing && (ep.aiTakeaways?.isEmpty ?? true) {
            HStack(spacing: 4) {
                Text(t("Thinking", lang)).italic()
                Text("…")
            }
            .font(.serif(14))
            .foregroundColor(Ink.tertiary)
        } else if let ts = ep.aiTakeaways, !ts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ts.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", i + 1))
                            .font(.mono(10.5, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 18)
                            .padding(.top, 4)
                        Text(t)
                            .font(.serif(15))
                            .foregroundColor(Ink.primary)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        Rectangle()
                            .fill(i < ts.count - 1 ? Color.black.opacity(0.05) : .clear)
                            .frame(height: 1),
                        alignment: .bottom
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(summaryConfigured
                     ? "Run analysis to surface key takeaways."
                     : "Add your \(summaryConfig.provider.displayName) key in Settings to enable AI.")
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                Button {
                    if !summaryConfigured {
                        store.navigate(to: .settings)
                    } else {
                        runAnalysis(ep: ep, show: show)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 11))
                        Text("\(t("Analyze with", lang)) \(summaryConfig.provider.displayName)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func askPane(ep: Episode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundColor(accent).font(.system(size: 11))
                TextField(askPlaceholder(ep: ep), text: $askValue)
                    .textFieldStyle(.plain)
                    .font(.sans(13.5))
                    .onSubmit {
                        runAsk(ep: ep)
                    }
                    .disabled(!canAsk(ep: ep))
                Button {
                    runAsk(ep: ep)
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10))
                }
                .buttonStyle(PlayMiniStyle())
                .disabled(!canAsk(ep: ep) || askValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04))
            )

            if suggestionsLoading && suggestedQuestions.isEmpty {
                // Skeleton chips while the first suggestion fetch lands —
                // keeps the layout from jumping when results arrive.
                FlowLayout(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: CGFloat.random(in: 120...190), height: 24)
                            .redacted(reason: .placeholder)
                    }
                }
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(currentSuggestions(ep: ep), id: \.self) { q in
                        Button {
                            askValue = q
                            runAsk(ep: ep)
                        } label: {
                            Text(q)
                                .font(.sans(12, weight: .medium))
                                .foregroundColor(Ink.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.04))
                                        .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAsk(ep: ep))
                    }
                }
            }

            if askLoading {
                HStack(spacing: 4) {
                    Text(t("Thinking", lang)).italic()
                    Text("…")
                }
                .font(.serif(14))
                .foregroundColor(Ink.tertiary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.05), lineWidth: 1))
                )
            } else if let answer = askAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowText(text: "Answer")
                    Text(answer)
                        .font(.serif(15))
                        .foregroundColor(Ink.primary)
                        .lineSpacing(4)
                    if !askCitations.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(askCitations.enumerated()), id: \.offset) { _, c in
                                Button {
                                    if store.player.currentEpisodeID != ep.id { store.startPlaying(ep) }
                                    store.player.seek(to: c.t)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "play.fill").font(.system(size: 8))
                                        Text(Fmt.time(c.t))
                                    }
                                    .font(.mono(10.5))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(accent.opacity(0.1)))
                                    .foregroundColor(Brand.orange700)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.05), lineWidth: 1))
                )
            } else if let err = askError {
                Text(err)
                    .font(.sans(12))
                    .foregroundColor(Danger.primary)
            }
        }
        .onAppear { loadSuggestionsIfNeeded(ep: ep) }
        // When the analysis output changes (summary lands, user re-runs
        // analysis after editing transcript, etc.), refetch with the
        // sharper grounding.
        .onChange(of: ep.aiSummary) { _, _ in loadSuggestionsIfNeeded(ep: ep) }
        .onChange(of: ep.aiTakeaways) { _, _ in loadSuggestionsIfNeeded(ep: ep) }
    }

    private func askPlaceholder(ep: Episode) -> String {
        if !summaryConfigured {
            return "Add your \(summaryConfig.provider.displayName) key in Settings"
        }
        if ep.transcriptLines.isEmpty {
            return "Transcribe first"
        }
        return "Ask anything about this episode…"
    }

    private func canAsk(ep: Episode) -> Bool {
        summaryConfigured && !ep.transcriptLines.isEmpty
    }

    // MARK: - Actions

    private func isPlaying(_ ep: Episode) -> Bool {
        store.player.currentEpisodeID == ep.id && store.player.isPlaying
    }

    /// Thin wrapper. Real download lives in `DownloadStore` so progress
    /// survives the user navigating away from this page.
    private func removeDownload() {
        guard let ep = episodes.first else { return }
        downloads.removeDownload(episode: ep, ctx: modelContext)
        store.toast("Download removed")
    }

    /// Thin wrapper. Real pipeline lives in `TranscribeStore` (which
    /// internally drives `DownloadStore` for the audio fetch stage).
    private func startTranscribe(ep: Episode) {
        // Cloud requires an OpenAI key — bounce to settings if missing.
        if store.settings.transcribeEngine != "local" {
            if (store.settings.openaiKey ?? "").isEmpty {
                store.toast("Add your OpenAI API key in Settings to transcribe")
                store.navigate(to: .settings)
                return
            }
        }
        // Jump to the transcript tab so the user sees lines stream in
        // as they're decoded — no need to manually switch over after
        // pressing Transcribe. Retry from the error row also wants this.
        tab = .transcript
        transcribes.startTranscribe(
            episode: ep,
            settings: store.settings,
            ctx: modelContext,
            onAnalyze: { [self] ep in
                if summaryConfigured, let show = ep.show {
                    runAnalysis(ep: ep, show: show)
                }
            },
            toast: { msg in store.toast(msg) }
        )
    }

    private func runAnalysis(ep: Episode, show: Show) {
        guard summaryConfigured else {
            store.toast("Add your \(summaryConfig.provider.displayName) key in Settings")
            store.navigate(to: .settings)
            return
        }
        guard !ep.transcriptLines.isEmpty else {
            store.toast("Transcribe first")
            return
        }
        let cfg = summaryConfig
        analyzing = true
        Task { @MainActor in
            do {
                let texts = ep.sortedTranscriptLines.map { $0.text }
                let r = try await AIService.analyze(
                    transcript: texts,
                    episodeTitle: ep.title,
                    showTitle: show.title,
                    config: cfg
                )
                ep.aiSummary = r.summary
                ep.aiTakeaways = r.takeaways
                ep.aiConcepts = r.concepts.map { $0.name }
                try? modelContext.save()
                store.rebuildConcepts()
                store.toast("AI analysis ready")
            } catch {
                store.toast("AI failed: \(error.localizedDescription)")
            }
            analyzing = false
        }
    }

    private func runAsk(ep: Episode) {
        let q = askValue.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, canAsk(ep: ep) else { return }
        let cfg = summaryConfig
        askLoading = true
        askAnswer = nil
        askCitations = []
        askError = nil
        Task { @MainActor in
            do {
                let lines = ep.sortedTranscriptLines
                let pairs: [(index: Int, t: Double, text: String)] = lines.enumerated().map { (i, l) in
                    (i, l.t, l.text)
                }
                let r = try await AIService.ask(
                    question: q,
                    episodeTitle: ep.title,
                    lines: pairs,
                    config: cfg
                )
                askAnswer = r.answer
                askCitations = r.citations.map { (line: $0.line, t: $0.t) }
            } catch {
                askError = error.localizedDescription
            }
            askLoading = false
        }
    }

    /// Stable identity for "the current state of suggestions" — episode id
    /// plus a hash of the summary so we refetch once the analysis lands
    /// (a richer set of questions), but don't keep refetching on every tab
    /// switch when nothing has changed.
    private func suggestionsKey(for ep: Episode) -> String {
        let summaryHash = (ep.aiSummary ?? "").hashValue
        let takeawaysHash = (ep.aiTakeaways ?? []).joined(separator: "|").hashValue
        return "\(ep.id):\(summaryHash):\(takeawaysHash)"
    }

    /// Fallback suggestions for when the AI hasn't produced episode-specific
    /// prompts yet (or AI is unconfigured). Translated to the current
    /// app language.
    private var fallbackSuggestions: [String] {
        [
            t("What's the main argument?", lang),
            t("Summarize in one paragraph", lang),
            t("What are the surprising claims?", lang)
        ]
    }

    private func currentSuggestions(ep: Episode) -> [String] {
        suggestedQuestions.isEmpty ? fallbackSuggestions : suggestedQuestions
    }

    /// Fetch content-aware suggestions when the user lands on the Ask tab
    /// (or whenever the analysis output changes). Cheap to call repeatedly —
    /// `suggestionsLoadedKey` short-circuits redundant work.
    private func loadSuggestionsIfNeeded(ep: Episode) {
        guard summaryConfigured, !ep.transcriptLines.isEmpty else { return }
        let key = suggestionsKey(for: ep)
        if suggestionsLoadedKey == key { return }
        if suggestionsLoading { return }

        // Optimistically mark this key as "in flight" so a second trigger
        // (tab toggle, analysis completion racing) doesn't kick off twice.
        suggestionsLoadedKey = key
        suggestionsLoading = true
        let cfg = summaryConfig
        let texts = ep.sortedTranscriptLines.map { $0.text }
        let summary = ep.aiSummary
        let takeaways = ep.aiTakeaways ?? []
        let showTitle = ep.show?.title ?? ""
        let episodeTitle = ep.title

        Task { @MainActor in
            do {
                let qs = try await AIService.suggestQuestions(
                    transcript: texts,
                    summary: summary,
                    takeaways: takeaways,
                    episodeTitle: episodeTitle,
                    showTitle: showTitle,
                    config: cfg
                )
                // Only swap in if the episode + analysis we requested for is
                // still the relevant one (user could have navigated away).
                if suggestionsLoadedKey == key {
                    suggestedQuestions = qs
                }
            } catch {
                // Silent fallback — the generic suggestions still render via
                // `currentSuggestions`. Clearing the key allows a retry next
                // time the user re-enters the tab.
                if suggestionsLoadedKey == key { suggestionsLoadedKey = nil }
            }
            suggestionsLoading = false
        }
    }

    private func deleteTranscript() {
        guard let ep = episodes.first else { return }
        for line in ep.transcriptLines { modelContext.delete(line) }
        ep.transcribed = false
        ep.transcribedAt = nil
        ep.aiSummary = nil
        ep.aiTakeaways = nil
        ep.aiConcepts = nil
        try? modelContext.save()
        store.rebuildConcepts()
    }

}

/// Equatable so that on every player tick (which only flips `isActive` for
/// the previously-active row and the newly-active row), SwiftUI skips
/// re-rendering every other row in the transcript. Otherwise the entire
/// ForEach body re-evaluates every 0.5s and the highlight-update feels sticky.
private struct TranscriptRow: View, Equatable {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    let time: Double
    let speaker: String?
    let text: String
    let isActive: Bool
    let onTap: () -> Void
    /// Save the line as a highlight. Hooked up to a right-click context
    /// menu — replaces the dead bookmark button that used to sit in the
    /// header and only worked when the player happened to be at this
    /// timestamp. Per-line save is way more discoverable.
    let onSaveHighlight: () -> Void

    static func == (lhs: TranscriptRow, rhs: TranscriptRow) -> Bool {
        lhs.time == rhs.time
            && lhs.text == rhs.text
            && lhs.speaker == rhs.speaker
            && lhs.isActive == rhs.isActive
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.time(time))
                        .font(.mono(10.5))
                        .foregroundColor(Ink.tertiary)
                    if let speaker {
                        Text(speaker)
                            .font(.sans(11.5, weight: .semibold))
                            .foregroundColor(Ink.primary)
                    }
                }
                .frame(width: 110, alignment: .leading)
                .padding(.leading, 8)
                .overlay(
                    Rectangle().fill(isActive ? accent : .clear).frame(width: 2),
                    alignment: .leading
                )
                Text(text)
                    .font(.serif(16))
                    .foregroundColor(isActive ? Ink.primary : Ink.secondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? accent.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSaveHighlight()
            } label: {
                Label(t("Save highlight", lang), systemImage: "bookmark")
            }
        }
    }
}

struct DotPulse: View {
    @Environment(\.brandAccent) private var accent: Color
    @State private var scale: CGFloat = 0.85
    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.1 }
    }
}

// MARK: - Transcription banner + skeleton

/// Heads-up status pill while a transcribe job is running. Shows the
/// current pipeline stage (fetching / loading model / transcribing /
/// tagging speakers), a percentage, and a thin progress bar.
/// Replaces the previous bare "STREAMING · whisper-1" text row.
struct TranscribingBanner: View {
    let stage: TranscribeJob.Stage
    let progress: Double
    let modelLabel: String
    let accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    @State private var shimmerX: CGFloat = -200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                DotPulse()
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.mono(11, weight: .bold))
                        .tracking(0.7)
                        .foregroundColor(accent)
                    Text(subtitle)
                        .font(.sans(11))
                        .foregroundColor(Ink.tertiary)
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.mono(11, weight: .semibold))
                    .foregroundColor(Ink.secondary)
                    .contentTransition(.numericText(value: progress))
                    .animation(.easeOut(duration: 0.4), value: progress)
            }

            // Slim progress bar at the bottom of the banner. Acts as
            // overflow channel for the percentage on the right — both
            // show the same number, but visually one is a moving line.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.06))
                        .frame(height: 3)
                    Capsule().fill(accent)
                        .frame(width: max(0, geo.size.width * progress), height: 3)
                        .animation(.easeOut(duration: 0.3), value: progress)
                    // Sheen sweeping across the filled portion.
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 80, height: 3)
                        .offset(x: shimmerX)
                        .mask(
                            Capsule()
                                .frame(width: max(0, geo.size.width * progress), height: 3)
                        )
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.opacity(0.15), lineWidth: 0.5)
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerX = 320
            }
        }
    }

    private var headline: String {
        switch stage {
        case .fetchingAudio:     return "FETCHING AUDIO"
        case .loadingModel:      return "LOADING MODEL · \(modelLabel)"
        case .downloadingModel:  return "DOWNLOADING MODEL · \(modelLabel)"
        case .transcribing:      return "TRANSCRIBING · \(modelLabel)"
        case .finalizing:        return "FINALIZING"
        }
    }
    private var subtitle: String {
        switch stage {
        case .fetchingAudio:
            return t("Getting the audio file ready", lang)
        case .loadingModel:
            return t("Warming up the model — first run takes a moment", lang)
        case .downloadingModel:
            return t("Downloading the model from the network", lang)
        case .transcribing:
            return t("Decoding speech, line by line", lang)
        case .finalizing:
            return t("Saving transcript", lang)
        }
    }
}

/// Skeleton row that mirrors `TranscriptRow`'s layout — time + speaker
/// stub on the left, two rounded "text" bars on the right — with a
/// continuous shimmer sweeping across to communicate "still working".
struct TranscriptLineSkeleton: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                bar(width: 44, height: 9)
                bar(width: 60, height: 9)
            }
            .frame(width: 110, alignment: .leading)
            .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 7) {
                bar(width: nil, height: 11)
                bar(width: nil, height: 11, widthFraction: 0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 12)
        .opacity(0.85)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    /// One shimmer bar. `width` pins an exact width (used for the
    /// timestamp / speaker stubs); `widthFraction` makes the bar fill
    /// a fraction of the available width (text lines, where we want
    /// the second line to look slightly shorter than the first).
    @ViewBuilder
    private func bar(width: CGFloat?, height: CGFloat, widthFraction: CGFloat = 1.0) -> some View {
        GeometryReader { geo in
            let w = width ?? (geo.size.width * widthFraction)
            ZStack {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.clear,
                                 Color.white.opacity(0.6),
                                 .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .offset(x: -w + (2 * w) * phase)
                    .mask(
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    )
            }
            .frame(width: w, height: height)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), frames)
    }
}
