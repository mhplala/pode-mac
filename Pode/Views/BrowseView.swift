import SwiftUI
import SwiftData

struct BrowseView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Query private var shows: [Show]

    @State private var query: String = ""
    @State private var feedUrlInput: String = ""
    @State private var searching: Bool = false
    @State private var adding: Bool = false
    @State private var searchResults: [ITunesPodcast]? = nil
    @State private var top: [ITunesPodcast] = []
    @State private var loadingTop: Bool = true
    @State private var genreId: Int? = nil
    @State private var subscribingId: Int? = nil
    @State private var region: String = "cn"

    // Editor's pick canon — hand-curated AI roster, hydrated once via
    // iTunes lookup so artwork stays current.
    private let canon: CuratedCanon = .ai
    @State private var canonHydrated: [Int: ITunesPodcast] = [:]
    @State private var canonClusterId: String = CuratedCanon.ai.clusters.first?.id ?? ""

    /// When set, BrowseView renders a preview detail page for this iTunes
    /// podcast (cover/title/host + RSS-fetched recent episodes) instead
    /// of the grid. Cleared by the preview's back button.
    @State private var preview: ITunesPodcast? = nil

    var body: some View {
        if let p = preview {
            BrowsePreviewView(
                podcast: p,
                existingShow: subscribedShow(p),
                onBack: { preview = nil }
            )
        } else {
            mainBody
        }
    }

    @ViewBuilder
    private var mainBody: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: "Discover").padding(.bottom, 10)
                Text(t("Browse", lang))
                    .font(.serif(48, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 24)

                searchPanel.padding(.bottom, 22)

                if let results = searchResults {
                    SectionHeader(eyebrow: "\(results.count) \(t("results", lang))",
                                  title: "\"\(query)\"",
                                  action: AnyView(
                                    Button(t("Clear", lang)) {
                                        searchResults = nil
                                        query = ""
                                    }
                                    .buttonStyle(TextButtonStyle())
                                  ))
                    .padding(.bottom, 18)
                    grid(items: results)
                } else {
                    editorsPickSection
                        .padding(.bottom, 36)
                    Divider()
                        .opacity(0.4)
                        .padding(.bottom, 28)

                    SectionHeader(
                        eyebrow: t("Categories", lang),
                        title: t("Pick a room", lang),
                        action: AnyView(regionPicker)
                    )
                    .padding(.bottom, 18)
                    FlowLayout(spacing: 8) {
                        chip("All", on: genreId == nil) { genreId = nil; loadTop() }
                        ForEach(ITunesService.genres(for: region)) { g in
                            chip(g.name, on: genreId == g.id) {
                                genreId = g.id
                                loadTop()
                            }
                        }
                    }
                    .padding(.bottom, 22)

                    SectionHeader(
                        eyebrow: genreId.flatMap { id in ITunesService.genres(for: region).first(where: { $0.id == id })?.name } ?? t("Top podcasts", lang),
                        title: regionTitle()
                    )
                    .padding(.bottom, 18)

                    if top.isEmpty {
                        Text(loadingTop ? "Loading…" : "No results — try a different region or genre.")
                            .font(.serif(loadingTop ? 16 : 15))
                            .italic()
                            .foregroundColor(Ink.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(40)
                            .glass(.panel)
                    } else {
                        grid(items: top)
                            .opacity(loadingTop ? 0.5 : 1)
                            .animation(.easeOut(duration: 0.18), value: loadingTop)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .task {
            loadTop()
            loadCanon()
        }
        // When the global search field punches a query through to Browse
        // (via SearchView's "Search Apple Podcasts for X" CTA), pick it up
        // and run it.
        .onReceive(NotificationCenter.default.publisher(for: .runiTunesSearch)) { note in
            guard let q = note.userInfo?["q"] as? String, !q.isEmpty else { return }
            query = q
            runSearch()
        }
    }

    private var searchPanel: some View {
        VStack(spacing: 12) {
            // Search row
            HStack(spacing: 8) {
                searchField(
                    icon: "magnifyingglass",
                    placeholder: t("Search Apple's podcast directory…", lang),
                    text: $query
                ) {
                    runSearch()
                }
                Button {
                    runSearch()
                } label: {
                    Text(searching ? t("Searching…", lang) : t("Search", lang))
                        .lineLimit(1)
                        .frame(minWidth: 78)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            // Add feed row
            HStack(spacing: 8) {
                searchField(
                    icon: "plus",
                    placeholder: t("Or paste an RSS feed URL", lang),
                    text: $feedUrlInput
                ) {
                    addFeed()
                }
                Button {
                    addFeed()
                } label: {
                    Text(adding ? t("Adding…", lang) : t("Add feed", lang))
                        .lineLimit(1)
                        .frame(minWidth: 78)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(adding || feedUrlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .glass(.panel)
    }

    private func searchField(icon: String, placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Ink.tertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.sans(12.5))
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var regionPicker: some View {
        Menu {
            ForEach(ITunesService.regions) { r in
                Button {
                    region = r.code
                    genreId = nil
                    loadTop()
                } label: {
                    if r.code == region {
                        Label(r.name, systemImage: "checkmark")
                    } else {
                        Text(r.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe").font(.system(size: 11))
                Text(ITunesService.regions.first(where: { $0.code == region })?.name ?? region.uppercased())
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .font(.sans(12, weight: .medium))
            .foregroundColor(Ink.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.black.opacity(0.04))
                    .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func regionTitle() -> String {
        let regionName = ITunesService.regions.first(where: { $0.code == region })?.name ?? region.uppercased()
        switch region {
        case "cn", "tw", "hk", "jp": return "\(regionName) · 推荐"
        default: return t("Editor's chart", lang)
        }
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.sans(12, weight: .medium))
                .foregroundColor(on ? .white : Ink.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(on ? Ink.onPaper : Color.black.opacity(0.04))
                        .overlay(
                            Capsule().stroke(on ? Ink.onPaper : Color.black.opacity(0.05), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func grid(items: [ITunesPodcast]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(items) { p in
                tile(p)
            }
        }
    }

    private func tile(_ p: ITunesPodcast) -> some View {
        let subbed = isSubscribed(p)
        let localShow = subscribedShow(p)
        return VStack(alignment: .leading, spacing: 10) {
            // Cover + title is its own click target. For shows we already
            // subscribe to it deep-links into ShowDetailView; for shows
            // we don't, it auto-subscribes and then jumps to the show's
            // detail page (saves the user from reaching for the Subscribe
            // button below — clicking the cover is the obvious move).
            Button {
                openTile(p, existing: localShow)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    CoverView(artworkUrl: p.artworkUrl600 ?? p.artworkUrl100,
                              title: p.collectionName,
                              size: 260, radius: 14, fill: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.collectionName)
                            .font(.serif(15, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(2)
                        Text(p.artistName)
                            .font(.sans(11.5))
                            .foregroundColor(Ink.tertiary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 56, alignment: .top)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if subbed {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .foregroundColor(Success.primary)
                            .font(.system(size: 11))
                        Text(t("Subscribed", lang)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(true)
            } else {
                Button {
                    Task {
                        subscribingId = p.collectionId
                        _ = await store.subscribe(
                            feedUrl: p.feedUrl ?? "",
                            hint: (
                                title: p.collectionName,
                                host: p.artistName,
                                artworkUrl: p.artworkUrl600 ?? p.artworkUrl100 ?? "",
                                category: p.primaryGenreName,
                                itunesId: p.collectionId
                            )
                        )
                        subscribingId = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Fixed-size icon area prevents the row from
                        // shifting height between idle / subscribing.
                        ZStack {
                            if subscribingId == p.collectionId {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(.white)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                            }
                        }
                        .frame(width: 12, height: 12)

                        Text(subscribingId == p.collectionId
                             ? t("Subscribing…", lang)
                             : t("Subscribe", lang))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(subscribingId == p.collectionId)
            }
        }
        .padding(14)
        .glass(.tile)
    }

    /// Click a Browse tile. Subscribed → straight to the local show page
    /// (it has a real episode list). Not subscribed → open an inline
    /// preview view that fetches the RSS for a peek without committing
    /// to a subscription. The user can subscribe from inside the preview
    /// if they like what they see.
    private func openTile(_ p: ITunesPodcast, existing: Show?) {
        if let show = existing {
            store.navigate(to: .show(show.id))
            return
        }
        preview = p
    }

    private func isSubscribed(_ p: ITunesPodcast) -> Bool {
        subscribedShow(p) != nil
    }

    private func subscribedShow(_ p: ITunesPodcast) -> Show? {
        shows.first(where: { $0.itunesId == p.collectionId || $0.feedUrl == (p.feedUrl ?? "") })
    }

    private func runSearch() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        searching = true
        Task {
            do {
                let r = try await ITunesService.search(term: term, limit: 30)
                searchResults = r
            } catch {
                searchResults = []
                store.toast("Search failed: \(error.localizedDescription)")
            }
            searching = false
        }
    }

    private func addFeed() {
        let url = feedUrlInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        adding = true
        Task {
            let r = await store.subscribe(feedUrl: url)
            if r != nil { feedUrlInput = "" }
            adding = false
        }
    }

    private func loadTop() {
        loadingTop = true
        Task {
            do {
                top = try await ITunesService.top(country: region, genreId: genreId, limit: 24)
            } catch {
                top = []
                store.toast("Couldn't load top: \(error.localizedDescription)")
            }
            loadingTop = false
        }
    }

    // MARK: - Editor's Pick (curated canon)

    /// One-shot iTunes lookup that hydrates the entire canon's artwork +
    /// feedUrl in a single network call. We don't surface a loading state —
    /// the cluster grid renders immediately from the static data with
    /// gradient-fallback covers, then swaps in real artwork as it arrives.
    private func loadCanon() {
        let ids = canon.allItunesIds
        Task {
            do {
                let results = try await ITunesService.lookup(ids: ids)
                var map: [Int: ITunesPodcast] = [:]
                for r in results { map[r.collectionId] = r }
                canonHydrated = map
            } catch {
                // Fail silently — the static data still renders. Cover art
                // just stays as gradient until the next app launch.
            }
        }
    }

    private var activeCluster: CuratedCluster? {
        canon.clusters.first(where: { $0.id == canonClusterId }) ?? canon.clusters.first
    }

    @ViewBuilder
    private var editorsPickSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                eyebrow: t("Editor's pick", lang),
                title: canon.title,
                action: AnyView(
                    Text("Updated \(canon.updatedAt)")
                        .font(.mono(10.5, weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(Ink.tertiary)
                )
            )
            .padding(.bottom, 14)

            // Lead-in: the editorial framing for the whole canon.
            Text(canon.description)
                .font(.serif(16))
                .italic()
                .foregroundColor(Ink.secondary)
                .lineSpacing(2)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.bottom, 18)

            // Cluster selector — same chip vocabulary as the iTunes
            // genre row below, so the section reads as "another row of
            // categories" with the editorial layer on top.
            FlowLayout(spacing: 8) {
                ForEach(canon.clusters) { c in
                    canonChip(c)
                }
            }
            .padding(.bottom, 14)

            if let cluster = activeCluster {
                Text(cluster.blurb)
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.secondary)
                    .lineSpacing(1.5)
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(.bottom, 16)

                canonGrid(cluster.shows)
            }
        }
    }

    private func canonChip(_ c: CuratedCluster) -> some View {
        let on = canonClusterId == c.id
        return Button {
            canonClusterId = c.id
        } label: {
            HStack(spacing: 6) {
                Text(c.title)
                    .font(.sans(12, weight: .medium))
                Text("\(c.shows.count)")
                    .font(.sans(11, weight: .medium))
                    .foregroundColor(on ? Color.white.opacity(0.55) : Ink.tertiary)
            }
            .foregroundColor(on ? .white : Ink.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(on ? Ink.onPaper : Color.black.opacity(0.04))
                    .overlay(Capsule().stroke(on ? Ink.onPaper : Color.black.opacity(0.05), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func canonGrid(_ shows: [CuratedShow]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(shows) { s in
                canonTile(s)
            }
        }
    }

    /// Curated tile — same visual rhythm as the iTunes `tile()`, plus an
    /// italic editorial caption between the host line and the action button.
    /// Reuses subscribe / open semantics from the standard tile.
    private func canonTile(_ s: CuratedShow) -> some View {
        let live = canonHydrated[s.itunesId]
        let podcast = live ?? ITunesPodcast(
            collectionId: s.itunesId,
            collectionName: s.title,
            artistName: s.host,
            feedUrl: s.feedUrl,
            artworkUrl600: nil,
            artworkUrl100: nil,
            primaryGenreName: nil,
            trackCount: nil
        )
        let subbed = isSubscribed(podcast)
        let localShow = subscribedShow(podcast)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                openTile(podcast, existing: localShow)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    CoverView(
                        artworkUrl: live?.artworkUrl600 ?? live?.artworkUrl100,
                        title: s.title,
                        size: 260, radius: 14, fill: true
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title)
                            .font(.serif(15, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(2)
                        Text(s.host)
                            .font(.sans(11.5))
                            .foregroundColor(Ink.tertiary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 46, alignment: .top)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Editorial "why" caption. Italic serif, muted, 4-line clamp.
            // Sits between the title block and the subscribe button so it
            // doesn't compete with the show's own metadata.
            Text(s.why)
                .font(.serif(12.5))
                .italic()
                .foregroundColor(Ink.secondary)
                .lineSpacing(1.5)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black.opacity(0.07))
                        .frame(height: 1)
                }

            if subbed {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .foregroundColor(Success.primary)
                            .font(.system(size: 11))
                        Text(t("Subscribed", lang)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(true)
            } else {
                Button {
                    Task {
                        subscribingId = podcast.collectionId
                        _ = await store.subscribe(
                            feedUrl: podcast.feedUrl ?? "",
                            hint: (
                                title: podcast.collectionName,
                                host: podcast.artistName,
                                artworkUrl: podcast.artworkUrl600 ?? podcast.artworkUrl100 ?? "",
                                category: podcast.primaryGenreName,
                                itunesId: podcast.collectionId
                            )
                        )
                        subscribingId = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            if subscribingId == podcast.collectionId {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(.white)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                            }
                        }
                        .frame(width: 12, height: 12)

                        Text(subscribingId == podcast.collectionId
                             ? t("Subscribing…", lang)
                             : t("Subscribe", lang))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(subscribingId == podcast.collectionId)
            }
        }
        .padding(14)
        .glass(.tile)
    }
}

// MARK: - Browse preview detail

/// Read-only detail page for an `ITunesPodcast` we don't subscribe to yet.
/// Mirrors the look of `ShowDetailView` so the user gets a consistent
/// "this is a show page" feel — but the data comes from a one-off RSS
/// fetch instead of SwiftData. From here the user can either go back
/// to Browse or subscribe (which then routes to the real ShowDetailView).
private struct BrowsePreviewView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    let podcast: ITunesPodcast
    /// If non-nil, we're previewing a show the user already subscribes
    /// to — the subscribe button shows a checkmark instead. (BrowseView
    /// normally routes those clicks straight to the real ShowDetailView,
    /// so this is mostly a defensive fallback.)
    let existingShow: Show?
    let onBack: () -> Void

    @State private var feed: ParsedFeed? = nil
    @State private var loading: Bool = true
    @State private var fetchError: String? = nil
    @State private var subscribing: Bool = false

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 32) // overlay back button breathing room

                header
                    .padding(.top, 12)
                    .padding(.bottom, 22)

                episodesSection
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                    Text(t("Back", lang))
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
        .task(id: podcast.collectionId) { await loadFeed() }
    }

    // MARK: Header (cover + meta + actions)

    private var header: some View {
        HStack(alignment: .top, spacing: 26) {
            CoverView(
                artworkUrl: podcast.artworkUrl600 ?? podcast.artworkUrl100,
                title: podcast.collectionName,
                size: 200, radius: 22
            )
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: (podcast.primaryGenreName ?? "Podcast"))
                    .padding(.bottom, 6)
                Text(podcast.collectionName)
                    .font(.serif(36, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 8)
                if !podcast.artistName.isEmpty {
                    Text(podcast.artistName)
                        .font(.sans(14))
                        .foregroundColor(Ink.secondary)
                        .padding(.bottom, 14)
                }
                if let desc = feed?.show.description, !desc.isEmpty {
                    Text(HTMLStripper.toPlainText(desc))
                        .font(.serif(14))
                        .italic()
                        .foregroundColor(Ink.secondary)
                        .lineSpacing(2)
                        .lineLimit(4)
                        .padding(.bottom, 16)
                }
                actionRow
            }
        }
        .padding(28)
        .glass(.panel)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if existingShow != nil {
                // The user already has this show. We still let them open
                // the live page (BrowseView handles that path before us,
                // but if somehow we got here, route them there).
                Button {
                    if let s = existingShow { store.navigate(to: .show(s.id)) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .foregroundColor(Success.primary)
                            .font(.system(size: 11))
                        Text(t("Subscribed", lang)).lineLimit(1)
                    }
                }
                .buttonStyle(GhostButtonStyle())
            } else {
                Button {
                    Task { await doSubscribe() }
                } label: {
                    HStack(spacing: 6) {
                        // Pin icon/spinner area to a fixed size so the
                        // button height doesn't jump when state flips
                        // (ProgressView's intrinsic size is taller than
                        // an 11pt plus glyph).
                        ZStack {
                            if subscribing {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(.white)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                            }
                        }
                        .frame(width: 12, height: 12)

                        Text(subscribing
                             ? t("Subscribing…", lang)
                             : t("Subscribe", lang))
                            .lineLimit(1)
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(subscribing || (podcast.feedUrl ?? "").isEmpty)
            }

            Spacer()
            if let count = feed?.episodes.count {
                MetaMono(text: "\(count) episodes")
            }
        }
    }

    // MARK: Episodes preview

    @ViewBuilder
    private var episodesSection: some View {
        if let err = fetchError {
            Text(err)
                .font(.sans(13))
                .foregroundColor(Danger.primary)
                .frame(maxWidth: .infinity)
                .padding(40)
                .glass(.panel)
        } else if loading, feed == nil {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.7)
                Text(t("Loading episodes…", lang))
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .glass(.panel)
        } else if let eps = feed?.episodes, !eps.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(eps.prefix(20).enumerated()), id: \.element.guid) { _, ep in
                    PreviewEpisodeRow(episode: ep)
                }
            }
            .padding(6)
            .glass(.panel)
        } else {
            Text(t("No episodes in this feed yet.", lang))
                .font(.serif(15))
                .italic()
                .foregroundColor(Ink.tertiary)
                .frame(maxWidth: .infinity)
                .padding(40)
                .glass(.panel)
        }
    }

    // MARK: Actions

    private func loadFeed() async {
        loading = true
        fetchError = nil
        guard let url = podcast.feedUrl, !url.isEmpty else {
            fetchError = "This show has no RSS feed URL."
            loading = false
            return
        }
        do {
            let parsed = try await RSSService.fetchAndParse(feedUrl: url)
            feed = parsed
        } catch {
            fetchError = error.localizedDescription
        }
        loading = false
    }

    private func doSubscribe() async {
        subscribing = true
        let newShow = await store.subscribe(
            feedUrl: podcast.feedUrl ?? "",
            hint: (
                title: podcast.collectionName,
                host: podcast.artistName,
                artworkUrl: podcast.artworkUrl600 ?? podcast.artworkUrl100 ?? "",
                category: podcast.primaryGenreName,
                itunesId: podcast.collectionId
            )
        )
        subscribing = false
        // Hand off to the real (SwiftData-backed) detail page.
        if let newShow {
            store.navigate(to: .show(newShow.id))
        }
    }
}

/// Compact episode row used inside the Browse preview. Read-only — no
/// queue / play actions, since the show isn't subscribed yet.
private struct PreviewEpisodeRow: View {
    let episode: ParsedEpisode

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.serif(15, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .lineLimit(1)
                Text(Fmt.date(episode.pubDate))
                    .font(.sans(12.5))
                    .foregroundColor(Ink.secondary)
                    .lineLimit(1)
            }
            Spacer()
            MetaMono(text: Fmt.dur(episode.duration))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
