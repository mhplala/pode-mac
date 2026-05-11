import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Query(sort: [SortDescriptor(\Show.addedAt, order: .reverse)]) private var shows: [Show]
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var episodes: [Episode]

    enum LibraryTab: String, CaseIterable, Hashable {
        case shows, episodes, downloaded, transcripts
        var label: String {
            switch self {
            case .shows: return "Shows"
            case .episodes: return "Episodes"
            case .downloaded: return "Downloaded"
            case .transcripts: return "Transcripts"
            }
        }
    }
    @State private var tab: LibraryTab = .shows

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: t("Your collection", lang).uppercased())
                    .padding(.bottom, 10)
                Text(t("Library", lang))
                    .font(.serif(48, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 24)

                // No manual "Refresh feeds" button — the background timer
                // re-checks every 30 minutes (and once 5s after launch),
                // and `refreshShow` toasts when new episodes actually
                // arrive. Nothing for the user to do.
                PillBar(
                    items: LibraryTab.allCases.map { ($0, t($0.label, lang)) },
                    selection: $tab
                )
                .padding(.bottom, 24)

                if tab == .shows {
                    showsView
                } else {
                    episodesList
                }
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
    }

    private var showsView: some View {
        Group {
            if shows.isEmpty {
                VStack(spacing: 18) {
                    Text(t("No subscriptions yet.", lang))
                        .font(.serif(17))
                        .italic()
                        .foregroundColor(Ink.secondary)
                    Button {
                        store.goTo(.browse)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 13))
                            Text(t("Browse podcasts", lang))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .glass(.panel)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 22, alignment: .top)],
                    alignment: .leading,
                    spacing: 32
                ) {
                    ForEach(shows) { show in
                        Button {
                            store.navigate(to: .show(show.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                CoverView(artworkUrl: show.artworkUrl, title: show.title,
                                          size: 240, radius: 22, fill: true)
                                Text(show.title)
                                    .font(.serif(16, weight: .medium))
                                    .foregroundColor(Ink.primary)
                                    .lineLimit(2, reservesSpace: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 12)
                                Text(show.host.isEmpty ? " " : show.host)
                                    .font(.sans(12.5))
                                    .foregroundColor(Ink.tertiary)
                                    .lineLimit(1, reservesSpace: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 3)
                                if let recent = show.episodes.sorted(by: { $0.pubDate > $1.pubDate }).first {
                                    MetaMono(text: "↓ \(String(recent.title.prefix(28)))\(recent.title.count > 28 ? "…" : "")")
                                        .lineLimit(1)
                                        .padding(.top, 6)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var episodesList: some View {
        let filtered: [Episode] = {
            switch tab {
            case .downloaded: return episodes.filter { $0.downloaded }
            case .transcripts: return episodes.filter { $0.transcribed }
            default: return episodes
            }
        }()

        return Group {
            if filtered.isEmpty {
                Text(t(emptyText, lang))
                    .font(.serif(16))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .glass(.panel)
            } else {
                // LazyVStack so a Show with hundreds of episodes
                // doesn't materialize every EpisodeRow up front —
                // only the rows in the visible viewport (plus a
                // small overscroll buffer) get built. Massive win
                // on first-paint and on scroll for big libraries.
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { ep in
                        EpisodeRow(index: nil, episode: ep)
                    }
                }
                .padding(6)
                .glass(.panel)
            }
        }
    }

    private var emptyText: String {
        switch tab {
        case .downloaded: return "No downloads yet."
        case .transcripts: return "No transcripts yet."
        default: return "No episodes yet."
        }
    }
}

struct ShowDetailView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    let showId: String
    @Query private var shows: [Show]
    @State private var refreshing = false
    @State private var confirmRemove = false

    init(showId: String) {
        self.showId = showId
        _shows = Query(filter: #Predicate<Show> { $0.id == showId })
    }

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                // Spacer where the back button used to live — the actual
                // button is rendered as a fixed-position overlay below
                // so it stays visible as the user scrolls.
                Color.clear.frame(height: 32)

                if let show = shows.first {
                    HStack(alignment: .top, spacing: 26) {
                        CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 200, radius: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            EyebrowText(text: show.category ?? "Podcast").padding(.bottom, 6)
                            Text(show.title)
                                .font(.serif(36, weight: .medium))
                                .foregroundColor(Ink.primary)
                                .padding(.bottom, 8)
                            if !show.host.isEmpty {
                                Text(show.host)
                                    .font(.sans(14))
                                    .foregroundColor(Ink.secondary)
                                    .padding(.bottom, 14)
                            }
                            if let desc = show.showDescription, !desc.isEmpty {
                                Text(desc)
                                    .font(.serif(15))
                                    .foregroundColor(Ink.secondary)
                                    .lineSpacing(3)
                                    .lineLimit(4)
                                    .padding(.bottom, 16)
                            }
                            HStack(spacing: 8) {
                                // Primary action: play / resume. Picks the
                                // most-recently-played episode for this show
                                // (resumes from saved position) — falls back
                                // to the newest episode if none played yet.
                                if let target = playTarget(in: show) {
                                    Button {
                                        store.togglePlay(target.episode)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: playLabel(for: target).icon)
                                                .font(.system(size: 11))
                                            Text(playLabel(for: target).text)
                                                .lineLimit(1)
                                        }
                                        .frame(minWidth: 90)
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                }

                                // Manual per-show refresh button removed
                                // — auto-refresh covers it. Keeping the
                                // `refreshing` @State around for potential
                                // future "force refresh" affordance.
                                Button {
                                    confirmRemove = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                        Text(t("Unsubscribe", lang))
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())

                                Spacer()
                                MetaMono(text: "\(show.episodes.count) episodes")
                            }
                        }
                    }
                    .padding(28)
                    .glass(.panel)
                    .padding(.top, 12)
                    .padding(.bottom, 22)

                    let sortedEps = show.episodes.sorted { $0.pubDate > $1.pubDate }
                    if sortedEps.isEmpty {
                        Text(t("No episodes loaded yet — try refreshing.", lang))
                            .font(.serif(15))
                            .italic()
                            .foregroundColor(Ink.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                            .glass(.panel)
                    } else {
                        // LazyVStack — same reasoning as the library
                        // index list: a long-running show with 500+
                        // episodes used to materialize every row up
                        // front on first paint.
                        LazyVStack(spacing: 0) {
                            ForEach(sortedEps) { ep in
                                // On a single show's page the cover + page
                                // header already identify the show — skip
                                // the redundant show-name in the subtitle.
                                EpisodeRow(index: nil, episode: ep, showsShowName: false)
                            }
                        }
                        .padding(6)
                        .glass(.panel)
                    }
                } else {
                    Text(t("Show not found.", lang))
                        .font(.serif(16))
                        .italic()
                        .foregroundColor(Ink.tertiary)
                        .padding(.top, 32)
                }
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        // Pinned back button — stays put as the user scrolls long
        // episode lists. Wrapped in a glass chip so the label stays
        // legible against any content scrolling underneath.
        .overlay(alignment: .topLeading) {
            Button {
                store.back()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                    Text(t("Back to Library", lang))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundColor(Ink.secondary)
            .font(.sans(12.5, weight: .medium))
            .glass(.chip)
            .padding(.leading, 32)
            .padding(.top, 12)
        }
        .alert(t("Unsubscribe?", lang), isPresented: $confirmRemove) {
            Button(t("Cancel", lang), role: .cancel) {}
            Button(t("Unsubscribe", lang), role: .destructive) {
                store.unsubscribe(showId: showId)
                // Show is gone — drop the stale entry from the back
                // stack and root back to Library.
                store.goTo(.library)
            }
        } message: {
            Text(t("Episodes, transcripts and highlights for this show will be removed.", lang))
        }
    }

    /// Decide what the Play button on the show page should do, and which
    /// episode it targets. Three modes drive the label/icon:
    /// - resume:  the user has played some episode of this show before
    ///            and there's saved progress to continue from.
    /// - replay:  the user has played episodes but they're all finished —
    ///            re-start the most-recently-played one.
    /// - latest:  no episode has been played yet — play the newest.
    private struct PlayTarget {
        enum Mode { case resume, replay, latest }
        let episode: Episode
        let mode: Mode
    }

    private func playTarget(in show: Show) -> PlayTarget? {
        let eps = show.episodes
        guard !eps.isEmpty else { return nil }
        // Prefer the most-recently-played episode that still has progress.
        let played = eps.filter { $0.lastPlayedAt != nil }
        let mostRecent = played.max(by: {
            ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast)
        })
        if let m = mostRecent {
            // < 0.99 means there's still meaningful progress to resume.
            if m.played < 0.99 { return PlayTarget(episode: m, mode: .resume) }
            // Finished — replay it (user explicitly asked: play the "last one").
            return PlayTarget(episode: m, mode: .replay)
        }
        // Never played — newest by pubDate.
        let newest = eps.max(by: { $0.pubDate < $1.pubDate })!
        return PlayTarget(episode: newest, mode: .latest)
    }

    private func playLabel(for target: PlayTarget) -> (icon: String, text: String) {
        // Currently playing this exact episode? Show pause.
        if store.player.currentEpisodeID == target.episode.id, store.player.isPlaying {
            return ("pause.fill", t("Pause", lang))
        }
        switch target.mode {
        case .resume:
            let remaining = max(0, target.episode.duration * (1 - target.episode.played))
            return ("play.fill", "\(t("Resume", lang)) · \(Fmt.time(remaining))")
        case .replay:
            return ("play.fill", t("Replay", lang))
        case .latest:
            return ("play.fill", t("Play latest", lang))
        }
    }
}

