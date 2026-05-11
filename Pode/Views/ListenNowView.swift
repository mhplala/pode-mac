import SwiftUI
import SwiftData

struct ListenNowView: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Query(sort: [SortDescriptor(\Show.addedAt, order: .reverse)]) private var shows: [Show]
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var episodes: [Episode]
    /// Live queue. Skip the head (currently-playing) when rendering the
    /// "Up next" section — the head is shown in the player dock instead.
    @Query(sort: [SortDescriptor(\QueueItem.position, order: .forward)])
    private var queue: [QueueItem]

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: Fmt.date(.now))
                    .padding(.bottom, 10)

                // Greeting
                Group {
                    Text(greeting()) +
                    Text(", ") +
                    Text(userName())
                        .italic()
                        .foregroundColor(accent) +
                    Text(".")
                }
                .font(.serif(56, weight: .medium))
                .foregroundColor(Ink.primary)
                .lineSpacing(-6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 28)

                if shows.isEmpty {
                    emptyState
                } else {
                    if let featured = featuredEpisode() {
                        FeaturedCard(episode: featured)
                            .padding(.bottom, 32)
                    }

                    let inProg = inProgress()
                    if !inProg.isEmpty {
                        SectionHeader(eyebrow: t("Continue Listening", lang),
                                      title:   t("In progress", lang))
                            .padding(.bottom, 18)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                            ForEach(inProg.prefix(3)) { ep in
                                InProgressCard(episode: ep)
                            }
                        }
                        .padding(.bottom, 36)
                    }

                    // Real queue. Head = currently playing (skipped here —
                    // it's shown in the player dock); the rest is "Up next".
                    let upcoming = Array(queue.dropFirst())
                    if !upcoming.isEmpty {
                        SectionHeader(
                            eyebrow: t("Queue", lang),
                            title:   t("Up next", lang),
                            action: AnyView(
                                Button {
                                    store.clearQueue()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10))
                                        Text(t("Clear queue", lang))
                                    }
                                }
                                .buttonStyle(GhostSmallButtonStyle())
                            )
                        )
                        .padding(.bottom, 18)
                        VStack(spacing: 0) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { i, item in
                                if let ep = item.episode {
                                    QueueRow(
                                        index: i + 1,
                                        episode: ep,
                                        isFirst: i == 0,
                                        isLast: i == upcoming.count - 1,
                                        moveUp: { moveItem(item, in: queue, by: -1) },
                                        moveDown: { moveItem(item, in: queue, by: +1) },
                                        remove: { store.removeFromQueue(episodeID: ep.id) }
                                    )
                                }
                            }
                        }
                        .padding(6)
                        .glass(.panel)
                        .padding(.bottom, 36)
                    }

                    SectionHeader(eyebrow: t("Your Shows", lang),
                                  title:   t("Recently updated", lang))
                        .padding(.bottom, 18)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 6), spacing: 16) {
                        ForEach(shows.prefix(6)) { show in
                            ShowTile(show: show)
                        }
                    }
                }
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Text(t("Nothing here yet. Browse the directory, paste a feed URL, or search for a show.", lang))
                .font(.serif(19))
                .italic()
                .foregroundColor(Ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .lineSpacing(4)

            HStack(spacing: 10) {
                Button {
                    store.view = .browse
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 13))
                        Text(t("Browse podcasts", lang))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Settings") { store.view = .settings }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glass(.panel)
    }

    /// Featured hero card. Prefers whatever the user most recently
    /// promoted to the top of the play queue — that's `queue.first`,
    /// since `startPlaying` always moves the clicked episode to the
    /// queue head. Falls back to "first in-progress, else newest" only
    /// when the queue is empty (e.g. brand-new install, or after Clear).
    private func featuredEpisode() -> Episode? {
        if let head = queue.first?.episode { return head }
        if let inProg = episodes.first(where: { $0.played > 0 && $0.played < 1 }) { return inProg }
        return episodes.first
    }

    private func inProgress() -> [Episode] {
        episodes.filter { $0.played > 0 && $0.played < 1 }
    }

    /// Move a queue item up or down by one slot. Wraps the IndexSet/dest
    /// dance that `reorderQueue(from:to:)` expects from SwiftUI's
    /// `.onMove(perform:)` API. `delta` is +1 (down) or -1 (up).
    private func moveItem(_ item: QueueItem, in items: [QueueItem], by delta: Int) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = idx + delta
        guard target >= 0, target < items.count else { return }
        // SwiftUI's onMove convention: moving down requires destination = target + 1.
        let dest = delta > 0 ? target + 1 : target
        store.reorderQueue(from: IndexSet(integer: idx), to: dest)
    }

    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: .now)
        let key: String
        if h < 5         { key = "Good night" }
        else if h < 12   { key = "Good morning" }
        else if h < 18   { key = "Good afternoon" }
        else             { key = "Good evening" }
        return L10n.t(key, language: lang)
    }

    private func userName() -> String {
        store.settings.userName.isEmpty
            ? L10n.t("friend", language: lang)
            : store.settings.userName
    }
}

