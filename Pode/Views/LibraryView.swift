import SwiftUI
import SwiftData

struct LibraryView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: "Your collection").padding(.bottom, 10)
                Text("Library")
                    .font(.serif(48, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 24)

                HStack {
                    PillBar(
                        items: LibraryTab.allCases.map { ($0, $0.label) },
                        selection: $tab
                    )
                    Spacer()
                    Button {
                        Task {
                            await store.refreshAll(shows: shows)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text(store.refreshing ? "Refreshing…" : "Refresh feeds")
                        }
                    }
                    .buttonStyle(GhostSmallButtonStyle())
                    .disabled(store.refreshing || shows.isEmpty)
                }
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
                    Text("No subscriptions yet.")
                        .font(.serif(17))
                        .italic()
                        .foregroundColor(Ink.secondary)
                    Button {
                        store.view = .browse
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 13))
                            Text("Browse podcasts")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .glass(.panel)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 5), spacing: 32) {
                    ForEach(shows) { show in
                        Button {
                            store.view = .show(show.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 200, radius: 14)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                Text(show.title)
                                    .font(.serif(16, weight: .medium))
                                    .foregroundColor(Ink.primary)
                                    .lineLimit(2)
                                    .padding(.top, 12)
                                if !show.host.isEmpty {
                                    Text(show.host)
                                        .font(.sans(12.5))
                                        .foregroundColor(Ink.tertiary)
                                        .lineLimit(1)
                                        .padding(.top, 3)
                                }
                                if let recent = show.episodes.sorted(by: { $0.pubDate > $1.pubDate }).first {
                                    MetaMono(text: "↓ \(String(recent.title.prefix(28)))\(recent.title.count > 28 ? "…" : "")")
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
                Text(emptyText)
                    .font(.serif(16))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .glass(.panel)
            } else {
                VStack(spacing: 0) {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    store.view = .library
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text("Back to Library")
                    }
                }
                .buttonStyle(TextButtonStyle())

                if let show = shows.first {
                    HStack(alignment: .top, spacing: 26) {
                        CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 200, radius: 16)
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
                                Button {
                                    refreshing = true
                                    Task {
                                        await store.refreshShow(show)
                                        refreshing = false
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11))
                                        Text(refreshing ? "Refreshing…" : "Refresh")
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                                .disabled(refreshing)

                                Button {
                                    confirmRemove = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                        Text("Unsubscribe")
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
                        Text("No episodes loaded yet — try refreshing.")
                            .font(.serif(15))
                            .italic()
                            .foregroundColor(Ink.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                            .glass(.panel)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sortedEps) { ep in
                                EpisodeRow(index: nil, episode: ep)
                            }
                        }
                        .padding(6)
                        .glass(.panel)
                    }
                } else {
                    Text("Show not found.")
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
        .alert("Unsubscribe?", isPresented: $confirmRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Unsubscribe", role: .destructive) {
                store.unsubscribe(showId: showId)
                store.view = .library
            }
        } message: {
            Text("Episodes, transcripts and highlights for this show will be removed.")
        }
    }
}
