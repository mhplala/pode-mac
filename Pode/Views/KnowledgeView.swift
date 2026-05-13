import SwiftUI
import SwiftData

struct KnowledgeView: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(\.brandAccent) private var accent: Color
    @Environment(AppStore.self) private var store
    @Query private var concepts: [Concept]
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var episodes: [Episode]
    @Query(sort: [SortDescriptor(\Highlight.createdAt, order: .reverse)]) private var highlights: [Highlight]
    @Query private var shows: [Show]

    enum Mode: String, Hashable { case galaxy, timeline }
    @State private var mode: Mode = .galaxy
    @State private var selected: String? = nil
    @State private var hovered: String? = nil

    private static let clusterColors: [String: Color] = [
        "Editorial": Color(hex: "#d06a3a"),
        "Mind": Color(hex: "#0075de"),
        "Body": Color(hex: "#1f7a4c"),
        "Craft": Color(hex: "#7a3a2e"),
        "Other": Color(hex: "#615d59"),
    ]
    private static let clusterOrder = ["Editorial", "Mind", "Body", "Craft", "Other"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(accent)
                    EyebrowText(text: t("What you've learned", lang).uppercased())
                }
                .padding(.bottom, 10)

                Group {
                    Text(t("Your", lang) + " ") +
                    Text(t("canon", lang)).italic().foregroundColor(accent) +
                    Text(".")
                }
                .font(.serif(56, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 6)

                if concepts.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: 18) {
                        Text("\(concepts.count) \(t("concepts", lang))")
                        Text("\(highlights.count) \(t("highlights", lang))")
                        Text("\(transcribedCount) \(t("transcripts", lang))")
                    }
                    .font(.mono(12.5))
                    .foregroundColor(Ink.tertiary)
                    .tracking(0.5)
                    .padding(.bottom, 24)

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 6) {
                                    EyebrowText(text: t(mode == .galaxy ? "Concept galaxy" : "Concept timeline", lang).uppercased())
                                    Text(t(mode == .galaxy ? "How ideas cluster across your listening" : "When ideas appeared", lang))
                                        .font(.serif(22, weight: .medium))
                                        .foregroundColor(Ink.primary)
                                }
                                Spacer()
                                HStack(spacing: 14) {
                                    if selected == nil {
                                        legend
                                    }
                                    PillBar(items: [(Mode.galaxy, t("Galaxy", lang)), (Mode.timeline, t("Timeline", lang))],
                                            selection: $mode)
                                }
                            }
                            .padding(.bottom, 14)

                            if mode == .galaxy {
                                Galaxy(concepts: concepts, selected: $selected, hovered: $hovered, colors: Self.clusterColors)
                            } else {
                                Timeline(concepts: concepts, episodes: episodes,
                                         clusters: visibleClusters(),
                                         selected: $selected,
                                         colors: Self.clusterColors)
                            }
                        }
                        .padding(24)
                        .glass(.panel)

                        if let name = selected, let concept = concepts.first(where: { $0.name == name }) {
                            ConceptDrawer(concept: concept, episodes: episodes, shows: shows, onClose: { selected = nil })
                                .frame(width: 380)
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        highlightsCard
                        steveNoticedCard
                    }
                    .padding(.top, 18)
                }
            }
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text(t("No concepts yet. Transcribe an episode and run AI analysis — Claude will pull out concepts, and they'll cluster here as a galaxy of what you've heard.", lang))
                .font(.serif(17))
                .italic()
                .foregroundColor(Ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .lineSpacing(2)
            Button {
                store.goTo(.library)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.grid.2x2").font(.system(size: 13))
                    Text(t("Open Library", lang))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .glass(.panel)
        .padding(.top, 14)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(visibleClusters(), id: \.self) { cl in
                HStack(spacing: 5) {
                    Circle().fill(Self.clusterColors[cl] ?? .gray)
                        .frame(width: 7, height: 7)
                    Text(t(cl, lang))
                        .font(.sans(11.5, weight: .medium))
                        .foregroundColor(Ink.secondary)
                }
            }
        }
    }

    private func visibleClusters() -> [String] {
        let seen = Set(concepts.map { $0.cluster })
        return Self.clusterOrder.filter { seen.contains($0) }
    }

    private var transcribedCount: Int {
        episodes.filter { $0.transcribed }.count
    }

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowText(text: "\(t("Saved highlights", lang).uppercased()) · \(highlights.count)")
                .padding(.bottom, 12)
            if highlights.isEmpty {
                Text(t("No highlights saved.", lang))
                    .font(.serif(15))
                    .italic()
                    .foregroundColor(Ink.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(highlights.prefix(6)) { h in
                        Button {
                            if let ep = h.episode { store.navigate(to: .episode(ep.id)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\"\(h.quote)\"")
                                    .font(.serif(16))
                                    .italic()
                                    .foregroundColor(Ink.primary)
                                    .lineSpacing(3)
                                HStack(spacing: 8) {
                                    if let show = h.episode?.show {
                                        CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 20, radius: 4)
                                        Text(show.title)
                                            .font(.sans(11.5))
                                            .foregroundColor(Ink.secondary)
                                    }
                                    Text(Fmt.time(h.at))
                                        .font(.mono(10.5))
                                        .foregroundColor(Ink.tertiary)
                                }
                            }
                            .padding(.bottom, 14)
                            .overlay(
                                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1),
                                alignment: .bottom
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(22)
        .glass(.panel)
    }

    private var steveNoticedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowText(text: t("Steve noticed", lang).uppercased()).padding(.bottom, 12)
            let insights = generateInsights()
            if insights.isEmpty {
                Text(t("Listen to and analyze a few more episodes — patterns will start showing up here.", lang))
                    .font(.serif(15))
                    .italic()
                    .foregroundColor(Ink.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(insights) { ins in
                        Button {
                            if let c = ins.concept { selected = c }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(accent)
                                    .font(.system(size: 11))
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ins.tagLabel)
                                        .font(.mono(10.5, weight: .semibold))
                                        .tracking(1)
                                        .foregroundColor(Ink.tertiary)
                                    Text(ins.text)
                                        .font(.serif(14.5))
                                        .foregroundColor(Ink.primary)
                                        .lineSpacing(3)
                                    if let c = ins.concept {
                                        Text("\(t("Open", lang)) \(c) →")
                                            .font(.sans(12.5, weight: .medium))
                                            .foregroundColor(accent)
                                            .padding(.top, 6)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10).fill(.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(22)
        .glass(.panel)
    }

    private struct Insight: Identifiable {
        /// Already-localized eyebrow label (e.g. "RECURRING" / "复现").
        let tagLabel: String
        /// Already-localized full sentence.
        let text: String
        let concept: String?
        var id: String { "\(tagLabel):\(concept ?? "")" }
    }

    private func generateInsights() -> [Insight] {
        guard !concepts.isEmpty else { return [] }
        var out: [Insight] = []
        let isZH = (lang == .zh_Hans)

        if let top = concepts.sorted(by: { $0.count > $1.count }).first, top.count >= 2 {
            let n = top.episodeIDs.count
            let text: String = isZH
                ? "「\(top.name)」在 \(n) 集里反复出现 —— 这是你目前最常听到的概念。"
                : "\"\(top.name)\" appears in \(n) \(n == 1 ? "episode" : "episodes") — your most-discussed idea right now."
            out.append(Insight(tagLabel: t("RECURRING", lang), text: text, concept: top.name))
        }
        if let cross = concepts.first(where: { $0.episodeIDs.count >= 2 && $0.cluster != "Other" }),
           cross.name != out.first?.concept {
            let text: String = isZH
                ? "「\(cross.name)」横跨多个节目 —— 值得把它们串起来写一篇草稿。"
                : "\(cross.name) surfaces across multiple shows — worth pulling them together for a draft."
            out.append(Insight(tagLabel: t("CONNECTION", lang), text: text, concept: cross.name))
        }
        let present = Set(concepts.map { $0.cluster })
        let missing = ["Editorial", "Mind", "Body", "Craft"].first { !present.contains($0) }
        if let m = missing {
            // Cluster name is itself translated — "Editorial" → "编辑" etc.
            let clusterName = t(m, lang)
            let text: String = isZH
                ? "你的「\(clusterName)」分组还是空的。试试转录一集合适的节目。"
                : "Nothing in your \(m) cluster yet. Try transcribing an episode that fits."
            out.append(Insight(tagLabel: t("GAP", lang), text: text, concept: nil))
        }
        return Array(out.prefix(3))
    }
}

private struct GalaxyLayout {
    let nodes: [PositionedNode]
    let clusterCenters: [(cluster: String, point: CGPoint)]
    let edges: [(from: PositionedNode, to: PositionedNode, cluster: String)]
    /// Pre-computed label centers keyed by node name. The label-placement
    /// pass tries right → left → below → above for each node and picks the
    /// first candidate that doesn't overlap another dot or already-placed
    /// label, so dense Chinese labels stop colliding.
    let labelPositions: [String: CGPoint]
}

private struct Galaxy: View {
    let concepts: [Concept]
    @Binding var selected: String?
    @Binding var hovered: String?
    let colors: [String: Color]

    /// Cached layout. `computeLayout` runs an O(n) collision-avoidance
    /// pass for label placement — re-running it on every hover/select
    /// (which fires when SwiftUI invalidates body via @Binding writes)
    /// produced perceptible jank with 30+ concepts. We key the cache on
    /// (concept names + cluster + width + height) so it only
    /// recomputes when something layout-affecting actually changes.
    @State private var cachedLayout: GalaxyLayout? = nil
    @State private var cachedKey: String = ""

    // Zoom state. `userZoom` persists across gesture cycles;
    // `pinchDelta` is the live in-progress magnification value
    // (resets to 1.0 when the gesture ends, after we fold it into
    // `userZoom`). `densityScale` is an automatic prefactor that
    // spreads the canvas as the user accumulates more concepts so
    // they aren't crammed even at 100% zoom.
    @State private var userZoom: CGFloat = 1.0
    @GestureState private var pinchDelta: CGFloat = 1.0

    private var densityScale: CGFloat {
        let n = concepts.count
        if n <= 20 { return 1.0 }
        if n <= 40 { return 1.3 }
        if n <= 80 { return 1.7 }
        return 2.2
    }

    private var effectiveScale: CGFloat {
        max(0.5, min(3.0, densityScale * userZoom * pinchDelta))
    }

    var body: some View {
        GeometryReader { outer in
            let canvasW = max(outer.size.width, outer.size.width * effectiveScale)
            let canvasH = max(outer.size.height, outer.size.height * effectiveScale)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                galaxyCanvas(width: canvasW, height: canvasH)
                    .frame(width: canvasW, height: canvasH)
            }
            // Pinch-to-zoom on trackpad. We use @GestureState for the
            // in-flight delta so it auto-resets when the user lifts
            // their fingers; the final value gets folded into the
            // persistent `userZoom` on .onEnded.
            .gesture(
                MagnificationGesture()
                    .updating($pinchDelta) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        userZoom = max(0.5, min(3.0, userZoom * value))
                    }
            )
            .overlay(alignment: .topTrailing) {
                zoomControls
                    .padding(.top, 10)
                    .padding(.trailing, 14)
            }
        }
        .frame(height: 460)
    }

    /// Top-right zoom chip: − / current% (click to reset) / +.
    /// Mirrors what most Mac canvas apps (Figma, OmniGraffle, Notes)
    /// put in the same corner so users find it without a tutorial.
    @ViewBuilder
    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                userZoom = max(0.5, userZoom - 0.2)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Ink.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(effectiveScale <= 0.5 + 0.01)

            Button {
                userZoom = 1.0
            } label: {
                Text("\(Int((effectiveScale * 100).rounded()))%")
                    .font(.mono(10, weight: .medium))
                    .foregroundColor(Ink.tertiary)
                    .frame(width: 36, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reset zoom")

            Button {
                userZoom = min(3.0, userZoom + 0.2)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Ink.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(effectiveScale >= 3.0 - 0.01)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.28)))
                .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
        )
    }

    /// The actual canvas — pulled out of body so the ScrollView wrapper
    /// can pass an explicit width/height. computeLayout uses these as
    /// its working dimensions, so denser concepts get more room.
    @ViewBuilder
    private func galaxyCanvas(width: CGFloat, height: CGFloat) -> some View {
        let layout = resolveLayout(width: width, height: height)
        ZStack {
                // Aurora per cluster — purely decorative. SwiftUI hit-tests
                // shape outlines (NOT visual alpha), so without this each
                // 340pt aurora swallows hover/tap events for every node
                // sitting inside it. Only one node per canvas was reachable
                // (the one outside any aurora) before this fix.
                ForEach(Array(layout.clusterCenters.enumerated()), id: \.offset) { _, c in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [(colors[c.cluster] ?? .gray).opacity(0.18),
                                         (colors[c.cluster] ?? .gray).opacity(0.04),
                                         .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 170
                            )
                        )
                        .frame(width: 340, height: 340)
                        .position(c.point)
                        .allowsHitTesting(false)
                }

                // Cluster threads — pre-computed. Strokes don't usually
                // hit-test, but disabling explicitly keeps the gesture
                // surface tidy and the intent obvious.
                ForEach(Array(layout.edges.enumerated()), id: \.offset) { _, edge in
                    Path { p in
                        p.move(to: CGPoint(x: edge.from.x, y: edge.from.y))
                        p.addLine(to: CGPoint(x: edge.to.x, y: edge.to.y))
                    }
                    .stroke(
                        (colors[edge.cluster] ?? .gray).opacity(0.16),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                }

                // Nodes — all visuals are .allowsHitTesting(false). Hover
                // + tap routing is handled by a single canvas-wide gesture
                // layer below, which manually finds the nearest node from
                // the cursor position. Per-view .onHover was unreliable
                // when adjacent hit-circles or labels overlapped: SwiftUI
                // didn't always fire hover-out, so hover got "stuck" on
                // the first node the cursor touched.
                ForEach(layout.nodes) { n in
                    let isSelected = selected == n.name
                    let isHover = hovered == n.name
                    let color = colors[n.cluster] ?? .gray

                    ZStack {
                        if isSelected || isHover {
                            Circle().fill(color.opacity(0.16))
                                .frame(width: (n.size + 11) * 2, height: (n.size + 11) * 2)
                        }
                        Circle().fill(color.opacity(0.13))
                            .frame(width: (n.size + 4) * 2, height: (n.size + 4) * 2)
                        Circle()
                            .fill(color.opacity(isSelected ? 1 : 0.88))
                            .overlay(
                                Circle().stroke(
                                    Color.white.opacity(isSelected ? 1 : 0.85),
                                    lineWidth: isSelected ? 2.5 : 1.5
                                )
                            )
                            .frame(width: n.size * 2, height: n.size * 2)
                    }
                    .position(x: n.x, y: n.y)
                    .allowsHitTesting(false)

                    // Label — placed by the layout's collision-avoiding
                    // pass (right / left / below / above), with a
                    // parchment-toned backplate so any unavoidable
                    // overlaps still read cleanly.
                    let labelPos = layout.labelPositions[n.name]
                        ?? CGPoint(x: n.x + n.size + 32, y: n.y)
                    Text(n.name)
                        .font(.sans(11.5, weight: isSelected || isHover ? .semibold : .medium))
                        .foregroundColor(isSelected || isHover ? Ink.primary : Ink.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(Color(hex: "#EFE3CE").opacity(0.82))
                        )
                        .position(labelPos)
                        .allowsHitTesting(false)
                }

                // Single canvas-wide gesture surface. Sits on top so it
                // gets every hover / tap event; manual hit-testing finds
                // the nearest node and updates `hovered` / `selected`.
                // Replaces per-node .onHover, which was getting stuck
                // when adjacent hit-circles overlapped.
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        let next: String?
                        switch phase {
                        case .active(let p): next = Self.hitTest(at: p, layout: layout)
                        case .ended:         next = nil
                        }
                        if hovered != next { hovered = next }
                    }
                    .gesture(
                        SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                            if let target = Self.hitTest(at: value.location, layout: layout) {
                                selected = (selected == target) ? nil : target
                            }
                        }
                    )
            }
    }

    /// Find which node (if any) the cursor is over. Labels are checked
    /// first (they're visually "on top" in the rendering order); falls
    /// through to the dot's generous hit-radius if no label matches. Pure
    /// function — no SwiftUI hover state involved.
    private static func hitTest(at p: CGPoint, layout: GalaxyLayout) -> String? {
        // 1. Label hit (priority — they're on top visually).
        for n in layout.nodes {
            guard let lp = layout.labelPositions[n.name] else { continue }
            let w = estimateLabelWidth(n.name)
            let h: Double = 18
            let pad: Double = 3   // small slack so the edge isn't a dead zone
            if abs(Double(p.x) - Double(lp.x)) <= w / 2 + pad,
               abs(Double(p.y) - Double(lp.y)) <= h / 2 + pad {
                return n.name
            }
        }
        // 2. Dot hit — pick the nearest dot whose hit-circle contains the
        //    cursor. Min radius 16pt so tiny dots stay easy to click.
        var best: (name: String, dist: Double)? = nil
        for n in layout.nodes {
            let dx = n.x - Double(p.x)
            let dy = n.y - Double(p.y)
            let d = (dx * dx + dy * dy).squareRoot()
            let r = max(n.size + 8, 16)
            if d <= r, best == nil || d < best!.dist {
                best = (n.name, d)
            }
        }
        return best?.name
    }

    /// Cache-aware wrapper around `computeLayout`. Returns the
    /// previous result when the layout-affecting inputs are
    /// unchanged. Crucially, `selected` / `hovered` are NOT inputs
    /// to the layout — re-rendering body on hover or selection
    /// should hit this cache.
    private func resolveLayout(width: CGFloat, height: CGFloat) -> GalaxyLayout {
        let key = layoutKey(width: width, height: height)
        if let hit = cachedLayout, cachedKey == key {
            return hit
        }
        let fresh = computeLayout(width: width, height: height)
        // SwiftUI doesn't allow @State writes inside body; defer to
        // the next runloop tick. Even when we return the recomputed
        // `fresh` synchronously now, the cache will hold for the
        // next render pass.
        Task { @MainActor in
            cachedKey = key
            cachedLayout = fresh
        }
        return fresh
    }

    private func layoutKey(width: CGFloat, height: CGFloat) -> String {
        // Round dimensions so sub-pixel window resizes don't bust
        // the cache. Concept identity = name + cluster + count
        // (count drives `size`, so it affects layout via the dot
        // radius even though it doesn't move centers).
        let w = Int(width.rounded())
        let h = Int(height.rounded())
        let conceptPart = concepts
            .map { "\($0.name)|\($0.cluster)|\($0.count)" }
            .joined(separator: "\n")
        return "\(w)x\(h)|\(conceptPart)"
    }

    /// One pass over the concepts. Builds positions, cluster centers, and
    /// nearest-neighbour edges in a single walk so a hover doesn't redo
    /// O(n²) distance work.
    private func computeLayout(width: CGFloat, height: CGFloat) -> GalaxyLayout {
        // 1. Group concepts by cluster while preserving canonical order.
        let grouped = Dictionary(grouping: concepts, by: \.cluster)
        let clusters = ClusterOrder.filter { grouped[$0] != nil }
        guard !clusters.isEmpty else {
            return GalaxyLayout(nodes: [], clusterCenters: [], edges: [], labelPositions: [:])
        }

        let cols = min(clusters.count, 2)
        let rows = max(1, Int(ceil(Double(clusters.count) / Double(cols))))

        var centers: [(String, CGPoint)] = []
        var nodes: [PositionedNode] = []
        var nodesByCluster: [String: [PositionedNode]] = [:]

        for (i, cl) in clusters.enumerated() {
            let col = i % cols
            let row = i / cols
            let cx = (CGFloat(col) + 0.5) / CGFloat(cols) * width
            let cy = (CGFloat(row) + 0.5) / CGFloat(rows) * height
            let center = CGPoint(x: cx, y: cy)
            centers.append((cl, center))

            let items = grouped[cl] ?? []
            var clusterNodes: [PositionedNode] = []
            clusterNodes.reserveCapacity(items.count)
            for (j, c) in items.enumerated() {
                let angle = Double(j) / Double(max(items.count, 1)) * .pi * 2 + Double(cl.count) * 0.7
                let r: Double = 70 + Double(j % 3) * 22 + Double(j % 2) * 8
                let x = Double(center.x) + cos(angle) * r
                let y = Double(center.y) + sin(angle) * r
                let size = 7.0 + Double(min(c.count, 6)) * 1.4
                clusterNodes.append(PositionedNode(name: c.name, cluster: cl, x: x, y: y, size: size))
            }
            nodes.append(contentsOf: clusterNodes)
            nodesByCluster[cl] = clusterNodes
        }

        // 2. Edges: for each node, find its nearest peer within the same cluster.
        //    O(n²) within each cluster, but n is small (typically 1–6 per cluster).
        var edges: [(PositionedNode, PositionedNode, String)] = []
        for (cl, peers) in nodesByCluster where peers.count > 1 {
            for n in peers {
                var best: PositionedNode?
                var bestD = Double.infinity
                for p in peers where p.name != n.name {
                    let d = hypot(p.x - n.x, p.y - n.y)
                    if d < bestD { bestD = d; best = p }
                }
                if let b = best {
                    edges.append((n, b, cl))
                }
            }
        }

        // 3. Label placement. For each node, try 8 anchor positions
        //    (right, left, below, above + 4 diagonals) and pick the
        //    first one whose bounding box doesn't collide with another
        //    dot, with an already-placed label, or with the canvas
        //    edge. If none are clean, fall back to whichever candidate
        //    has the SMALLEST total collision area (rather than always
        //    defaulting to right — that was leaving labels stacked over
        //    neighbouring dots when the cluster was dense).
        //    Bigger dots get processed first so the visually-prominent
        //    labels claim the prime right-of-dot slot; smaller dots
        //    route around them.
        let placeOrder = nodes.indices.sorted { lhs, rhs in
            if nodes[lhs].size != nodes[rhs].size { return nodes[lhs].size > nodes[rhs].size }
            return nodes[lhs].name < nodes[rhs].name   // deterministic on resize
        }
        // Bigger dot margin (8pt vs old 3pt) keeps labels from kissing
        // neighbour glyphs — the old margin let CJK labels touch the
        // adjacent dot's circle.
        let dotBoxes: [Rect] = nodes.map { Rect.dot(p: $0, margin: 8) }
        var placedLabelBoxes: [Rect] = []
        var labelPositions: [String: CGPoint] = [:]
        let labelH: Double = 18
        let gap: Double = 14   // dot-to-label gap
        let diag = gap / 1.4142  // 45° offset = gap / √2

        for idx in placeOrder {
            let n = nodes[idx]
            let w = Self.estimateLabelWidth(n.name)
            // Candidate centers — `.position` anchors at view center.
            // Order encodes preference: right is canonical; left is the
            // first "still aligned with the dot" alternative; vertical
            // comes next; diagonals are last-resort.
            let candidates: [CGPoint] = [
                // Cardinal
                CGPoint(x: n.x + n.size + gap + w / 2,                y: n.y),
                CGPoint(x: n.x - n.size - gap - w / 2,                y: n.y),
                CGPoint(x: n.x,                                       y: n.y + n.size + gap + labelH / 2),
                CGPoint(x: n.x,                                       y: n.y - n.size - gap - labelH / 2),
                // Diagonals (NE, SE, SW, NW)
                CGPoint(x: n.x + n.size + diag + w / 2,               y: n.y - n.size - diag - labelH / 2),
                CGPoint(x: n.x + n.size + diag + w / 2,               y: n.y + n.size + diag + labelH / 2),
                CGPoint(x: n.x - n.size - diag - w / 2,               y: n.y + n.size + diag + labelH / 2),
                CGPoint(x: n.x - n.size - diag - w / 2,               y: n.y - n.size - diag - labelH / 2),
            ]

            var chosen: CGPoint? = nil
            var bestPenalty = Double.infinity
            var bestFallback: CGPoint = candidates[0]

            for cand in candidates {
                let bb = Rect.label(center: cand, width: w, height: labelH, margin: 3)
                // Canvas bounds — 4pt slack at the edge.
                let oobPenalty = max(0, -bb.minX - 4) + max(0, bb.maxX - width - 4)
                                + max(0, -bb.minY - 4) + max(0, bb.maxY - height - 4)
                // Aggregate collision area against dots + previously
                // placed labels. Used both to short-circuit (penalty 0
                // → clean) and to pick the least-bad fallback.
                var penalty = oobPenalty * 4  // edge violations weigh heavier
                for i in dotBoxes.indices where i != idx {
                    penalty += bb.overlapArea(dotBoxes[i])
                }
                for lb in placedLabelBoxes {
                    penalty += bb.overlapArea(lb) * 0.6   // label-on-label is less ugly than label-on-dot
                }
                if penalty <= 0 {
                    chosen = cand
                    break
                }
                if penalty < bestPenalty {
                    bestPenalty = penalty
                    bestFallback = cand
                }
            }

            let final = chosen ?? bestFallback
            placedLabelBoxes.append(Rect.label(center: final, width: w, height: labelH, margin: 3))
            labelPositions[n.name] = final
        }

        return GalaxyLayout(nodes: nodes, clusterCenters: centers,
                            edges: edges, labelPositions: labelPositions)
    }

    /// Approximate the rendered width of a label without measuring text.
    /// Numbers tuned by eye against actual sans 11.5pt CJK + ASCII glyphs;
    /// erring slightly wide is safer than narrow because under-estimates
    /// cause the collision pass to think a label "fits" when it really
    /// kisses the neighbour glyph.
    private static func estimateLabelWidth(_ s: String) -> Double {
        var w: Double = 0
        for u in s.unicodeScalars {
            let v = u.value
            if (0x4E00...0x9FFF).contains(v) ||
               (0x3040...0x30FF).contains(v) ||
               (0xAC00...0xD7AF).contains(v) ||
               (0xFF00...0xFFEF).contains(v) {   // fullwidth punctuation
                w += 13.5      // CJK / hiragana-katakana / hangul / fullwidth
            } else if v < 128 {
                w += 7         // ASCII
            } else {
                w += 9         // misc symbols, accents
            }
        }
        return w + 12          // capsule horizontal padding (5+5) + slack
    }

    private static let ClusterOrder = ["Editorial", "Mind", "Body", "Craft", "Other"]
    private var ClusterOrder: [String] { Self.ClusterOrder }
}

