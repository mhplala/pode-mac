import SwiftUI
import SwiftData
import CoreMedia

struct PlayerDockView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Query private var allEpisodes: [Episode]
    @Query(sort: [SortDescriptor(\QueueItem.position, order: .forward)])
    private var queue: [QueueItem]
    @State private var showQueue: Bool = false

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
            dock(ep: ep, show: show)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func dock(ep: Episode, show: Show) -> some View {
        // Two-row dock. Top row: cover/title (left), transport controls
        // (center, geometrically — symmetric Spacers around them), and
        // right cluster. Bottom row: full-width scrubber with chapter
        // dots embedded inline, time labels at the corners.
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                CoverMeta(episode: ep, show: show, store: store)
                    .frame(width: 240, alignment: .leading)

                Spacer(minLength: 8)
                TransportRow(store: store)
                Spacer(minLength: 8)

                RightCluster(
                    episode: ep,
                    store: store,
                    showQueue: $showQueue,
                    queueCount: max(0, queue.count - 1)
                )
                .frame(width: 240)
            }

            ScrubberRow(episode: ep, store: store)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(.dock)
        // SwiftUI's Text views default to the I-beam cursor on macOS
        // because they're potentially selectable. The dock has lots of
        // Text (times, titles, transport labels) but none of it should
        // be selectable — force the arrow cursor across the whole dock.
        .arrowCursor()
    }
}

/// View modifier that forces NSCursor.arrow while the pointer is inside
/// the modified view. Uses push/pop so it stacks cleanly with other
/// cursor changes (e.g. button hovers).
private struct ArrowCursorModifier: ViewModifier {
    @State private var pushed = false
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active:
                if !pushed { NSCursor.arrow.push(); pushed = true }
            case .ended:
                if pushed { NSCursor.pop(); pushed = false }
            }
        }
    }
}
private extension View {
    func arrowCursor() -> some View { modifier(ArrowCursorModifier()) }
}

// MARK: - Static-ish parts (don't read currentTime)

private struct CoverMeta: View {
    let episode: Episode
    let show: Show
    let store: AppStore

    var body: some View {
        Button {
            store.navigate(to: .episode(episode.id))
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
            RatePicker(store: store)
        }
    }
}

/// Playback speed picker. Renders the current rate (e.g. "1.5×") and opens
/// a Menu of presets on click. Active rate is highlighted with the brand
/// accent so the user can see at a glance whether playback is at normal
/// speed or sped up.
private struct RatePicker: View {
    let store: AppStore
    @Environment(\.brandAccent) private var accent: Color

