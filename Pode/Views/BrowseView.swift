import SwiftUI
import SwiftData

struct BrowseView: View {
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

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: "Discover").padding(.bottom, 10)
                Text("Browse")
                    .font(.serif(48, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 24)

                searchPanel.padding(.bottom, 22)

                if let results = searchResults {
                    SectionHeader(eyebrow: "\(results.count) results", title: "\"\(query)\"",
                                  action: AnyView(
                                    Button("Clear") {
                                        searchResults = nil
                                        query = ""
                                    }
                                    .buttonStyle(TextButtonStyle())
                                  ))
                    .padding(.bottom, 18)
                    grid(items: results)
                } else {
                    SectionHeader(
                        eyebrow: "Categories",
                        title: "Pick a room",
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
                        eyebrow: genreId.flatMap { id in ITunesService.genres(for: region).first(where: { $0.id == id })?.name } ?? "Top podcasts",
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
        }
    }

    private var searchPanel: some View {
        VStack(spacing: 12) {
            // Search row
            HStack(spacing: 8) {
                searchField(
                    icon: "magnifyingglass",
                    placeholder: "Search Apple's podcast directory…",
                    text: $query
                ) {
                    runSearch()
                }
                Button {
                    runSearch()
                } label: {
                    Text(searching ? "Searching…" : "Search")
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
                    placeholder: "Or paste an RSS feed URL",
                    text: $feedUrlInput
                ) {
                    addFeed()
                }
                Button {
                    addFeed()
                } label: {
                    Text(adding ? "Adding…" : "Add feed")
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
        default: return "Editor's chart"
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
        return VStack(alignment: .leading, spacing: 10) {
            CoverView(artworkUrl: p.artworkUrl600 ?? p.artworkUrl100, title: p.collectionName, size: 260, radius: 14)
                .frame(maxWidth: .infinity)
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

            if subbed {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .foregroundColor(Success.primary)
                            .font(.system(size: 11))
                        Text("Subscribed").lineLimit(1)
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
                        if subscribingId == p.collectionId {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white)
                            Text("Subscribing…").lineLimit(1)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                            Text("Subscribe").lineLimit(1)
                        }
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

    private func isSubscribed(_ p: ITunesPodcast) -> Bool {
        shows.contains(where: { $0.itunesId == p.collectionId || $0.feedUrl == (p.feedUrl ?? "") })
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
}
