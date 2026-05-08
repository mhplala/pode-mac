import Foundation
import SwiftData
import Observation
import SwiftUI

enum AppView: Hashable {
    case listenNow
    case browse
    case library
    case knowledge
    case settings
    case show(String)
    case episode(String)
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
}

@Observable
final class AppStore {
    var view: AppView = .listenNow
    var search: String = ""
    var settings: AppSettings = AppSettings()
    var toasts: [ToastItem] = []
    var refreshing: Bool = false

    let player: AudioPlayerStore

    private var modelContext: ModelContext?

    // Throttle SwiftData writes during playback. Periodic time observer fires
    // every 0.5s; we only need to persist position every ~5s. Final position
    // is also written on pause/teardown so we never lose progress.
    private var lastPositionSaveAt: Date = .distantPast
    private let positionSaveInterval: TimeInterval = 5.0

    init(player: AudioPlayerStore) {
        self.player = player
        player.onPositionChanged = { [weak self] id, t, dur in
            self?.maybePersistPlaybackPosition(episodeID: id, time: t, duration: dur)
        }
        player.onFinished = { [weak self] id in
            self?.markFinished(episodeID: id)
        }
        player.onWillStop = { [weak self] id, t, dur in
            self?.persistPlaybackPosition(episodeID: id, time: t, duration: dur)
            self?.lastPositionSaveAt = .now
        }
    }

    func attach(_ ctx: ModelContext) {
        self.modelContext = ctx
        loadSettings()
    }

    // MARK: - Toast

