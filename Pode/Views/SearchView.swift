import SwiftUI
import SwiftData

/// Global search results — driven by the sidebar search field. Searches:
/// - subscribed shows (title / host)
/// - episodes (title / description)
/// - transcript lines (text)
/// - highlights (quote)
/// - Apple Podcasts (iTunes search) — visible as a button at the bottom
///   that pushes the user over to Browse with the query.
struct SearchView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(\.brandAccent) private var accent: Color
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    let query: String

    @Query(sort: [SortDescriptor(\Show.addedAt, order: .reverse)]) private var allShows: [Show]
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var allEpisodes: [Episode]
    /// Single queue fetch so EpisodeRow doesn't subscribe per row.
    @Query(sort: [SortDescriptor(\QueueItem.position, order: .forward)])
    private var queueItems: [QueueItem]
    // Transcript lines NO LONGER pulled into memory via @Query — for a
    // heavy user that's tens of thousands of rows materialised at view
    // init plus an O(n) lowercase+contains scan on every keystroke.
    // We now fetch only matches via a SwiftData predicate with a
    // fetchLimit, off the debounced query.
    @Query(sort: [SortDescriptor(\Highlight.createdAt, order: .reverse)]) private var allHighlights: [Highlight]

    /// Debounced version of `query`. Updated 280ms after the last
    /// keystroke. All filtering downstream reads `q` (this) — so
    /// typing fast doesn't trigger filter work on every character.
    @State private var debouncedQuery: String = ""
    @State private var debounceTask: Task<Void, Never>? = nil
    /// Transcript-line search results, materialised by `runLineSearch`
    /// after the debounce settles.
    @State private var matchedLinesState: [TranscriptLineModel] = []

    /// Lowercased trimmed search needle. Falls back to empty when
    /// debounce hasn't caught up yet.
    private var q: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private var matchedShows: [Show] {
        guard !q.isEmpty else { return [] }
        return allShows.filter {
            $0.title.lowercased().contains(q) || $0.host.lowercased().contains(q)
        }
    }
    private var matchedEpisodes: [Episode] {
        guard !q.isEmpty else { return [] }
        return allEpisodes.filter {
            $0.title.lowercased().contains(q)
            || ($0.episodeDescription?.lowercased().contains(q) ?? false)
        }
        .prefix(40)
        .map { $0 }
    }
    private var matchedLines: [TranscriptLineModel] { matchedLinesState }
    private var matchedHighlights: [Highlight] {
        guard !q.isEmpty else { return [] }
        return allHighlights.filter { $0.quote.lowercased().contains(q) }
    }

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: t("Search", lang).uppercased()).padding(.bottom, 10)
                Group {
                    Text("\"\(query)\"")
                        .italic()
                        .foregroundColor(accent)
                }
                .font(.serif(48, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 8)

                let totalLocal = matchedShows.count + matchedEpisodes.count + matchedLines.count + matchedHighlights.count
                Text("\(totalLocal) \(t("local results", lang))")
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
                    .padding(.bottom, 24)

                if totalLocal == 0 {
                    emptyState
                } else {
                    if !matchedShows.isEmpty {
                        showsSection
                            .padding(.bottom, 28)
                    }
                    if !matchedEpisodes.isEmpty {
                        episodesSection
                            .padding(.bottom, 28)
                    }
                    if !matchedHighlights.isEmpty {
                        highlightsSection
                            .padding(.bottom, 28)
                    }
                    if !matchedLines.isEmpty {
                        transcriptsSection
                            .padding(.bottom, 28)
                    }
                }

                applePodcastsCTA
                    .padding(.top, 8)
                    .padding(.bottom, 140)
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .environment(\.queueIDs, Set(queueItems.map(\.id)))
        // Debounce typing → write `debouncedQuery` 280ms after the
        // last keystroke. All downstream filtering depends on this
        // so a fast typist doesn't pay search cost per character.
        .onAppear {
            debouncedQuery = query   // initial paint matches current query
        }
        .onChange(of: query) { _, new in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                if Task.isCancelled { return }
                debouncedQuery = new
            }
        }
        // SwiftData predicate fetch with fetchLimit replaces the old
        // "@Query everything + .filter in memory" pattern. For a
        // heavy user that path materialised hundreds of thousands of
        // TranscriptLineModel instances per search-input event.
        .task(id: debouncedQuery) {
            await runLineSearch()
        }
    }

    @MainActor
    private func runLineSearch() async {
        let needle = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            if !matchedLinesState.isEmpty { matchedLinesState = [] }
            return
        }
        // localizedStandardContains is Unicode-aware case-insensitive
        // — handled at SQLite level by SwiftData, no full-table scan.
        var desc = FetchDescriptor<TranscriptLineModel>(
            predicate: #Predicate { $0.text.localizedStandardContains(needle) },
            sortBy: [SortDescriptor(\.t)]
        )
        desc.fetchLimit = 60
        if let rows = try? modelContext.fetch(desc) {
            matchedLinesState = rows
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Ink.tertiary)
            Text(t("Nothing in your library matches.", lang))
                .font(.serif(17))
                .italic()
                .foregroundColor(Ink.secondary)
                .multilineTextAlignment(.center)
            Text(t("Try Apple Podcasts to find new shows.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glass(.panel)
    }

    @ViewBuilder
    private var showsSection: some View {
        SectionHeader(eyebrow: t("Shows", lang),
                      title: "\(matchedShows.count) " + t("shows", lang))
        .padding(.bottom, 14)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 18)],
                  spacing: 18) {
            ForEach(matchedShows) { show in
                Button {
                    store.navigate(to: .show(show.id))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        CoverView(artworkUrl: show.artworkUrl, title: show.title,
                                  size: 200, radius: 14)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                        Text(show.title)
                            .font(.serif(15, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(2)
                        if !show.host.isEmpty {
                            Text(show.host)
                                .font(.sans(11.5))
                                .foregroundColor(Ink.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        SectionHeader(eyebrow: t("Episodes", lang),
                      title: "\(matchedEpisodes.count) " + t("episodes", lang))
        .padding(.bottom, 14)
        VStack(spacing: 0) {
            ForEach(matchedEpisodes) { ep in
                EpisodeRow(index: nil, episode: ep)
            }
        }
        .padding(6)
        .glass(.panel)
    }

    @ViewBuilder
    private var highlightsSection: some View {
        SectionHeader(eyebrow: t("Highlights", lang),
                      title: "\(matchedHighlights.count) " + t("highlights", lang))
        .padding(.bottom, 14)
        VStack(spacing: 12) {
            ForEach(matchedHighlights) { h in
                Button {
                    if let ep = h.episode {
                        store.navigate(to: .episode(ep.id))
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(accent)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 6) {
                            highlightedText(h.quote, query: q)
                                .font(.serif(15))
                                .italic()
                                .foregroundColor(Ink.primary)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                if let show = h.episode?.show {
                                    CoverView(artworkUrl: show.artworkUrl,
                                              title: show.title, size: 18, radius: 4)
                                    Text(show.title)
                                        .font(.sans(11.5))
                                        .foregroundColor(Ink.secondary)
                                }
                                Text(Fmt.time(h.at))
                                    .font(.mono(10.5))
                                    .foregroundColor(Ink.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .glass(.deep)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var transcriptsSection: some View {
        SectionHeader(eyebrow: t("Transcripts", lang),
                      title: "\(matchedLines.count) " + t("matches", lang))
        .padding(.bottom, 14)
        VStack(spacing: 8) {
            ForEach(matchedLines, id: \.persistentModelID) { line in
                Button {
                    if let ep = line.episode {
                        store.navigate(to: .episode(ep.id))
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
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
                        .frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            highlightedText(line.text, query: q)
                                .font(.serif(15))
                                .foregroundColor(Ink.secondary)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                            if let ep = line.episode {
                                Text(ep.title)
                                    .font(.sans(11))
                                    .foregroundColor(Ink.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.45))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var applePodcastsCTA: some View {
        Button {
            // Hand the query to Browse via a notification-style payload —
            // simplest: stash the query in the AppStore's `search` (already
            // there) and switch to .browse. BrowseView can pick it up on
            // appear.
            store.goTo(.browse)
            NotificationCenter.default.post(
                name: .runiTunesSearch,
                object: nil,
                userInfo: ["q": query]
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(t("Search Apple Podcasts for", lang)) \"\(query)\"")
                        .font(.serif(16, weight: .medium))
                        .foregroundColor(Ink.primary)
                    Text(t("Find new podcasts to subscribe to.", lang))
                        .font(.sans(12))
                        .foregroundColor(Ink.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Ink.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glass(.panel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Render `text` with the matching `query` substring highlighted in the
    /// brand accent. Case-insensitive match. Returns a `Text` so callers can
    /// chain font/color modifiers without losing the inline highlight.
    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = text.range(of: query, options: .caseInsensitive) else {
            return Text(text)
        }
        let before = String(text[..<range.lowerBound])
        let match  = String(text[range])
        let after  = String(text[range.upperBound...])
        return Text(before)
            + Text(match)
                .foregroundColor(accent)
                .fontWeight(.semibold)
            + Text(after)
    }
}

extension Notification.Name {
    static let runiTunesSearch = Notification.Name("pode.runiTunesSearch")
}