private struct FeaturedCard: View {
    @Environment(AppStore.self) private var store
    let episode: Episode

    var body: some View {
        if let show = episode.show {
            HStack(alignment: .top, spacing: 28) {
                CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 260, radius: 26)

                VStack(alignment: .leading, spacing: 0) {
                    EyebrowText(text: "Featured · \(show.title)")
                        .padding(.bottom, 8)
                    Text(episode.title)
                        .font(.serif(38, weight: .medium))
                        .foregroundColor(Ink.primary)
                        // Let the title wrap to as many lines as it needs.
                        // Previously the parent HStack only offered the
                        // Text its single-line intrinsic width's worth of
                        // wrapping space, so it truncated to "Op…" rather
                        // than wrapping. `frame(maxWidth: .infinity) +
                        // fixedSize(horizontal: false, vertical: true)`
                        // forces the layout to give it full row width and
                        // grow vertically instead of clipping horizontally.
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 14)

                    Text(HTMLStripper.toPlainText(
                        episode.aiSummary
                            ?? episode.episodeDescription
                            ?? "Open the episode to download, transcribe, and analyze."
                    ))
                        .font(.serif(14))
                        .italic()
                        .foregroundColor(Ink.secondary)
                        .lineSpacing(2)
                        // 4 lines was too short ("why so little text"),
                        // 12 was too tall (card grew past the cover).
                        // 6 fits a typical show-notes blurb without
                        // dwarfing the rest of Listen Now below.
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 16)

                    if let concepts = episode.aiConcepts, !concepts.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(concepts.prefix(4), id: \.self) { c in
                                Text(c)
                                    .font(.sans(12, weight: .medium))
                                    .foregroundColor(Ink.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(GlassBackground(variant: .chip))
                            }
                        }
                        .padding(.bottom, 16)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Button {
                            store.togglePlay(episode)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                Text(playLabel)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Open episode") {
                            store.view = .episode(episode.id)
                        }
                        .buttonStyle(GhostButtonStyle())

                        Spacer()
                        MetaMono(text: "\(Fmt.date(episode.pubDate)) · \(Fmt.dur(episode.duration))")
                    }
                }
                .padding(.vertical, 0)
            }
            .padding(28)
            .glass(.panel)
        }
    }

    private var isPlaying: Bool {
        store.player.currentEpisodeID == episode.id && store.player.isPlaying
    }
    private var playLabel: String {
        if isPlaying { return "Pause" }
        if episode.played > 0 {
            let remaining = max(0, episode.duration * (1 - episode.played))
            return "Resume · \(Fmt.time(remaining))"
        }
        return "Play"
    }
}

private struct InProgressCard: View {
    @Environment(AppStore.self) private var store
    let episode: Episode