    func toast(_ message: String) {
        let t = ToastItem(message: message)
        toasts.append(t)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.toasts.removeAll { $0.id == t.id }
        }
    }

    // MARK: - Settings

    func loadSettings() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<AppSettingsRecord>()
        guard let records = try? ctx.fetch(descriptor) else { return }
        var s = AppSettings()
        for r in records {
            switch SettingsKey(rawValue: r.key) {
            case .openaiKey: s.openaiKey = r.stringValue
            case .anthropicKey: s.anthropicKey = r.stringValue
            case .whisperModel: if let v = r.stringValue { s.whisperModel = v }
            case .claudeModel: if let v = r.stringValue { s.claudeModel = v }
            case .accentHex: if let v = r.stringValue { s.accentHex = v }
            case .bloomStrength: if let v = r.doubleValue { s.bloomStrength = v }
            case .glassBlur: if let v = r.doubleValue { s.glassBlur = v }
            case .showSecondaryBloom: if let v = r.boolValue { s.showSecondaryBloom = v }
            case .userName: if let v = r.stringValue { s.userName = v }
            case .none: break
            }
        }
        self.settings = s
    }

    func saveSettings(_ s: AppSettings) {
        guard let ctx = modelContext else { return }
        self.settings = s
        let pairs: [(SettingsKey, String?, Double?, Bool?)] = [
            (.openaiKey, s.openaiKey, nil, nil),
            (.anthropicKey, s.anthropicKey, nil, nil),
            (.whisperModel, s.whisperModel, nil, nil),
            (.claudeModel, s.claudeModel, nil, nil),
            (.accentHex, s.accentHex, nil, nil),
            (.bloomStrength, nil, s.bloomStrength, nil),
            (.glassBlur, nil, s.glassBlur, nil),
            (.showSecondaryBloom, nil, nil, s.showSecondaryBloom),
            (.userName, s.userName, nil, nil),
        ]
        for (key, str, dbl, bln) in pairs {
            let keyString = key.rawValue
            let descriptor = FetchDescriptor<AppSettingsRecord>(
                predicate: #Predicate<AppSettingsRecord> { $0.key == keyString }
            )
            if let existing = (try? ctx.fetch(descriptor))?.first {
                existing.stringValue = str
                existing.doubleValue = dbl
                existing.boolValue = bln
            } else {
                ctx.insert(AppSettingsRecord(key: key.rawValue, stringValue: str, doubleValue: dbl, boolValue: bln))
            }
        }
        try? ctx.save()
    }

    // MARK: - Subscriptions

    func subscribe(feedUrl: String, hint: (title: String, host: String, artworkUrl: String, category: String?, itunesId: Int?)? = nil) async -> Show? {
        guard let ctx = modelContext else { return nil }
        let id = IDFactory.showId(feedUrl: feedUrl)
        let descriptor = FetchDescriptor<Show>(predicate: #Predicate<Show> { $0.id == id })
        if let existing = try? ctx.fetch(descriptor).first {
            await MainActor.run { self.toast("Already subscribed to \(existing.title)") }
            return existing
        }
        do {
            let parsed = try await RSSService.fetchAndParse(feedUrl: feedUrl)
            let show = Show(
                id: id,
                title: hint?.title ?? parsed.show.title,
                host: hint?.host ?? parsed.show.host,
                feedUrl: feedUrl,
                artworkUrl: hint?.artworkUrl ?? parsed.show.artworkUrl,
                publisher: parsed.show.publisher,
                showDescription: parsed.show.description,
                category: hint?.category ?? parsed.show.category,
                itunesId: hint?.itunesId
            )
            await MainActor.run {
                ctx.insert(show)
                let limit = min(parsed.episodes.count, 50)
                for raw in parsed.episodes.prefix(limit) {
                    let epId = IDFactory.episodeId(showId: id, guid: raw.guid)
                    let ep = Episode(
                        id: epId,
                        guid: raw.guid,
                        title: raw.title,
                        pubDate: raw.pubDate,
                        duration: raw.duration,
                        audioUrl: raw.audioUrl,
                        episodeDescription: raw.description,
                        audioType: raw.audioType,
                        audioSize: raw.audioSize
                    )
                    ep.show = show
                    ctx.insert(ep)
                }
                try? ctx.save()
                self.toast("Subscribed to \(show.title)")
            }
            return show
        } catch {
            await MainActor.run { self.toast("Couldn't fetch feed: \(error.localizedDescription)") }
            return nil
        }
    }

    func unsubscribe(showId: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Show>(predicate: #Predicate<Show> { $0.id == showId })
        if let s = try? ctx.fetch(descriptor).first {
            ctx.delete(s)
            try? ctx.save()
            toast("Unsubscribed")
        }
    }

    func refreshShow(_ show: Show) async {
        guard let ctx = modelContext else { return }
        do {
            let parsed = try await RSSService.fetchAndParse(feedUrl: show.feedUrl)
            await MainActor.run {
                show.title = parsed.show.title.isEmpty ? show.title : parsed.show.title
                show.host = parsed.show.host.isEmpty ? show.host : parsed.show.host
                show.artworkUrl = parsed.show.artworkUrl.isEmpty ? show.artworkUrl : parsed.show.artworkUrl
                show.showDescription = parsed.show.description ?? show.showDescription

                let existingByID = Dictionary(uniqueKeysWithValues: show.episodes.map { ($0.id, $0) })
                for raw in parsed.episodes.prefix(50) {
                    let epId = IDFactory.episodeId(showId: show.id, guid: raw.guid)
                    if let existing = existingByID[epId] {
                        existing.title = raw.title
                        existing.pubDate = raw.pubDate
                        existing.duration = raw.duration > 0 ? raw.duration : existing.duration
                        existing.audioUrl = raw.audioUrl.isEmpty ? existing.audioUrl : raw.audioUrl
                        existing.episodeDescription = raw.description ?? existing.episodeDescription
                    } else {
                        let ep = Episode(
                            id: epId, guid: raw.guid, title: raw.title,
                            pubDate: raw.pubDate, duration: raw.duration, audioUrl: raw.audioUrl,
                            episodeDescription: raw.description, audioType: raw.audioType, audioSize: raw.audioSize
                        )
                        ep.show = show
                        ctx.insert(ep)
                    }
                }
                try? ctx.save()
            }
        } catch {
            await MainActor.run { self.toast("Refresh failed: \(error.localizedDescription)") }
        }
    }

    func refreshAll(shows: [Show]) async {
        await MainActor.run { self.refreshing = true }
        for s in shows { await refreshShow(s) }
        await MainActor.run {
            self.refreshing = false
            self.toast("Refreshed \(shows.count) \(shows.count == 1 ? "show" : "shows")")
        }
    }

    // MARK: - Playback

    func startPlaying(_ episode: Episode) {
        let source: URL
        if episode.downloaded, let path = episode.localFilePath, FileManager.default.fileExists(atPath: path) {
            source = URL(fileURLWithPath: path)
        } else if let url = URL(string: episode.audioUrl) {
            source = url
        } else {
            toast("Bad audio URL")
            return
        }
        if player.currentEpisodeID == episode.id {
            player.play()
            return
        }
        player.load(episodeID: episode.id, source: source, startAt: episode.position)
        player.play()
    }

    func togglePlay(_ episode: Episode) {
        if player.currentEpisodeID == episode.id {
            player.toggle()
        } else {
            startPlaying(episode)
        }
    }

    private func maybePersistPlaybackPosition(episodeID: String, time: Double, duration: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastPositionSaveAt) >= positionSaveInterval else { return }
        lastPositionSaveAt = now
        persistPlaybackPosition(episodeID: episodeID, time: time, duration: duration)
    }

    private func persistPlaybackPosition(episodeID: String, time: Double, duration: Double) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.id == episodeID })
        guard let ep = try? ctx.fetch(descriptor).first else { return }
        ep.position = time
        let dur = duration > 0 ? duration : ep.duration
        ep.played = dur > 0 ? min(1, max(0, time / dur)) : ep.played
        try? ctx.save()
    }

    /// Force-flush the current playback position. Called when user pauses,
    /// switches episodes, or the app is about to background.
    func flushPlaybackPosition() {
        guard let id = player.currentEpisodeID else { return }
        persistPlaybackPosition(episodeID: id, time: player.currentTime, duration: player.duration)
        lastPositionSaveAt = .now
    }

    private func markFinished(episodeID: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.id == episodeID })
        guard let ep = try? ctx.fetch(descriptor).first else { return }
        ep.played = 1
        ep.position = ep.duration
        try? ctx.save()
    }

    // MARK: - Highlights

    func saveHighlight(episode: Episode, at: Double, quote: String, note: String? = nil) {
        guard let ctx = modelContext else { return }
        let h = Highlight(
            id: "hl_\(UUID().uuidString)",
            at: at, quote: quote, note: note
        )
        h.episode = episode
        ctx.insert(h)
        try? ctx.save()
        toast("Highlight saved")
    }

    func deleteHighlight(_ h: Highlight) {
        guard let ctx = modelContext else { return }
        ctx.delete(h)
        try? ctx.save()
    }

    // MARK: - Concepts

    func rebuildConcepts() {
        guard let ctx = modelContext else { return }
        let conceptDescriptor = FetchDescriptor<Concept>()
        if let existing = try? ctx.fetch(conceptDescriptor) {
            for c in existing { ctx.delete(c) }
        }
        // Only fetch episodes that have AI concepts.
        let epDescriptor = FetchDescriptor<Episode>()
        guard let allEpisodes = try? ctx.fetch(epDescriptor) else {
            try? ctx.save()
            return
        }
        var bucket: [String: Concept] = [:]
        for ep in allEpisodes {
            guard let names = ep.aiConcepts, !names.isEmpty else { continue }
            for name in names {
                if let existing = bucket[name] {
                    existing.count += 1
                    if !existing.episodeIDs.contains(ep.id) {
                        existing.episodeIDs.append(ep.id)
                    }
                } else {
                    let cluster = Self.inferCluster(name: name)
                    let c = Concept(name: name, cluster: cluster, count: 1,
                                    episodeIDs: [ep.id],
                                    firstSeen: ep.transcribedAt ?? ep.pubDate)
                    bucket[name] = c
                    ctx.insert(c)
                }
            }
        }
        try? ctx.save()
    }

    static func inferCluster(name: String) -> String {
        let lc = name.lowercased()
        if let _ = lc.range(of: #"sleep|brain|memor|attent|circad|caffein|hippoc|neuro|cortis|hormone|exerc"#, options: .regularExpression) { return "Body" }
        if let _ = lc.range(of: #"percept|conscious|cogniti|mind|predict|halluc|ego|self|distribut"#, options: .regularExpression) { return "Mind" }
        if let _ = lc.range(of: #"sound|audio|noise|acoust|produc|production|mix|record|voice memo|layered"#, options: .regularExpression) { return "Craft" }
        if let _ = lc.range(of: #"writ|read|note|essay|web|blog|edit|canon|link|index card|atomic|slow"#, options: .regularExpression) { return "Editorial" }
        return "Other"
    }

    private func inferCluster(name: String) -> String { Self.inferCluster(name: name) }
}
