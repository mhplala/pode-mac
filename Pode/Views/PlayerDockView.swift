import SwiftUI
import SwiftData

struct PlayerDockView: View {
    @Environment(AppStore.self) private var store
    @Query private var allEpisodes: [Episode]
    @State private var showTranscript: Bool = false

    private var episode: Episode? {
        guard let id = store.player.currentEpisodeID else { return nil }
        return allEpisodes.first(where: { $0.id == id })
    }

    var body: some View {
        if let ep = episode, let show = ep.show {
            // The outer body reads only `currentEpisodeID` and `isPlaying`
            // (via observed @Bindable accesses inside subviews) — NOT
            // `currentTime`. That keeps the glass dock shell from re-rendering
            // every 0.5s. Time-driven content is isolated into ScrubberRow
            // and ActiveLineMarquee.
            VStack(spacing: 8) {
                if showTranscript, !ep.transcriptLines.isEmpty {
                    TranscriptDrawer(episode: ep, store: store)
                        .padding(18)
                        .frame(maxHeight: 220)
                        .glass(.dock)
                }
                dock(ep: ep, show: show)
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func dock(ep: Episode, show: Show) -> some View {
        HStack(spacing: 16) {
            CoverMeta(episode: ep, show: show, store: store)
                .frame(width: 240, alignment: .leading)

            VStack(spacing: 6) {
                TransportRow(store: store)
                ScrubberRow(episode: ep, store: store)
            }
            .frame(maxWidth: .infinity)

            RightCluster(
                episode: ep,
                store: store,
                showTranscript: $showTranscript,
                hasTranscript: !ep.transcriptLines.isEmpty
            )
            .frame(width: 240)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(.dock)
    }
}

// MARK: - Static-ish parts (don't read currentTime)

private struct CoverMeta: View {
    let episode: Episode
    let show: Show
    let store: AppStore

    var body: some View {
        Button {
            store.view = .episode(episode.id)
        } label: {
            HStack(spacing: 12) {
                CoverView(artworkUrl: show.artworkUrl, title: show.title,
                          size: 48, radius: 9, playing: store.player.isPlaying)
                VStack(alignment: .leading, spacing: 0) {
                    Text(episode.title)
                        .font(.serif(14, weight: .medium))
                        .foregroundColor(Ink.primary)
                        .lineLimit(1)
                    Text(show.title)
                        .font(.sans(11.5))
                        .foregroundColor(Ink.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TransportRow: View {
    let store: AppStore
    var body: some View {
        HStack(spacing: 14) {
            DockBtn(label: "−15") { store.player.skip(-15) }
            DockIcon(systemName: "gobackward.5") { store.player.skip(-5) }
            Button {
                store.player.toggle()
            } label: {
                Image(systemName: store.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Ink.onPaper))
            }
            .buttonStyle(.plain)
            DockIcon(systemName: "goforward.5") { store.player.skip(5) }
            DockBtn(label: "+30") { store.player.skip(30) }
        }
    }
}

// MARK: - Time-driven parts (these re-render every 0.5s; the glass shell does not)

private struct ScrubberRow: View {
    let episode: Episode
    let store: AppStore

    var body: some View {
        let dur = max(episode.duration, store.player.duration)
        let wide = dur >= 3600
        let timeWidth: CGFloat = wide ? 62 : 44
        HStack(spacing: 10) {
            Text(Fmt.time(store.player.currentTime))
                .font(.mono(11))
                .foregroundColor(Ink.tertiary)
                .lineLimit(1)
                .frame(width: timeWidth, alignment: .trailing)

            Scrubber(currentTime: store.player.currentTime,
                     duration: dur,
                     onSeek: { store.player.seek(to: $0) })

            Text(Fmt.time(dur))
                .font(.mono(11))
                .foregroundColor(Ink.tertiary)
                .lineLimit(1)
                .frame(width: timeWidth, alignment: .leading)
        }
    }
}

private struct RightCluster: View {
    let episode: Episode
    let store: AppStore
    @Binding var showTranscript: Bool
    let hasTranscript: Bool

    var body: some View {
        HStack(spacing: 8) {
            if hasTranscript {
                ActiveLineMarquee(episode: episode, store: store)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer()
            }
            Button {
                showTranscript.toggle()
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12))
                    .foregroundColor(showTranscript ? Brand.orange : Ink.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(showTranscript ? Brand.orange.opacity(0.1) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasTranscript)
        }
    }
}

private struct ActiveLineMarquee: View {
    let episode: Episode
    let store: AppStore

    var body: some View {
        let lines = episode.sortedTranscriptLines
        let now = store.player.currentTime
        let active = lines.last { now >= $0.t }
        if let active {
            VStack(alignment: .trailing, spacing: 2) {
                if let speaker = active.speaker {
                    Text("\(speaker) · live")
                        .font(.mono(10))
                        .foregroundColor(Ink.tertiary)
                }
                Text("\"\(active.text)\"")
                    .font(.serif(12.5))
                    .italic()
                    .foregroundColor(Ink.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TranscriptDrawer: View {
    let episode: Episode
    let store: AppStore

    var body: some View {
        let sorted = episode.sortedTranscriptLines
        let now = store.player.currentTime
        let activeIdx = sorted.lastIndex(where: { now >= $0.t }) ?? -1
        let start = max(0, activeIdx - 1)
        let end = min(sorted.count, max(0, activeIdx) + 3)
        let slice = start < end ? Array(sorted[start..<end]) : []

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12))
                    .foregroundColor(Brand.orange)
                EyebrowText(text: "Live transcript")
                Spacer()
                Button("Open full →") {
                    store.view = .episode(episode.id)
                }
                .buttonStyle(TextButtonStyle())
            }
            ForEach(Array(slice.enumerated()), id: \.element.lineIndex) { i, line in
                let realIdx = start + i
                Button {
                    store.player.seek(to: line.t)
                } label: {
                    DrawerRow(line: line, isActive: realIdx == activeIdx)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DrawerRow: View {
    let line: TranscriptLineModel
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.time(line.t))
                    .font(.mono(10.5))
                    .foregroundColor(Ink.tertiary)
                if let speaker = line.speaker {
                    Text(speaker)
                        .font(.sans(11.5, weight: .semibold))
                        .foregroundColor(Ink.secondary)
                }
            }
            .frame(width: 110, alignment: .leading)
            .padding(.leading, 8)
            .overlay(
                Rectangle()
                    .fill(isActive ? Brand.orange : .clear)
                    .frame(width: 2),
                alignment: .leading
            )
            Text(line.text)
                .font(.serif(15))
                .foregroundColor(isActive ? Ink.primary : Ink.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Brand.orange.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Small reusable buttons

private struct DockBtn: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mono(11, weight: .semibold))
                .foregroundColor(Ink.primary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct DockIcon: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundColor(Ink.primary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct Scrubber: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let pct = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                    .frame(height: 6)
                Capsule().fill(Ink.primary)
                    .frame(width: max(0, geo.size.width * pct), height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .position(x: max(6, min(geo.size.width - 6, geo.size.width * pct)), y: geo.size.height / 2)
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .onTapGesture { p in
                let ratio = min(1, max(0, p.x / geo.size.width))
                onSeek(duration * ratio)
            }
            .gesture(
                DragGesture()
                    .onChanged { v in
                        let ratio = min(1, max(0, v.location.x / geo.size.width))
                        onSeek(duration * ratio)
                    }
            )
        }
        .frame(height: 12)
    }
}
