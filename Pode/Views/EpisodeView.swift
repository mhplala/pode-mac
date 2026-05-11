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
    @State private var pickerSelection: LocalWhisperModel = .balanced

    @State private var askValue: String = ""
    @State private var askLoading: Bool = false
    @State private var askAnswer: String? = nil
    @State private var askCitations: [(line: Int, t: Double)] = []
    @State private var askError: String? = nil

    @State private var confirmDeleteTranscript = false
    @State private var confirmRemoveDownload = false

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
                .onAppear { tabContentHeight = height }
                .onChange(of: geo.size.height) { _, _ in
                    tabContentHeight = height
                }
                // Back button stays pinned at the page's top-left
                // regardless of scroll position — sits above the
                // GlassScroll so it never disappears as the user
                // scrolls long descriptions / transcripts.
                .overlay(alignment: .topLeading) {
                    Button {
                        store.view = .listenNow
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
        GlassScroll {
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
                    .padding(.bottom, 140)
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
        }
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
            pickerSelection = LocalWhisperModel(rawValue: store.settings.localWhisperModel) ?? .balanced
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
                        if m == .balanced {
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
                    HStack(spacing: 10) {
                        DotPulse()
                        Text(job.stage == .fetchingAudio
                             ? "FETCHING AUDIO"
                             : "STREAMING · \(store.settings.whisperModel)")
                            .font(.mono(11, weight: .semibold))
                            .tracking(0.7)
                            .foregroundColor(accent)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 16)
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 1)
                            .padding(.bottom, 14),
                        alignment: .bottom
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }

                let sorted = ep.sortedTranscriptLines
                let activeIdx = activeIndex(in: sorted, ep: ep)
                ForEach(Array(sorted.enumerated()), id: \.element.lineIndex) { i, line in
                    TranscriptRow(
                        time: line.t,
                        speaker: line.speaker,
                        text: line.text,
                        isActive: i == activeIdx,
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
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, ep.transcriptLines.isEmpty ? 0 : 24)
        }
        .frame(height: tabContentHeight)
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
        .frame(height: tabContentHeight)
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
        .frame(height: tabContentHeight)
    }

    private func activeIndex(in sorted: [TranscriptLineModel], ep: Episode) -> Int {
        guard store.player.currentEpisodeID == ep.id else { return -1 }
        let now = store.player.currentTime
        return sorted.lastIndex(where: { now >= $0.t }) ?? -1
    }

    // MARK: - AI Inspector

    @ViewBuilder
    private func aiInspector(ep: Episode, show: Show) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .padding(22)
        .glass(.panel)
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
                        store.view = .settings
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
                        store.view = .settings
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

            FlowLayout(spacing: 6) {
                ForEach(["What's the main argument?", "Summarize in one paragraph", "What are the surprising claims?"], id: \.self) { q in
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
                store.view = .settings
                return
            }
        }
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
            store.view = .settings
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
