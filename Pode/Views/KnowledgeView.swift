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
                store.view = .library
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
                    Text(cl)
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
                            if let ep = h.episode { store.view = .episode(ep.id) }
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
                                    Text(ins.tag.uppercased())
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
        let tag: String
        let text: String
        let concept: String?
        var id: String { "\(tag):\(concept ?? "")" }
    }

    private func generateInsights() -> [Insight] {
        guard !concepts.isEmpty else { return [] }
        var out: [Insight] = []
        if let top = concepts.sorted(by: { $0.count > $1.count }).first, top.count >= 2 {
            out.append(Insight(
                tag: "recurring",
                text: "\"\(top.name)\" appears in \(top.episodeIDs.count) \(top.episodeIDs.count == 1 ? "episode" : "episodes") — your most-discussed idea right now.",
                concept: top.name
            ))
        }
        if let cross = concepts.first(where: { $0.episodeIDs.count >= 2 && $0.cluster != "Other" }),
           cross.name != out.first?.concept {
            out.append(Insight(
                tag: "connection",
                text: "\(cross.name) surfaces across multiple shows — worth pulling them together for a draft.",
                concept: cross.name
            ))
        }
        let present = Set(concepts.map { $0.cluster })
        let missing = ["Editorial", "Mind", "Body", "Craft"].first { !present.contains($0) }
        if let m = missing {
            out.append(Insight(
                tag: "gap",
                text: "Nothing in your \(m) cluster yet. Try transcribing an episode that fits.",
                concept: nil
            ))
        }
        return Array(out.prefix(3))
    }
}

private struct GalaxyLayout {
    let nodes: [PositionedNode]
    let clusterCenters: [(cluster: String, point: CGPoint)]
    let edges: [(from: PositionedNode, to: PositionedNode, cluster: String)]
}

private struct Galaxy: View {
    let concepts: [Concept]
    @Binding var selected: String?
    @Binding var hovered: String?
    let colors: [String: Color]

    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout(width: geo.size.width, height: geo.size.height)

            ZStack {
                // Aurora per cluster
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
                }

                // Cluster threads — pre-computed
                ForEach(Array(layout.edges.enumerated()), id: \.offset) { _, edge in
                    Path { p in
                        p.move(to: CGPoint(x: edge.from.x, y: edge.from.y))
                        p.addLine(to: CGPoint(x: edge.to.x, y: edge.to.y))
                    }
                    .stroke(
                        (colors[edge.cluster] ?? .gray).opacity(0.16),
                        lineWidth: 1
                    )
                }

                // Nodes
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
                    .onTapGesture {
                        selected = isSelected ? nil : n.name
                    }
                    .onHover { hovered = $0 ? n.name : (hovered == n.name ? nil : hovered) }

                    // Label
                    Text(n.name)
                        .font(.sans(11.5, weight: isSelected || isHover ? .semibold : .medium))
                        .foregroundColor(isSelected || isHover ? Ink.primary : Ink.secondary)
                        .position(x: n.x + n.size + 30, y: n.y)
                }
            }
        }
        .frame(height: 460)
    }

    /// One pass over the concepts. Builds positions, cluster centers, and
    /// nearest-neighbour edges in a single walk so a hover doesn't redo
    /// O(n²) distance work.
    private func computeLayout(width: CGFloat, height: CGFloat) -> GalaxyLayout {
        // 1. Group concepts by cluster while preserving canonical order.
        let grouped = Dictionary(grouping: concepts, by: \.cluster)
        let clusters = ClusterOrder.filter { grouped[$0] != nil }
        guard !clusters.isEmpty else {
            return GalaxyLayout(nodes: [], clusterCenters: [], edges: [])
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
        return GalaxyLayout(nodes: nodes, clusterCenters: centers, edges: edges)
    }

    private static let ClusterOrder = ["Editorial", "Mind", "Body", "Craft", "Other"]
    private var ClusterOrder: [String] { Self.ClusterOrder }
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
                let conceptsInCluster = concepts.filter { $0.cluster == cluster }.map(\.name)
                let dots: [TLDot] = transcribed.flatMap { ep -> [TLDot] in
                    guard let names = ep.aiConcepts else { return [] }
                    return names.compactMap { name in
                        guard conceptsInCluster.contains(name),
                              let c = concepts.first(where: { $0.name == name }) else { return nil }
                        return TLDot(concept: name, ts: ep.pubDate, count: c.count)
                    }
                }
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
    let concept: Concept
    let episodes: [Episode]
    let shows: [Show]
    let onClose: () -> Void

    private static let clusterColors: [String: Color] = [
        "Editorial": Color(hex: "#d06a3a"),
        "Mind": Color(hex: "#0075de"),
        "Body": Color(hex: "#1f7a4c"),
        "Craft": Color(hex: "#7a3a2e"),
        "Other": Color(hex: "#615d59"),
    ]

    var body: some View {
        let mentioned = episodes.filter { concept.episodeIDs.contains($0.id) }
        let color = Self.clusterColors[concept.cluster] ?? .gray

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(color.opacity(0.22), lineWidth: 4))
                VStack(alignment: .leading, spacing: 0) {
                    EyebrowText(text: concept.cluster).padding(.bottom, 2)
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

            EyebrowText(text: t("From the transcripts", lang).uppercased())
                .padding(.top, 14).padding(.bottom, 10)

            ScrollView {
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
                                    store.view = .episode(ep.id)
                                } label: {
                                    Text(t("Open episode →", lang))
                                }
                                .buttonStyle(TextButtonStyle())
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.55))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.05), lineWidth: 1))
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(22)
        .glass(.panel)
    }
}