/// Axis-aligned rectangle helper used only by the label-placement pass.
/// Cheaper than CGRect for the inner overlap loop.
private struct Rect {
    let minX, minY, maxX, maxY: Double
    func overlaps(_ o: Rect) -> Bool {
        !(maxX <= o.minX || minX >= o.maxX || maxY <= o.minY || minY >= o.maxY)
    }
    /// Area of intersection in pt². 0 when disjoint. Used by the label
    /// placer to pick the least-bad fallback when no clean slot exists.
    func overlapArea(_ o: Rect) -> Double {
        let dx = max(0, min(maxX, o.maxX) - max(minX, o.minX))
        let dy = max(0, min(maxY, o.maxY) - max(minY, o.minY))
        return dx * dy
    }
    static func dot(p: PositionedNode, margin: Double) -> Rect {
        Rect(minX: p.x - p.size - margin, minY: p.y - p.size - margin,
             maxX: p.x + p.size + margin, maxY: p.y + p.size + margin)
    }
    static func label(center: CGPoint, width: Double, height: Double, margin: Double) -> Rect {
        Rect(minX: Double(center.x) - width / 2 - margin,
             minY: Double(center.y) - height / 2 - margin,
             maxX: Double(center.x) + width / 2 + margin,
             maxY: Double(center.y) + height / 2 + margin)
    }
}