    var body: some View {
        if let show = episode.show {
            Button {
                store.view = .episode(episode.id)
            } label: {
                HStack(spacing: 14) {
                    CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 64, radius: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(show.title.uppercased())
                            .font(.mono(11, weight: .semibold))
                            .tracking(0.7)
                            .foregroundColor(Ink.tertiary)
                            .lineLimit(1)
                            .padding(.bottom, 4)
                        Text(episode.title)
                            .font(.serif(16, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(2)
                            .padding(.bottom, 10)
                        HStack(spacing: 10) {
                            Button {
                                store.togglePlay(episode)
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(PlayMiniStyle())

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.black.opacity(0.08)).frame(height: 3)
                                    Capsule().fill(Ink.primary.opacity(0.85))
                                        .frame(width: geo.size.width * episode.played, height: 3)
                                }
                            }
                            .frame(height: 3)

                            Text("\(Fmt.time(episode.duration * (1 - episode.played))) left")
                                .font(.mono(10.5))
                                .foregroundColor(Ink.tertiary)
                        }
                    }
                }
                .padding(14)
                .glass(.tile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var isPlaying: Bool {
        store.player.currentEpisodeID == episode.id && store.player.isPlaying
    }
}

struct EpisodeRow: View {
    @Environment(AppStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @Environment(TranscribeStore.self) private var transcribes
    @Environment(\.appLanguage) private var lang: AppLanguage
    /// Live queue. Used to flip the "+ add" button into a "✓ in queue"
    /// state so the user knows the episode's already in their playlist.
    @Query(sort: [SortDescriptor(\QueueItem.position, order: .forward)])
    private var queue: [QueueItem]
    let index: Int?
    let episode: Episode
    /// Hide the show name in the subtitle when the row is rendered on a
    /// page that already identifies the show (e.g. ShowDetailView). Default
    /// `true` — useful in mixed-show lists like Library and Listen Now's
    /// Up Next queue.
    var showsShowName: Bool = true

    private var isInQueue: Bool {
        queue.contains(where: { $0.id == episode.id })
    }

    var body: some View {
        if let show = episode.show {
            Button {
                store.view = .episode(episode.id)
            } label: {
                HStack(spacing: 12) {
                    if let i = index {
                        Text(String(format: "%02d", i))
                            .font(.mono(11))
                            .foregroundColor(Ink.tertiary)
                            .frame(width: 22, alignment: .leading)
                    }
                    CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 40, radius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.serif(15, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(1)
                        // Subtitle: show name + date in mixed lists; just
                        // date on a single-show page (caller passes false).
                        Text(showsShowName
                             ? "\(show.title) · \(Fmt.date(episode.pubDate))"
                             : Fmt.date(episode.pubDate))
                            .font(.sans(12.5))
                            .foregroundColor(Ink.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if episode.transcribed {
                            BadgeSoft(icon: "text.alignleft", text: "Transcript")
                        }
                        if episode.downloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Success.primary)
                                .font(.system(size: 13))
                        }
                        // Live work indicator. Transcribe wins over plain
                        // download since transcribe's audio-fetch stage
                        // already encompasses the download.
                        if let job = transcribes.job(for: episode.id) {
                            JobRingIndicator(progress: job.overall,
                                             label: t(job.stageLabelKey, lang),
                                             tone: .accent)
                        } else if let job = downloads.job(for: episode.id), job.task != nil {
                            JobRingIndicator(progress: job.progress,
                                             label: t("Downloading", lang),
                                             tone: .accent)
                        }
                        MetaMono(text: Fmt.dur(episode.duration))

                        // Add-to-queue button. Toggles between "+" (add to
                        // tail) and "✓" (already queued — click removes).
                        // Right-click for richer options (Play next vs end).
                        Button {
                            if isInQueue {
                                store.removeFromQueue(episodeID: episode.id)
                            } else {
                                store.enqueue(episode: episode)
                            }
                        } label: {
                            Image(systemName: isInQueue ? "checkmark" : "plus")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(QueueIconStyle())
                        .help(isInQueue ? t("Remove from queue", lang) : t("Add to queue", lang))
                        .contextMenu {
                            Button {
                                store.playNext(episode: episode)
                            } label: {
                                Label(t("Play next", lang), systemImage: "text.insert")
                            }
                            Button {
                                store.enqueue(episode: episode)
                            } label: {
                                Label(t("Add to queue", lang), systemImage: "text.append")
                            }
                            if isInQueue {
                                Divider()
                                Button(role: .destructive) {
                                    store.removeFromQueue(episodeID: episode.id)
                                } label: {
                                    Label(t("Remove from queue", lang), systemImage: "minus.circle")
                                }
                            }
                        }

                        Button {
                            store.togglePlay(episode)
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlayMiniStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var isPlaying: Bool {
        store.player.currentEpisodeID == episode.id && store.player.isPlaying
    }
}

private struct ShowTile: View {
    @Environment(AppStore.self) private var store
    let show: Show

    var body: some View {
        Button {
            store.view = .show(show.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                CoverView(artworkUrl: show.artworkUrl, title: show.title,
                          size: 140, radius: 18, fill: true)
                Text(show.title)
                    .font(.serif(14, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                Text(show.host.isEmpty ? " " : show.host)
                    .font(.sans(11.5))
                    .foregroundColor(Ink.tertiary)
                    .lineLimit(1, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A queue row with reorder (up/down arrows) and remove (×) controls.
/// Differs from `EpisodeRow` mostly in its right-side affordances —
/// reorder/remove instead of badges + play.
struct QueueRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appLanguage) private var lang: AppLanguage
    let index: Int
    let episode: Episode
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        if let show = episode.show {
            Button {
                store.view = .episode(episode.id)
            } label: {
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index))
                        .font(.mono(11))
                        .foregroundColor(Ink.tertiary)
                        .frame(width: 22, alignment: .leading)
                    CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 40, radius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.serif(15, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(1)
                        Text("\(show.title) · \(Fmt.date(episode.pubDate))")
                            .font(.sans(12.5))
                            .foregroundColor(Ink.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        MetaMono(text: Fmt.dur(episode.duration))
                            .padding(.trailing, 4)
                        Button(action: moveUp) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(QueueIconStyle())
                        .disabled(isFirst)
                        .opacity(isFirst ? 0.3 : 1)

                        Button(action: moveDown) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(QueueIconStyle())
                        .disabled(isLast)
                        .opacity(isLast ? 0.3 : 1)

                        Button {
                            store.togglePlay(episode)
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlayMiniStyle())

                        Button(action: remove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(QueueIconStyle())
                        .help(t("Remove from queue", lang))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.04) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    private var isPlaying: Bool {
        store.player.currentEpisodeID == episode.id && store.player.isPlaying
    }
}

/// Compact progress ring + tooltip label. Shown on rows where the user
/// has a download or transcribe pipeline running. The label is a short
/// stage name ("Transcribing…") sized to fit next to the row's badges.
struct JobRingIndicator: View {
    enum Tone { case accent, neutral }
    let progress: Double  // 0..1
    let label: String
    let tone: Tone
    @Environment(\.brandAccent) private var accent: Color

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.10), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.03, min(1, progress)))
                    .stroke(tone == .accent ? accent : Ink.secondary,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
            .frame(width: 13, height: 13)
            Text(label)
                .font(.mono(10, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(Ink.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.white.opacity(0.05))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        )
        .help(label)
    }
}

/// Compact icon button for queue affordances (up/down/×). Matches the
/// hairline-glass pill look without the chunkier `PlayMiniStyle` halo.
struct QueueIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Ink.secondary)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.04))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            )
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    var action: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowText(text: eyebrow)
                Text(title)
                    .font(.serif(30, weight: .medium))
                    .foregroundColor(Ink.primary)
            }
            Spacer()
            if let action { action }
        }
    }
}
