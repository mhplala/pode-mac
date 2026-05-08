import SwiftUI
import SwiftData

struct EpisodeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    let episodeId: String
    @Query private var episodes: [Episode]

    enum EpTab: String, CaseIterable, Hashable { case transcript, description, highlights }
    enum AITab: String, CaseIterable, Hashable { case summary, takeaways, ask }

    @State private var tab: EpTab = .transcript
    @State private var aiTab: AITab = .summary

    @State private var downloading: Bool = false
    @State private var downloadProgress: Double = 0  // 0..1
    @State private var downloadTotal: Int64 = 0
    @State private var downloadLoaded: Int64 = 0
    @State private var downloadStartedAt: Date? = nil
    @State private var downloadTask: Task<Void, Never>? = nil
    @State private var downloadError: String? = nil

    @State private var transcribing: Bool = false
    @State private var transcribeStage: String = ""
    @State private var transcribeError: String? = nil
    @State private var analyzing: Bool = false

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    store.view = .listenNow
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 11))
                        Text("Back")
                    }
                }
                .buttonStyle(TextButtonStyle())

                if let ep = episodes.first, let show = ep.show {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) {
                            headerCard(ep: ep, show: show)
                            tabsCard(ep: ep, show: show)
                        }
                        aiInspector(ep: ep, show: show)
                            .frame(width: 380)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                } else {
                    Text("Episode not found.")
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
        .alert("Delete transcript?", isPresented: $confirmDeleteTranscript) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteTranscript() }
        } message: {
            Text("AI summaries will be cleared too.")
        }
        .alert("Remove downloaded audio?", isPresented: $confirmRemoveDownload) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { removeDownload() }
        }
    }

    // MARK: - Header card

    @ViewBuilder
    private func headerCard(ep: Episode, show: Show) -> some View {
        HStack(alignment: .top, spacing: 22) {
            CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 140, radius: 14, playing: isPlaying(ep))
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
                            Text(isPlaying(ep) ? "Pause" : (ep.played > 0 ? "Resume" : "Play"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    downloadButton(ep: ep)
                    transcribeButton(ep: ep)

                    Spacer()

                    Button {
                        saveHighlight(ep: ep)
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .buttonStyle(IconBtnStyle())
                    .help("Save highlight at current position")
                    .disabled(ep.transcriptLines.isEmpty)
                }
                .padding(.bottom, 16)

                if downloading || ep.downloaded {
                    progressBar(ep: ep)
                }

                if let downloadError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Danger.primary)
                            .font(.system(size: 11))
                            .padding(.top, 2)
                        Text(downloadError)
                            .font(.sans(12))
                            .foregroundColor(Danger.primary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            startDownload(ep: ep)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 10))
                                Text("Retry")
                            }
                        }
                        .buttonStyle(GhostSmallButtonStyle())
                    }
                    .padding(.top, 8)
                }

                if let transcribeError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Danger.primary)
                            .font(.system(size: 11))
                            .padding(.top, 2)
                        Text(transcribeError)
                            .font(.sans(12))
                            .foregroundColor(Danger.primary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            startTranscribe(ep: ep)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 10))
                                Text("Retry")
                            }
                        }
                        .buttonStyle(GhostSmallButtonStyle())
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(24)
        .glass(.panel)
    }

    @ViewBuilder
    private func downloadButton(ep: Episode) -> some View {
        Button {
            if downloading {
                downloadTask?.cancel()
                downloading = false
                return
            }
            if ep.downloaded {
                confirmRemoveDownload = true
                return
            }
            startDownload(ep: ep)
        } label: {
            HStack(spacing: 6) {
                if ep.downloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Success.primary)
                    Text("Downloaded")
                } else if downloading {
                    Text(downloadProgress > 0 ? "Cancel · \(Int(downloadProgress * 100))%" : "Cancel")
                } else {
                    Image(systemName: "arrow.down.circle")
                    Text("Download")
                }
            }
        }
        .buttonStyle(GhostButtonStyle())
    }

    @ViewBuilder
    private func transcribeButton(ep: Episode) -> some View {
        Button {
            if transcribing { return }
            startTranscribe(ep: ep)
        } label: {
            HStack(spacing: 6) {
                if ep.transcribed {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(Success.primary)
                    Text("Transcribed").foregroundColor(Success.primary)
                } else if transcribing {
                    DotPulse()
                    Text(transcribeStage == "fetching" ? "Fetching audio…" : "Transcribing…")
                } else {
                    Image(systemName: "text.alignleft")
                    Text("Transcribe")
                }
            }
        }
        .buttonStyle(GhostButtonStyle())
    }

    @ViewBuilder
    private func progressBar(ep: Episode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let pct = downloading
                    ? (downloadTotal > 0 ? Double(downloadLoaded) / Double(downloadTotal) : downloadProgress)
                    : (ep.downloaded ? 1.0 : 0.0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07)).frame(height: 6)
                    Capsule().fill(Brand.orange.opacity(0.85))
                        .frame(width: max(0, geo.size.width * pct), height: 6)
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                Text(progressLeftText(ep: ep))
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
                Spacer()
                Text(progressRightText(ep: ep))
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
            }
        }
    }

    private func progressLeftText(ep: Episode) -> String {
        if ep.downloaded {
            return "downloaded · \(Fmt.bytes(ep.audioSize))"
        }
        if !downloading { return "—" }
        // Live percent + bytes counters
        if downloadTotal > 0 {
            let loadedMB = Double(downloadLoaded) / 1_048_576
            let totalMB  = Double(downloadTotal) / 1_048_576
            return String(format: "%.1f / %.1f MB · %d%%",
                          loadedMB, totalMB, Int(downloadProgress * 100))
        }
        let loadedMB = Double(downloadLoaded) / 1_048_576
        return String(format: "%.1f MB", loadedMB)
    }

    private func progressRightText(ep: Episode) -> String {
        guard downloading else { return Fmt.dur(ep.duration) }
        // Speed + ETA derived from start time and bytes loaded
        guard let start = downloadStartedAt else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0.5, downloadLoaded > 0 else { return "starting…" }
        let bytesPerSecond = Double(downloadLoaded) / elapsed
        let speedMBs = bytesPerSecond / 1_048_576
        if downloadTotal > 0 {
            let remaining = Double(downloadTotal - downloadLoaded) / max(bytesPerSecond, 1)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(tab == t ? Color.black.opacity(0.06) : .clear)
                            )
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

    private func label(for t: EpTab, ep: Episode) -> String {
        switch t {
        case .transcript: return "Transcript"
        case .description: return "Description"
        case .highlights: return "Highlights · \(ep.highlights.count)"
        }
    }

    @ViewBuilder
    private func transcriptTab(ep: Episode) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if ep.transcriptLines.isEmpty && !transcribing {
                    VStack(spacing: 18) {
                        Text("No transcript yet. Generate one to enable AI summaries, search, and concept extraction.")
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
                                Text("Transcribe this episode")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(36)
                }
                if transcribing {
                    HStack(spacing: 10) {
                        DotPulse()
                        Text(transcribeStage == "fetching" ? "FETCHING AUDIO" : "STREAMING · \(store.settings.whisperModel)")
                            .font(.mono(11, weight: .semibold))
                            .tracking(0.7)
                            .foregroundColor(Brand.orange)
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
                    Button {
                        if store.player.currentEpisodeID != ep.id {
                            store.startPlaying(ep)
                        }
                        store.player.seek(to: line.t)
                    } label: {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.time(line.t))
                                    .font(.mono(10.5))
                                    .foregroundColor(Ink.tertiary)
                                if let speaker = line.speaker {
                                    Text(speaker)
                                        .font(.sans(11.5, weight: .semibold))
                                        .foregroundColor(Ink.primary)
                                }
                            }
                            .frame(width: 110, alignment: .leading)
                            .padding(.leading, 8)
                            .overlay(
                                Rectangle().fill(i == activeIdx ? Brand.orange : .clear).frame(width: 2),
                                alignment: .leading
                            )
                            Text(line.text)
                                .font(.serif(16))
                                .foregroundColor(i == activeIdx ? Ink.primary : Ink.secondary)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 8)
                        }
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(i == activeIdx ? Brand.orange.opacity(0.06) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, ep.transcriptLines.isEmpty ? 0 : 24)
        }
        .frame(maxHeight: 560)
    }

    @ViewBuilder
    private func descriptionTab(ep: Episode) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let desc = ep.episodeDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.serif(16))
                        .foregroundColor(Ink.secondary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No description in the feed.")
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
        .frame(maxHeight: 560)
    }

    @ViewBuilder
    private func highlightsTab(ep: Episode) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if ep.highlights.isEmpty {
                    Text("No highlights yet. Press the bookmark button while listening to save the line at the current position.")
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
                            .foregroundColor(Brand.orange)
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
                            .fill(Brand.orange.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(Brand.orange.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(24)
        }
        .frame(maxHeight: 560)
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
                    .foregroundColor(Brand.orange)
                EyebrowText(text: "Steve · listening")
                Spacer()
                Text(modelShortName())
                    .font(.mono(10))
                    .foregroundColor(Ink.tertiary)
            }
            .padding(.bottom, 14)

            PillBar(
                items: [(AITab.summary, "Summary"), (AITab.takeaways, "Takeaways"), (AITab.ask, "Ask")],
                selection: $aiTab
            )
            .padding(.bottom, 16)

            if !ep.transcribed {
                Text("Transcribe first to enable AI.")
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

    private func modelShortName() -> String {
        let m = store.settings.claudeModel
        if m.contains("haiku") { return "haiku" }
        if m.contains("sonnet") { return "sonnet" }
        if m.contains("opus") { return "opus" }
        return m
    }

    @ViewBuilder
    private func summaryPane(ep: Episode, show: Show) -> some View {
        if analyzing && (ep.aiSummary?.isEmpty ?? true) {
            HStack(spacing: 6) {
                Text("Analyzing").italic()
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
                .disabled(analyzing || store.settings.anthropicKey?.isEmpty != false)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.settings.anthropicKey?.isEmpty == false
                     ? "Run analysis to extract a summary, takeaways, and concepts."
                     : "Add your Anthropic API key in Settings to enable AI.")
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                Button {
                    if store.settings.anthropicKey?.isEmpty != false {
                        store.view = .settings
                    } else {
                        runAnalysis(ep: ep, show: show)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 11))
                        Text("Analyze with Claude")
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
                Text("Thinking").italic()
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
                            .foregroundColor(Brand.orange)
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
                Text(store.settings.anthropicKey?.isEmpty == false
                     ? "Run analysis to surface key takeaways."
                     : "Add your Anthropic API key in Settings to enable AI.")
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                Button {
                    if store.settings.anthropicKey?.isEmpty != false {
                        store.view = .settings
                    } else {
                        runAnalysis(ep: ep, show: show)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 11))
                        Text("Analyze with Claude")
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
                Image(systemName: "sparkles").foregroundColor(Brand.orange).font(.system(size: 11))
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
                    Text("Thinking").italic()
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
                                    .background(Capsule().fill(Brand.orange.opacity(0.1)))
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
        if store.settings.anthropicKey?.isEmpty != false {
            return "Add your Anthropic API key in Settings"
        }
        if ep.transcriptLines.isEmpty {
            return "Transcribe first"
        }
        return "Ask anything about this episode…"
    }

    private func canAsk(ep: Episode) -> Bool {
        store.settings.anthropicKey?.isEmpty == false && !ep.transcriptLines.isEmpty
    }

    // MARK: - Actions

    private func isPlaying(_ ep: Episode) -> Bool {
        store.player.currentEpisodeID == ep.id && store.player.isPlaying
    }

    private func startDownload(ep: Episode) {
        guard let url = URL(string: ep.audioUrl) else {
            downloadError = "Bad audio URL"
            return
        }
        downloadError = nil
        downloading = true
        downloadProgress = 0
        downloadTotal = 0
        downloadLoaded = 0
        downloadStartedAt = .now
        downloadTask = Task { @MainActor in
            do {
                let dest = try await AudioDownloader.download(from: url) { loaded, total in
                    Task { @MainActor in
                        downloadLoaded = loaded
                        downloadTotal = total
                        if total > 0 { downloadProgress = Double(loaded) / Double(total) }
                    }
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                ep.localFilePath = dest.path
                ep.downloaded = true
                ep.downloadedAt = .now
                if let size = attrs?[.size] as? NSNumber {
                    ep.audioSize = size.int64Value
                }
                try? modelContext.save()
                store.toast("Downloaded · \(Fmt.bytes(ep.audioSize))")
            } catch {
                if (error as? CancellationError) != nil || (error as NSError).code == NSURLErrorCancelled {
                    store.toast("Download cancelled")
                } else {
                    downloadError = humanizeDownloadError(error)
                }
            }
            downloading = false
            downloadProgress = 0
            downloadStartedAt = nil
        }
    }

    private func humanizeDownloadError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "Network timed out. Try again."
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection."
        case NSURLErrorNetworkConnectionLost:
            return "Connection lost mid-download. Tap retry."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Couldn't reach the host. The feed may be down."
        case NSURLErrorBadServerResponse:
            return "The server returned a bad response."
        case NSURLErrorDataNotAllowed:
            return "Downloads are blocked on this network."
        default:
            return error.localizedDescription
        }
    }

    private func removeDownload() {
        guard let ep = episodes.first else { return }
        if let path = ep.localFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        ep.localFilePath = nil
        ep.downloaded = false
        ep.downloadedAt = nil
        try? modelContext.save()
        store.toast("Download removed")
    }

    private func startTranscribe(ep: Episode) {
        guard let key = store.settings.openaiKey, !key.isEmpty else {
            store.toast("Add your OpenAI API key in Settings to transcribe")
            store.view = .settings
            return
        }
        transcribeError = nil
        transcribing = true
        transcribeStage = ""
        Task { @MainActor in
            do {
                let audioFileURL: URL
                if ep.downloaded, let path = ep.localFilePath, FileManager.default.fileExists(atPath: path) {
                    audioFileURL = URL(fileURLWithPath: path)
                } else {
                    transcribeStage = "fetching"
                    guard let url = URL(string: ep.audioUrl) else {
                        throw WhisperError.audioFetch("bad URL")
                    }
                    let dest = try await AudioDownloader.download(from: url)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                    ep.localFilePath = dest.path
                    ep.downloaded = true
                    ep.downloadedAt = .now
                    if let size = attrs?[.size] as? NSNumber {
                        ep.audioSize = size.int64Value
                    }
                    try? modelContext.save()
                    audioFileURL = dest
                }

                transcribeStage = ""
                let result = try await WhisperService.transcribe(
                    audioFileURL: audioFileURL,
                    apiKey: key,
                    model: store.settings.whisperModel
                )
                // Replace transcript lines
                for old in ep.transcriptLines { modelContext.delete(old) }
                for (idx, line) in result.lines.enumerated() {
                    let m = TranscriptLineModel(t: line.t, text: line.text, speaker: line.speaker, lineIndex: idx)
                    m.episode = ep
                    modelContext.insert(m)
                }
                ep.transcribed = true
                ep.transcribedAt = .now
                try? modelContext.save()
                store.toast("Transcribed · \(result.lines.count) segments")

                // Auto-run AI analysis if Anthropic key set
                if let aKey = store.settings.anthropicKey, !aKey.isEmpty, let show = ep.show {
                    runAnalysis(ep: ep, show: show)
                }
            } catch {
                if (error as? CancellationError) != nil {
                    store.toast("Transcription cancelled")
                } else {
                    transcribeError = "Transcribe failed: \(error.localizedDescription)"
                }
            }
            transcribing = false
            transcribeStage = ""
        }
    }

    private func runAnalysis(ep: Episode, show: Show) {
        guard let key = store.settings.anthropicKey, !key.isEmpty else {
            store.toast("Add your Anthropic API key in Settings")
            store.view = .settings
            return
        }
        guard !ep.transcriptLines.isEmpty else {
            store.toast("Transcribe first")
            return
        }
        analyzing = true
        Task { @MainActor in
            do {
                let texts = ep.sortedTranscriptLines.map { $0.text }
                let r = try await ClaudeService.analyze(
                    transcript: texts,
                    episodeTitle: ep.title,
                    showTitle: show.title,
                    apiKey: key,
                    model: store.settings.claudeModel
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
        guard !q.isEmpty, canAsk(ep: ep), let key = store.settings.anthropicKey else { return }
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
                let r = try await ClaudeService.ask(
                    question: q,
                    episodeTitle: ep.title,
                    lines: pairs,
                    apiKey: key,
                    model: store.settings.claudeModel
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

    private func saveHighlight(ep: Episode) {
        let now = store.player.currentTime
        let sorted = ep.sortedTranscriptLines
        guard let line = sorted.last(where: { now >= $0.t }) else {
            store.toast("No transcript line at this position")
            return
        }
        store.saveHighlight(episode: ep, at: line.t, quote: line.text)
    }
}

struct DotPulse: View {
    @State private var scale: CGFloat = 0.85
    var body: some View {
        Circle()
            .fill(Brand.orange)
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