private struct PositionedNode: Identifiable {
    var id: String { name }
    let name: String
    let cluster: String
    let x: Double
    let y: Double
    let size: Double
}

private struct Timeline: View {
    let concepts: [Concept]
    let episodes: [Episode]
    let clusters: [String]
    @Binding var selected: String?
    let colors: [String: Color]

    var body: some View {
        let transcribed = episodes.filter { ($0.aiConcepts?.isEmpty == false) }
        let minDate = transcribed.map(\.pubDate).min() ?? .now
        let maxDate = transcribed.map(\.pubDate).max() ?? .now
        let span = max(1, maxDate.timeIntervalSince(minDate))

        // Precompute lookups ONCE per body:
        //   - `conceptByName`: O(1) concept lookup by name. Replaces
        //     `concepts.first(where:)` inside the per-cluster ForEach,
        //     which was an O(n²) over concepts × episodes.
        //   - `dotsByCluster`: walk all transcribed episodes once and
        //     bucket emitted dots by cluster. Replaces the per-cluster
        //     "filter then flatMap then nested first(where:)" pattern
        //     that scaled poorly with concept count.
        let conceptByName: [String: Concept] = Dictionary(
            concepts.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a }
        )
        var dotsByCluster: [String: [TLDot]] = [:]
        for ep in transcribed {
            guard let names = ep.aiConcepts else { continue }
            for name in names {
                guard let c = conceptByName[name] else { continue }
                dotsByCluster[c.cluster, default: []].append(
                    TLDot(concept: name, ts: ep.pubDate, count: c.count)
                )
            }
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Color.clear.frame(width: 120)
                HStack {
                    Text(Fmt.date(minDate))
                        .font(.mono(10.5))
                        .foregroundColor(Ink.tertiary)
                    Spacer()
                    Text(Fmt.date(maxDate))
                        .font(.mono(10.5))
                        .foregroundColor(Ink.tertiary)
                }
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 8)

