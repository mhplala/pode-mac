import SwiftUI
import SwiftData

struct ListenNowView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: [SortDescriptor(\Show.addedAt, order: .reverse)]) private var shows: [Show]
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var episodes: [Episode]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: Fmt.date(.now))
                    .padding(.bottom, 10)

                // Greeting
                Group {
                    Text(greeting()) +
                    Text(", ") +
                    Text(userName())
                        .italic()
                        .foregroundColor(Brand.orange) +
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
                        SectionHeader(eyebrow: "Continue Listening", title: "In progress")
                            .padding(.bottom, 18)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                            ForEach(inProg.prefix(3)) { ep in
                                InProgressCard(episode: ep)
                            }
                        }
                        .padding(.bottom, 36)
                    }

                    let next = upNext()
                    if !next.isEmpty {
                        SectionHeader(eyebrow: "Queue", title: "Up next")
                            .padding(.bottom, 18)
                        VStack(spacing: 0) {
                            ForEach(Array(next.enumerated()), id: \.element.id) { i, ep in
                                EpisodeRow(index: i + 1, episode: ep)
                            }
                        }
                        .padding(6)
                        .glass(.panel)
                        .padding(.bottom, 36)
                    }

                    SectionHeader(eyebrow: "Your Shows", title: "Recently updated")
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
            Text("Nothing here yet. Browse the directory, paste a feed URL, or search for a show.")
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
                        Text("Browse podcasts")
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

    private func featuredEpisode() -> Episode? {
        if let inProg = episodes.first(where: { $0.played > 0 && $0.played < 1 }) { return inProg }
        return episodes.first
    }

    private func inProgress() -> [Episode] {
        episodes.filter { $0.played > 0 && $0.played < 1 }
    }

    private func upNext() -> [Episode] {
        var seen: Set<String> = []
        var out: [Episode] = []
        for ep in episodes {
            if ep.played >= 0.99 { continue }
            guard let sid = ep.show?.id else { continue }
            if seen.contains(sid) { continue }
            seen.insert(sid)
            out.append(ep)
            if out.count >= 5 { break }
        }
        return out
    }

    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: .now)
        if h < 5 { return "Good night" }
        if h < 12 { return "Good morning" }
        if h < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private func userName() -> String {
        store.settings.userName.isEmpty ? "friend" : store.settings.userName
    }
}

private struct FeaturedCard: View {
    @Environment(AppStore.self) private var store
    let episode: Episode

    var body: some View {
        if let show = episode.show {
            HStack(alignment: .top, spacing: 28) {
                CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 260, radius: 16)

                VStack(alignment: .leading, spacing: 0) {
                    EyebrowText(text: "Featured · \(show.title)")
                        .padding(.bottom, 8)
                    Text(episode.title)
                        .font(.serif(38, weight: .medium))
                        .foregroundColor(Ink.primary)
                        .lineLimit(3)
                        .padding(.bottom, 14)

                    Text(episode.aiSummary ?? episode.episodeDescription ?? "Open the episode to download, transcribe, and analyze.")
                        .font(.serif(17))
                        .italic()
                        .foregroundColor(Ink.secondary)
                        .lineSpacing(2)
                        .lineLimit(4)
                        .frame(maxWidth: 560, alignment: .leading)
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
                    CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 64, radius: 10)
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
                .glass(.deep)
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
    let index: Int?
    let episode: Episode

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
                        Text(show.title)
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
                        MetaMono(text: Fmt.dur(episode.duration))
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
                CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 140, radius: 14)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                Text(show.title)
                    .font(.serif(14, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .lineLimit(2)
                    .padding(.top, 10)
                if !show.host.isEmpty {
                    Text(show.host)
                        .font(.sans(11.5))
                        .foregroundColor(Ink.tertiary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