    /// Preset rates. Round set that covers "slow down a hair to catch a
    /// line" through "podcast-junkie 3×". Skip 0.5 — too slow to actually
    /// listen to a podcast.
    private static let presets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        let rate = store.player.playbackRate
        let isCustom = rate != 1.0
        Menu {
            // Most-likely options first; checkmark on whichever matches
            // the live rate so the user can confirm without doing the
            // mental "what was it set to?" recall.
            ForEach(Self.presets, id: \.self) { preset in
                Button {
                    store.setPlaybackRate(preset)
                } label: {
                    HStack {
                        Text(Self.label(for: preset))
                        if rate == preset { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Text(Self.label(for: rate))
                .font(.mono(11, weight: .semibold))
                .foregroundColor(isCustom ? accent : Ink.primary)
                .frame(width: 44, height: 38)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Playback speed")
    }

    /// Format rates without trailing zeros and a trailing "×".
    /// 1.0 → "1×", 1.5 → "1.5×", 1.75 → "1.75×". Cleaner than always
    /// padding to two decimals.
    static func label(for rate: Double) -> String {
        let asInt = Int(rate)
        if Double(asInt) == rate { return "\(asInt)×" }
        // 1.25 / 1.5 / 1.75 etc — strip trailing zero if any
        let s = String(format: "%g", rate)
        return "\(s)×"
    }
}

// MARK: - Time-driven parts (these re-render every 0.5s; the glass shell does not)

private struct ScrubberRow: View {
    let episode: Episode
    let store: AppStore

    var body: some View {
        let _ = PerfCounters.shared.dockEval()
        return measureBody(.scrubber) {
        let dur = max(episode.duration, store.player.duration)
        let wide = dur >= 3600
        let timeWidth: CGFloat = wide ? 64 : 44
        let chapters = ChapterParser.chapters(
            from: episode.episodeDescription,
            episodeDuration: dur
        )
        let highlights = episode.highlights.sorted(by: { $0.at < $1.at })

        // When the episode exceeds an hour we pad the *current* time to
        // HH:MM:SS too — `00:47:49` instead of `47:49`. That way the left
        // label has a stable width and stays aligned with the cover above
        // it; otherwise the text drifts horizontally as the playhead
        // crosses the 1h mark.
        HStack(spacing: 12) {
            Text(formattedTime(store.player.currentTime, wide: wide))
                .font(.mono(11))
                .foregroundColor(Ink.tertiary)
                .lineLimit(1)
                // Align with row-1's cover left edge — cover is leading-
                // anchored at the same dock padding, label text leading
                // here matches it.
                .frame(width: timeWidth, alignment: .leading)

            ChapterScrubber(
                currentTime: store.player.currentTime,
                duration: dur,
                chapters: chapters,
                highlights: highlights,
                onScrub: { t in
                    store.player.seek(to: t, tolerance: CMTime(seconds: 1.0, preferredTimescale: 600))
                },
                onCommit: { t in store.player.commitSeek(to: t) }
            )

            Text(formattedTime(dur, wide: wide))
                .font(.mono(11))
                .foregroundColor(Ink.tertiary)
                .lineLimit(1)
                // Mirror on the right: align with the right cluster's
                // trailing edge above.
                .frame(width: timeWidth, alignment: .trailing)
        }
        }   // closes measureBody(.scrubber) { ... }
    }

    /// Stable-width time format. When the episode is ≥1h we always show
    /// `HH:MM:SS` (zero-padded), so the current-time label and total-
    /// duration label have identical widths and alignment is solid from
    /// 00:00:00 through to the end.
    private func formattedTime(_ s: Double, wide: Bool) -> String {
        guard s.isFinite, s >= 0 else { return wide ? "00:00:00" : "0:00" }
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if wide {
            return String(format: "%02d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}

private struct RightCluster: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    let episode: Episode
    let store: AppStore
    @Binding var showQueue: Bool
    /// Items behind the head (i.e. "Up next" count). 0 hides the badge.
    let queueCount: Int

    var body: some View {
        HStack(spacing: 8) {
            if !episode.transcriptLines.isEmpty {
                ActiveLineMarquee(episode: episode, store: store)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer()
            }

            // Queue button. Anchors a popover with the full queue and
            // native drag-reorder. The hit zone is the full 38×40 frame
            // (incl. the badge offset region) so it never feels finicky.
            Button {
                showQueue.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(showQueue ? accent : Ink.primary)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(showQueue ? accent.opacity(0.1) : .clear)
                        )
                    if queueCount > 0 {
                        Text("\(queueCount)")
                            .font(.mono(9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Circle().fill(Ink.onPaper))
                            .offset(x: 5, y: -2)
                    }
                }
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t("Queue", lang))
            .popover(isPresented: $showQueue, arrowEdge: .top) {
                QueuePopover(store: store)
            }
        }
    }
}

/// Queue popover anchored on the dock's queue button.
/// - Renders the full queue (head = currently playing, then upcoming).
/// - Drag-reorder uses `List`'s native `.onMove` so the user gets the
///   familiar finder-style row drag handle.
/// - Each row has remove (×). The current head shows a "now playing"
///   chip and is non-reorderable from the user's perspective (its play
///   state is owned by the player, not the queue UI).
private struct QueuePopover: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    let store: AppStore
    @Query(sort: [SortDescriptor(\QueueItem.position, order: .forward)])
    private var queue: [QueueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: t("Queue", lang).uppercased())
                    Text(t("Up next", lang))
                        .font(.serif(18, weight: .medium))
                        .foregroundColor(Ink.primary)
                }
                Spacer()
                if queue.count > 1 {
                    Button {
                        store.clearQueue()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                            Text(t("Clear", lang))
                        }
                    }
                    .buttonStyle(GhostSmallButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.4)

            if queue.isEmpty {
                Text(t("Queue is empty.", lang))
                    .font(.serif(14))
                    .italic()
                    .foregroundColor(Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                // Native List for drag-reorder. The first item is rendered
                // as a non-movable header row with a "now playing" chip.
                List {
                    if let head = queue.first, let ep = head.episode {
                        QueuePopoverRow(
                            episode: ep,
                            isHead: true,
                            onRemove: { store.removeFromQueue(episodeID: ep.id) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    ForEach(Array(queue.dropFirst()), id: \.id) { item in
                        if let ep = item.episode {
                            QueuePopoverRow(
                                episode: ep,
                                isHead: false,
                                onRemove: { store.removeFromQueue(episodeID: ep.id) }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                    }
                    .onMove(perform: handleMove)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, idealHeight: CGFloat(min(queue.count, 6)) * 64,
                       maxHeight: 420)
            }
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
    }

    /// SwiftUI's `.onMove` reports indices relative to the upcoming list
    /// (we trimmed the head). Remap them to absolute queue indices for
    /// `store.reorderQueue`.
    private func handleMove(from source: IndexSet, to destination: Int) {
        let upcomingOffset = 1
        let absoluteSource = IndexSet(source.map { $0 + upcomingOffset })
        let absoluteDest = destination + upcomingOffset
        store.reorderQueue(from: absoluteSource, to: absoluteDest)
    }
}

private struct QueuePopoverRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(\.brandAccent) private var accent: Color
    let episode: Episode
    let isHead: Bool
    let onRemove: () -> Void

    var body: some View {
        if let show = episode.show {
            HStack(spacing: 10) {
                CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 38, radius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(episode.title)
                            .font(.serif(13.5, weight: .medium))
                            .foregroundColor(Ink.primary)
                            .lineLimit(1)
                        if isHead {
                            Text(t("Now", lang))
                                .font(.mono(9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(accent))
                        }
                    }
                    Text("\(show.title) · \(Fmt.dur(episode.duration))")
                        .font(.sans(11))
                        .foregroundColor(Ink.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Ink.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.white.opacity(0.04))
                                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(t("Remove from queue", lang))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                store.navigate(to: .episode(episode.id))
            }
        }
    }
}

private struct ActiveLineMarquee: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    let episode: Episode
    let store: AppStore

    /// Sorted snapshot of the episode's transcript lines, cached in
    /// @State so we don't re-sort on every player tick. Re-primed when
    /// the episode changes via `.task(id:)`.
    @State private var sortedCache: [TranscriptLineModel] = []
    /// Currently-active line for this dock. Updated by the player
    /// tick subscription, NOT by reading currentTime in body — so the
    /// dock body re-renders only when the active line actually
    /// crosses (rare), not 2×/sec.
    @State private var active: TranscriptLineModel? = nil

    var body: some View {
        Group {
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
        // Re-prime cache on episode change. Doesn't fire per-tick; only
        // when the played episode actually swaps.
        .task(id: episode.id) {
            sortedCache = episode.transcriptLines.sorted { $0.t < $1.t }
            updateActive(at: store.player.currentTime)
        }
        // Subscribe via Combine subject — NOT .onChange(of: currentTime).
        // The subject sits behind @ObservationIgnored so reading it in
        // body adds no tracked dep, and only `active` state writes
        // cause body re-render (i.e. when the line actually changes,
        // ~1/sec on dense podcasts vs 2/sec on every tick).
        .onReceive(store.player.timePublisher) { newTime in
            updateActive(at: newTime)
        }
    }

    /// Binary-search the active line for `now`. Writes to @State only
    /// when the line's identity actually changes — no spurious body
    /// re-render per tick.
    private func updateActive(at now: Double) {
        let lines = sortedCache
        guard !lines.isEmpty else {
            if active != nil { active = nil }
            return
        }
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].t <= now { lo = mid + 1 } else { hi = mid }
        }
        let idx = lo - 1
        let new = (idx >= 0) ? lines[idx] : nil
        if new?.lineIndex != active?.lineIndex {
            active = new
        }
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
                .frame(width: 38, height: 38)
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
                .font(.system(size: 14))
                .foregroundColor(Ink.primary)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width scrubber with chapter dots, user-highlight bookmarks, hover
/// preview tooltip, click-snap-to-chapter, density clustering, and a
/// hover-time bar-thickening animation.
///
/// Design notes:
///
/// - **Filled bar**: live playback position; switches to a drag preview
///   while the user is mid-scrub.
/// - **Chapter dots**: 6pt circles drawn ABOVE the bar (not crossing it)
///   — looks more like video-product "highlight moments" than the
///   previous vertical-line ticks. The chapter the playhead currently
///   sits in is the brand accent + slightly larger; others are subtle.
/// - **Highlight bookmarks**: user-saved highlights show up as a second
///   layer of small accent glyphs BELOW the bar. Different layer + side
///   so they don't get confused with chapters.
/// - **Density clustering**: when two chapter dots would render within
///   ~`clusterPx` of each other, the second one is dropped from drawing
///   (still searchable via hover) so the bar doesn't turn into a smear
///   on dense outline-style descriptions.
/// - **Click snap**: tapping within `snapPx` of a chapter dot seeks
///   exactly to that chapter's start time, not to the cursor's exact
///   ratio. Anywhere else: free seek.
/// - **Hover bar thicken**: track height grows from 5pt → 9pt under the
///   cursor with a quick `easeOut`. Same idea as YouTube/Netflix bars.
/// - **Hover tooltip**: floats above the bar tracking the cursor, shows
///   the chapter title + timestamp (or just the timestamp if no chapter
///   covers that point yet).
private struct ChapterScrubber: View {
    let currentTime: Double
    let duration: Double
    let chapters: [Chapter]
    let highlights: [Highlight]
    /// Visual-only seek during drag (loose tolerance, runs on every delta).
    let onScrub: (Double) -> Void
    /// Final landing point — frame-accurate.
    let onCommit: (Double) -> Void

    @Environment(\.brandAccent) private var accent: Color
    @State private var dragRatio: Double? = nil
    @State private var hoverRatio: Double? = nil
    @State private var hovering: Bool = false

    private let barTrackIdle: CGFloat = 6
    private let barTrackHover: CGFloat = 10
    private let snapPx: CGFloat = 12             // click within ⇒ snap to chapter
    private let clusterPx: CGFloat = 8           // dots within ⇒ drop one

    /// Row height is fixed at the hover-thickened bar size + a hair of
    /// breathing room so the layout doesn't reflow when the user mouses
    /// over the bar — only the rendered track shrinks/grows.
    private var rowHeight: CGFloat { barTrackHover + 4 }

    var body: some View {
        GeometryReader { geo in
            let livePct = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
            let pct = dragRatio ?? livePct
            let trackH = hovering ? barTrackHover : barTrackIdle
            let centerY = rowHeight / 2

            ZStack(alignment: .leading) {
                track(width: geo.size.width, height: trackH, centerY: centerY)
                fill(width: geo.size.width, height: trackH, pct: pct, centerY: centerY)
                chapterDots(width: geo.size.width, centerY: centerY, trackH: trackH, pct: pct)
                handle(width: geo.size.width, pct: pct, centerY: centerY)
            }
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { p in
                let t = snappedTime(forX: p.x, width: geo.size.width)
                onCommit(t)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        // ONLY update local dragRatio for visual feedback
                        // (the fill capsule reads `dragRatio ?? livePct`).
                        // We deliberately do NOT call onScrub here — that
                        // path used to AVPlayer-seek on every drag tick
                        // (60+ Hz), each seek updated `currentTime` which
                        // propagated to every Observable subscriber and
                        // melted the main thread. The actual seek lands
                        // on .onEnded only.
                        let ratio = min(1, max(0, v.location.x / geo.size.width))
                        dragRatio = ratio
                    }
                    .onEnded { v in
                        // Snap on release when the release point is close
                        // to a chapter dot.
                        let t = snappedTime(forX: v.location.x, width: geo.size.width)
                        dragRatio = nil
                        onCommit(t)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let ratio = min(1, max(0, location.x / geo.size.width))
                    hoverRatio = ratio
                    if !hovering { hovering = true }
                case .ended:
                    hoverRatio = nil
                    hovering = false
                }
            }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .overlay(alignment: .topLeading) {
                if let r = hoverRatio {
                    // Capsule pill that *follows the cursor* horizontally.
                    // Uses a hidden GeometryReader sibling to measure the
                    // tooltip's actual width on the fly — that way short
                    // content (just a timestamp) stays compact while a
                    // long chapter title gets a wider pill, both centered
                    // on the cursor and clamped inside the dock edges.
                    HoverTooltip(
                        time: r * duration,
                        chapter: chapter(at: r * duration),
                        highlight: highlight(near: r * duration),
                        accent: accent
                    )
                    .modifier(FollowCursor(
                        ratio: r,
                        trackWidth: geo.size.width,
                        // Smaller (less-negative) offset = pill sits
                        // closer to the bar.
                        verticalOffset: -20
                    ))
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: rowHeight)
    }

    // MARK: - Layers

    @ViewBuilder
    private func track(width: CGFloat, height: CGFloat, centerY: CGFloat) -> some View {
        Capsule().fill(Color.black.opacity(0.08))
            .frame(width: width, height: height)
            .position(x: width / 2, y: centerY)
    }

    @ViewBuilder
    private func fill(width: CGFloat, height: CGFloat, pct: Double, centerY: CGFloat) -> some View {
        let w = max(0, width * pct)
        Capsule().fill(Ink.primary)
            .frame(width: w, height: height)
            .position(x: w / 2, y: centerY)
    }

    /// Subtle chapter dots embedded in the bar, centered on the track.
    /// All dots are the same size + low-contrast — the playhead handle is
    /// the only "you are here" indicator the user needs, and a colored
    /// current-chapter dot was redundant noise. Color flips by side of
    /// the playhead so each dot stays legible against its background:
    /// passed (sitting on the dark fill) → faint white; ahead (sitting
    /// on the gray track) → faint black.
    @ViewBuilder
    private func chapterDots(width: CGFloat, centerY: CGFloat, trackH: CGFloat, pct: Double) -> some View {
        let visible = clusteredChapters(width: width)
        let headX: CGFloat = width * pct
        let dotSize: CGFloat = min(trackH - 2, 4)
        ForEach(visible) { ch in
            let x: CGFloat = duration > 0 ? width * CGFloat(ch.t / duration) : 0
            let isPassed = x <= headX
            Circle()
                .fill(isPassed
                      ? Color.white.opacity(0.55)
                      : Color.black.opacity(0.30))
                .frame(width: dotSize, height: dotSize)
                .position(x: x, y: centerY)
        }
    }

    @ViewBuilder
    private func handle(width: CGFloat, pct: Double, centerY: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .position(
                x: max(6, min(width - 6, width * pct)),
                y: centerY
            )
    }

    // MARK: - Helpers

    /// Drop chapters that would render within `clusterPx` of an earlier
    /// one. Hover lookup still uses the full list — this is purely a
    /// visual de-duplication.
    private func clusteredChapters(width: CGFloat) -> [Chapter] {
        let sorted = chapters.filter { $0.t > 1 }.sorted { $0.t < $1.t }
        guard duration > 0, !sorted.isEmpty else { return [] }
        var lastX: CGFloat = -.infinity
        var out: [Chapter] = []
        for ch in sorted {
            let x = width * (ch.t / duration)
            if x - lastX >= clusterPx {
                out.append(ch)
                lastX = x
            }
        }
        return out
    }

    /// Map an x coordinate to a playback time, snapping to the nearest
    /// chapter start when the cursor's within `snapPx`.
    private func snappedTime(forX x: CGFloat, width: CGFloat) -> Double {
        guard duration > 0, width > 0 else { return 0 }
        let ratio = min(1, max(0, x / width))
        let rawT = duration * ratio
        // Find nearest chapter; if its dot is within snapPx of x, snap.
        if let near = nearestChapter(toX: x, width: width),
           abs(width * (near.t / duration) - x) <= snapPx {
            return near.t
        }
        return rawT
    }

    private func nearestChapter(toX x: CGFloat, width: CGFloat) -> Chapter? {
        guard duration > 0 else { return nil }
        var best: (Chapter, CGFloat)?
        for ch in chapters where ch.t > 1 {
            let cx: CGFloat = width * CGFloat(ch.t / duration)
            let d: CGFloat = abs(cx - x)
            if best == nil || d < best!.1 { best = (ch, d) }
        }
        return best?.0
    }

    private var currentChapter: Chapter? {
        chapters.last(where: { currentTime >= $0.t })
    }

    private func chapter(at t: Double) -> Chapter? {
        chapters.last(where: { t >= $0.t })
    }

    /// Highlight whose timestamp is within ~3 seconds of `t`. The hover
    /// tooltip uses this to surface the user's saved quote when they
    /// hover near a bookmark glyph.
    private func highlight(near t: Double) -> Highlight? {
        highlights.min(by: { abs($0.at - t) < abs($1.at - t) })
            .flatMap { abs($0.at - t) <= 3 ? $0 : nil }
    }
}

/// Floating chip rendered above the scrubber when the cursor hovers.
/// Capsule-shaped pill so it reads as a "liquid" indicator on top of the
/// progress bar rather than a documenty rounded-rectangle card.
/// Surfaces, in priority order: a nearby user highlight (if any),
/// then the chapter at the hovered position, then the timestamp itself.
private struct HoverTooltip: View {
    let time: Double
    let chapter: Chapter?
    let highlight: Highlight?
    let accent: Color

    var body: some View {
        // Single-line HStack so the capsule shape stays naturally
        // pill-like (wider than tall). Long titles get truncated with
        // `lineLimit(1)` rather than wrapping to two lines, since wrapping
        // turns the pill back into a rectangle visually.
        HStack(spacing: 8) {
            if let highlight {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(accent)
                Text("\"\(highlight.quote)\"")
                    .font(.serif(12, weight: .medium))
                    .italic()
                    .foregroundColor(Ink.primary)
                    .lineLimit(1)
            } else if let chapter {
                Text(chapter.title)
                    .font(.serif(12.5, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .lineLimit(1)
            }
            Text(Fmt.time(time))
                .font(.mono(10))
                .foregroundColor(Ink.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        )
        .frame(maxWidth: 320, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
    }
}

/// Modifier that pins a tooltip view above the scrubber and **follows
/// the cursor horizontally**. Measures its target's width via a hidden
/// GeometryReader sibling so the pill stays centered on the cursor
/// regardless of content length, and clamps the center to keep the pill
/// fully on-screen near the dock edges.
///
/// Implementation note: we use `.position(x:y:)` (which positions the
/// view's CENTER) rather than `alignmentGuide(.leading)` — the latter
/// behaves inconsistently when the modified view's intrinsic width
/// changes between renders (the guide uses a stale width on the frame
/// where the new content lays out).
private struct FollowCursor: ViewModifier {
    let ratio: Double
    let trackWidth: CGFloat
    let verticalOffset: CGFloat
    @State private var tooltipWidth: CGFloat = 80

    func body(content: Content) -> some View {
        // Position the center of the tooltip on the cursor's x. Clamp
        // so the pill never overflows the track on either edge.
        let cursorX: CGFloat = CGFloat(ratio) * trackWidth
        let halfW: CGFloat = tooltipWidth / 2
        let clampedX: CGFloat = max(halfW, min(trackWidth - halfW, cursorX))

        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: TooltipWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(TooltipWidthKey.self) { tooltipWidth = $0 }
            .position(x: clampedX, y: verticalOffset)
    }
}

private struct TooltipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 80
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