            ForEach(clusters, id: \.self) { cluster in
                // Pre-bucketed by `dotsByCluster` above — O(1) lookup.
                let dots: [TLDot] = dotsByCluster[cluster] ?? []
                HStack(alignment: .center, spacing: 0) {
                    HStack(spacing: 8) {
                        Circle().fill(colors[cluster] ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(cluster)
                            .font(.serif(16, weight: .regular))
                            .italic()
                            .foregroundColor(Ink.primary)
                    }
                    .frame(width: 120, alignment: .leading)

                    GeometryReader { geo in
                        ZStack {
                            ForEach([0.25, 0.5, 0.75], id: \.self) { p in
                                Rectangle()
                                    .fill(Color.black.opacity(0.04))
                                    .frame(width: 1)
                                    .position(x: geo.size.width * p, y: geo.size.height / 2)
                            }
                            ForEach(dots) { d in
                                let xRatio = d.ts.timeIntervalSince(minDate) / span
                                let r = 6 + min(d.count, 5) * 1
                                let isSelected = selected == d.concept
                                Circle()
                                    .fill(colors[cluster] ?? .gray)
                                    .opacity(isSelected ? 1 : 0.85)
                                    .frame(width: CGFloat(r) * 2, height: CGFloat(r) * 2)
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: 1.5)
                                    )
                                    .position(x: geo.size.width * xRatio, y: geo.size.height / 2)
                                    .onTapGesture {
                                        selected = isSelected ? nil : d.concept
                                    }
                            }
                        }
                    }
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.04), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private struct TLDot: Identifiable {
        let concept: String
        let ts: Date
        let count: Int
        // Stable, deterministic id — concept + integer timestamp. Survives
        // re-renders so SwiftUI can diff dots and skip redraws.
        var id: String { "\(concept)@\(Int(ts.timeIntervalSince1970))" }
    }
}

private struct ConceptDrawer: View {
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    let concept: Concept
    let episodes: [Episode]
    let shows: [Show]
    let onClose: () -> Void

    @State private var defining: Bool = false
    @State private var defineError: String? = nil
    /// Tracks which concept name the in-flight definition fetch is for —
    /// guards against the user clicking through several concepts in quick
    /// succession landing a stale response on the wrong concept.
    @State private var definingFor: String? = nil

    private static let clusterColors: [String: Color] = [
        "Editorial": Color(hex: "#d06a3a"),
        "Mind": Color(hex: "#0075de"),
        "Body": Color(hex: "#1f7a4c"),
        "Craft": Color(hex: "#7a3a2e"),
        "Other": Color(hex: "#615d59"),
    ]

    var body: some View {
        // Episode-ID lookup as a Set — `concept.episodeIDs` is a
        // [String], `.contains` on it is O(n) per filter step. With
        // a popular concept spanning 20+ episodes and a library of
        // 200+ episodes, that's tens of thousands of comparisons
        // every body re-render. The Set lookup is O(1).
        let episodeIDSet = Set(concept.episodeIDs)
        let mentioned = episodes.filter { episodeIDSet.contains($0.id) }
        let color = Self.clusterColors[concept.cluster] ?? .gray

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(color.opacity(0.22), lineWidth: 4))
                VStack(alignment: .leading, spacing: 0) {
                    EyebrowText(text: t(concept.cluster, lang).uppercased()).padding(.bottom, 2)
                    Text(concept.name)
                        .font(.serif(22, weight: .medium))
                        .foregroundColor(Ink.primary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            // Single scroll container for stats + definition + episode
            // list. Earlier layout put each section as a sibling in the
            // outer VStack, which let a long definition overflow over
            // the episode card (SwiftUI was under-measuring the Text
            // height in a fixed-width drawer). Folding everything into
            // one scroll view also means long Chinese definitions
            // scroll naturally instead of pushing the layout out.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t("Mentioned", lang)).font(.mono(10)).foregroundColor(Ink.tertiary)
                            HStack(spacing: 0) {
                                Text("\(concept.count)")
                                    .font(.serif(22, weight: .medium))
                                Text("×")
                                    .font(.system(size: 13))
                                    .foregroundColor(Ink.tertiary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t("Across", lang)).font(.mono(10)).foregroundColor(Ink.tertiary)
                            HStack(spacing: 4) {
                                Text("\(mentioned.count)")
                                    .font(.serif(22, weight: .medium))
                                Text("ep")
                                    .font(.system(size: 13))
                                    .foregroundColor(Ink.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.bottom, 14)
                    .overlay(
                        Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1),
                        alignment: .bottom
                    )

                    definitionBlock(mentioned: mentioned)

                    EyebrowText(text: t("From the transcripts", lang).uppercased())
                        .padding(.top, 18).padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(mentioned) { ep in
                            if let show = ep.show {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 22, radius: 5)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(ep.title)
                                                .font(.serif(13.5, weight: .medium))
                                                .foregroundColor(Ink.primary)
                                                .lineLimit(1)
                                            Text("\(show.title) · \(Fmt.date(ep.pubDate))")
                                                .font(.mono(10))
                                                .foregroundColor(Ink.tertiary)
                                        }
                                    }
                                    if let summary = ep.aiSummary, !summary.isEmpty {
                                        Text(summary)
                                            .font(.serif(13.5))
                                            .foregroundColor(Ink.secondary)
                                            .lineSpacing(2)
                                            .lineLimit(3)
                                    }
                                    Button {
                                        store.navigate(to: .episode(ep.id))
                                    } label: {
                                        Text(t("Open episode →", lang))
                                    }
                                    .buttonStyle(TextButtonStyle())
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.55))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.05), lineWidth: 1))
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 540)
        }
        .padding(22)
        .glass(.panel)
        // Auto-fetch the definition the first time this drawer renders
        // for a concept that doesn't have one yet.
        .task(id: concept.name) {
            if concept.aiDefinition == nil { await fetchDefinition() }
        }
    }

    @ViewBuilder
    private func definitionBlock(mentioned: [Episode]) -> some View {
        if let def = concept.aiDefinition, !def.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    EyebrowText(text: t("Definition", lang).uppercased())
                    Spacer()
                    Button {
                        Task { await fetchDefinition() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9))
                            Text(t("Regenerate", lang)).font(.mono(10))
                        }
                        .foregroundColor(Ink.tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(defining)
                }
                Text(def)
                    .font(.serif(14.5))
                    .foregroundColor(Ink.primary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    // Tell SwiftUI to claim the full intrinsic height
                    // based on width. Without this, long CJK text was
                    // under-measured and the next section drew on top.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if defining {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowText(text: t("Definition", lang).uppercased())
                HStack(spacing: 6) {
                    Text(t("Defining", lang))
                        .italic()
                    Text("…")
                }
                .font(.serif(14))
                .foregroundColor(Ink.tertiary)
            }
            .padding(.top, 14)
        } else if !summaryConfigured {
            // Quietly skip the block when AI isn't configured — no noisy
            // "configure your key" prompt; the rest of the drawer (counts,
            // episode list) is still useful on its own.
            EmptyView()
        } else if let err = defineError {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowText(text: t("Definition", lang).uppercased())
                Text(err)
                    .font(.sans(12))
                    .foregroundColor(Danger.primary)
                Button(t("Try again", lang)) {
                    Task { await fetchDefinition() }
                }
                .buttonStyle(TextButtonStyle())
            }
            .padding(.top, 14)
        }
    }

    private var summaryConfig: AIClientConfig {
        AIClientConfig(settings: store.settings)
    }
    private var summaryConfigured: Bool {
        !summaryConfig.apiKey.isEmpty && !summaryConfig.model.isEmpty
    }

    @MainActor
    private func fetchDefinition() async {
        guard summaryConfigured else { return }
        // Capture the concept name we're fetching FOR so a late response
        // for a previous concept doesn't clobber the current one.
        let conceptName = concept.name
        definingFor = conceptName
        defining = true
        defineError = nil

        // Gather grounding snippets: prefer each episode's AI summary
        // (already a tight distillation). If none exist, fall back to
        // a SHALLOW transcript scan — at most 200 lines per episode
        // with an early-break in matchCollect, instead of materialising
        // every episode's full sorted transcript and full-scanning.
        // For a popular concept spanning 6 episodes × 2000 lines each,
        // the old path was 12k line allocations + 12k case-insensitive
        // contains() on the MainActor.
        let episodeIDSet = Set(concept.episodeIDs)
        let mentioned = episodes.filter { episodeIDSet.contains($0.id) }
        let mentions: [(episodeTitle: String, snippet: String)] = mentioned.prefix(6).map { ep in
            if let s = ep.aiSummary, !s.isEmpty {
                return (ep.title, s)
            }
            // Shallow scan: walk the relationship lazily, early-break
            // after we've collected 3 matches OR examined 200 lines.
            // Avoids the full sort + full scan for unanalyzed episodes.
            var hits: [String] = []
            var examined = 0
            for line in ep.transcriptLines {
                examined += 1
                if line.text.localizedCaseInsensitiveContains(conceptName) {
                    hits.append(line.text)
                    if hits.count >= 3 { break }
                }
                if examined >= 200 { break }
            }
            return (ep.title, hits.joined(separator: " … "))
        }

        do {
            let def = try await AIService.defineConcept(
                name: conceptName,
                cluster: concept.cluster,
                mentions: mentions,
                config: summaryConfig
            )
            // Discard if the user navigated away mid-flight.
            guard definingFor == conceptName, !def.isEmpty else {
                defining = false
                return
            }
            concept.aiDefinition = def
            concept.aiDefinedAt = .now
            try? modelContext.save()
        } catch {
            if definingFor == conceptName {
                defineError = error.localizedDescription
            }
        }
        defining = false
    }
}
