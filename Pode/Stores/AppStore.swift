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
    /// Global search results page — driven by the sidebar search field.
    case search(String)
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

    /// Last view BEFORE we routed the user to Browse for an iTunes search.
    /// Set only when the sidebar search field navigates them away; never
    /// touched if the user was already on Browse or if they navigate via
    /// other means while a search is active.
    private var preSearchView: AppView = .listenNow
    /// True iff the *current* `.browse` view was entered via the global
    /// search field. Lets us pop back when the user clears the field
    /// without yanking the user out of Browse if they came in directly.
    private var enteredBrowseForSearch: Bool = false

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
        startAutoRefresh()
    }

    /// Background timer that keeps subscribed shows current without
    /// requiring the user to hit Refresh. Fires once shortly after
    /// launch (~5s — long enough that the UI has settled and SwiftData
    /// is ready, short enough that "I just opened the app" matches the
    /// "fetch new episodes" expectation) and then every 30 minutes
    /// while the app is alive.
    private var autoRefreshTask: Task<Void, Never>?

    private func startAutoRefresh() {
        // Single-instance guard — `attach` could theoretically run more
        // than once during hot reload / preview environments.
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { @MainActor [weak self] in
            // Initial delay: don't block app-launch CPU on RSS network IO.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                await self?.refreshAllSubscribed(silent: true)
                // 30 minute interval. Most podcast feeds update at most
                // daily; checking twice an hour is plenty without being
                // wasteful on the user's bandwidth.
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    /// Fetch every subscribed show from SwiftData and refresh them.
    /// `silent: true` suppresses the post-refresh toast — used by the
    /// auto-refresh timer (we don't want a popup every 30 min). The
    /// per-show "N new episodes queued" toast still fires from inside
    /// `refreshShow` if new episodes land.
    func refreshAllSubscribed(silent: Bool = false) async {
        guard let ctx = modelContext else { return }
        let shows = (try? ctx.fetch(FetchDescriptor<Show>())) ?? []
        guard !shows.isEmpty else { return }
        refreshing = true
        for s in shows { await refreshShow(s) }
        refreshing = false
        if !silent {
            toast("Refreshed \(shows.count) \(shows.count == 1 ? "show" : "shows")")
        }
    }

    // MARK: - Search / navigation

    /// Update the global search query and route the user straight to the
    /// Browse page running an iTunes search — same UX as Apple Podcasts.
    /// We don't show an interstitial "search results" page; the sidebar
    /// search box IS the iTunes-podcast search bar.
    ///
    /// Empty query → if we navigated *to* Browse for this search, pop back.
    /// Non-empty query → switch to `.browse` (if not already), then push the
    /// query through `.runiTunesSearch` so BrowseView fires the API call.
    func updateSearch(_ q: String) {
        search = q
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if case .browse = view, enteredBrowseForSearch {
                view = preSearchView
                enteredBrowseForSearch = false
            }
            return
        }

        // Need to be on Browse to run the search.
        if case .browse = view {
            // already there — just deliver the query
        } else {
            preSearchView = view
            enteredBrowseForSearch = true
            view = .browse
        }

        // Defer to the next runloop tick so BrowseView has a chance to mount
        // its `.onReceive(...)` subscription before we post.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .runiTunesSearch,
                object: nil,
                userInfo: ["q": trimmed]
            )
        }
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
            case .transcribeEngine: if let v = r.stringValue { s.transcribeEngine = v }
            case .localWhisperModel: if let v = r.stringValue { s.localWhisperModel = v }
            case .localWhisperPicked: if let v = r.boolValue { s.localWhisperPicked = v }
            case .inferSpeakers: if let v = r.boolValue { s.inferSpeakers = v }
            case .transcribeLanguage: if let v = r.stringValue { s.transcribeLanguage = v }
            case .simplifiedChinese: if let v = r.boolValue { s.simplifiedChinese = v }
            case .summaryProvider: if let v = r.stringValue { s.summaryProvider = v }
            case .geminiKey: s.geminiKey = r.stringValue
            case .customKey: s.customKey = r.stringValue
            case .customBaseURL: if let v = r.stringValue { s.customBaseURL = v }
            case .openaiSummaryModel: if let v = r.stringValue { s.openaiSummaryModel = v }
            case .geminiModel: if let v = r.stringValue { s.geminiModel = v }
            case .customModel: if let v = r.stringValue { s.customModel = v }
            case .appLanguage: if let v = r.stringValue { s.appLanguage = v }
            case .playbackRate: if let v = r.doubleValue { s.playbackRate = v }
            case .none: break
            }
        }
        self.settings = s
        // Restore the user's preferred playback rate on launch so the
        // player picks up where they left off across sessions.
        player.playbackRate = s.playbackRate
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
            (.transcribeEngine, s.transcribeEngine, nil, nil),
            (.localWhisperModel, s.localWhisperModel, nil, nil),
            (.localWhisperPicked, nil, nil, s.localWhisperPicked),
            (.inferSpeakers, nil, nil, s.inferSpeakers),
            (.transcribeLanguage, s.transcribeLanguage, nil, nil),
            (.simplifiedChinese, nil, nil, s.simplifiedChinese),
            (.summaryProvider, s.summaryProvider, nil, nil),
            (.geminiKey, s.geminiKey, nil, nil),
            (.customKey, s.customKey, nil, nil),
            (.customBaseURL, s.customBaseURL, nil, nil),
            (.openaiSummaryModel, s.openaiSummaryModel, nil, nil),
            (.geminiModel, s.geminiModel, nil, nil),
            (.customModel, s.customModel, nil, nil),
            (.appLanguage, s.appLanguage, nil, nil),
            (.playbackRate, nil, s.playbackRate, nil),
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

                // Snapshot whether this show already had episodes BEFORE we
                // start inserting. If empty, this is the first sync (the
                // user just subscribed) and we want to skip auto-queue —
                // otherwise the entire 50-item backlog would land in the
                // queue, which is never what the user wants.
                let existingByID = Dictionary(uniqueKeysWithValues: show.episodes.map { ($0.id, $0) })
                let isFirstSync = existingByID.isEmpty
                var newEpisodes: [Episode] = []
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
                        newEpisodes.append(ep)
                    }
                }
                try? ctx.save()

                // For genuine refreshes (not the initial subscribe), every
                // newly-arrived episode goes to "play next" automatically.
                // Iterating ascending by pubDate puts the newest nearest
                // the queue head (it's the last call → wins position[1]).
                if !isFirstSync, !newEpisodes.isEmpty {
                    let ordered = newEpisodes.sorted { $0.pubDate < $1.pubDate }
                    for ep in ordered {
                        playNext(episode: ep, reason: "auto", silent: true)
                    }
                    toast("\(newEpisodes.count) new \(newEpisodes.count == 1 ? "episode" : "episodes") queued")
                }
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

    /// Start playing an episode. Per the queue model, the episode is moved
    /// (or inserted) at the head of the queue first — so the queue head is
    /// always the currently-playing item.
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
        moveToQueueHead(episodeID: episode.id)
        // Stamp last-played so the Show page knows which episode to resume.
        episode.lastPlayedAt = .now
        try? modelContext?.save()
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

    /// Set the player's speed and persist it to settings so the choice
    /// survives across launches. Routes through the player store (which
    /// pushes the rate onto AVPlayer if currently playing) and updates
    /// `settings.playbackRate` so the next launch restores it.
    func setPlaybackRate(_ newRate: Double) {
        player.setPlaybackRate(newRate)
        var s = settings
        s.playbackRate = newRate
        saveSettings(s)
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
        // Auto-advance: the just-finished item is the queue head; pop it
        // and start the next item if there is one.
        advanceQueue(finishedEpisodeID: episodeID)
    }

    // MARK: - Queue

    /// Sorted queue items (smallest position first). Head = currently
    /// playing. Use this from views to render the queue.
    func loadQueue() -> [QueueItem] {
        guard let ctx = modelContext else { return [] }
        let descriptor = FetchDescriptor<QueueItem>(
            sortBy: [SortDescriptor(\QueueItem.position, order: .forward)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }

    /// Append an episode at the tail of the queue. No-op if it's already in
    /// the queue. `silent` skips the user-visible toast — the auto-queue
    /// path uses it because it issues one summary toast per refresh.
    @discardableResult
    func enqueue(episode: Episode, reason: String = "manual", silent: Bool = false) -> Bool {
        guard let ctx = modelContext else { return false }
        if existingQueueItem(for: episode.id, in: ctx) != nil {
            if !silent { toast("Already in queue") }
            return false
        }
        let items = loadQueue()
        let nextPos = (items.last?.position ?? 0) + 1000
        let item = QueueItem(id: episode.id, position: nextPos, addedReason: reason)
        item.episode = episode
        ctx.insert(item)
        try? ctx.save()
        if !silent { toast("Added to queue") }
        return true
    }

    /// Insert an episode right *after* the currently-playing item (i.e. at
    /// position 1 of the upcoming list). Used by "Play next" affordance
    /// and by per-show autoQueue=top on refresh.
    func playNext(episode: Episode, reason: String = "manual", silent: Bool = false) {
        guard let ctx = modelContext else { return }
        let items = loadQueue()
        // Remove any existing entry first so it can move.
        if let existing = existingQueueItem(for: episode.id, in: ctx) {
            ctx.delete(existing)
        }
        // Place between head (position[0]) and the next item.
        let head = items.first(where: { $0.id != episode.id })?.position
        let second = items.dropFirst().first(where: { $0.id != episode.id })?.position
        let pos: Int
        switch (head, second) {
        case (let h?, let s?): pos = (h + s) / 2 == h ? h + 1 : (h + s) / 2
        case (let h?, nil):    pos = h + 1000
        case (nil, _):         pos = 0
        }
        let item = QueueItem(id: episode.id, position: pos, addedReason: reason)
        item.episode = episode
        ctx.insert(item)
        try? ctx.save()
        if !silent { toast("Playing next") }
    }

    /// Move an episode to the head of the queue (the currently-playing
    /// slot). Used internally by `startPlaying`.
    func moveToQueueHead(episodeID: String) {
        guard let ctx = modelContext else { return }
        let items = loadQueue()
        let headPos = items.first?.position ?? 0
        // Remove any existing entry, regardless of position.
        if let existing = existingQueueItem(for: episodeID, in: ctx) {
            // If already at head, no-op.
            if existing.position == headPos { return }
            ctx.delete(existing)
        }
        // Fetch the episode reference to wire the relationship.
        let epDescriptor = FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.id == episodeID })
        let ep = try? ctx.fetch(epDescriptor).first
        let item = QueueItem(id: episodeID, position: headPos - 1000, addedReason: "manual")
        item.episode = ep
        ctx.insert(item)
        try? ctx.save()
    }

    /// Remove an episode from the queue.
    func removeFromQueue(episodeID: String) {
        guard let ctx = modelContext else { return }
        if let item = existingQueueItem(for: episodeID, in: ctx) {
            ctx.delete(item)
            try? ctx.save()
        }
    }

    /// Move an item from one queue index to another (drag-to-reorder).
    /// `from` is an `IndexSet` to match SwiftUI's `.onMove(perform:)` API.
    func reorderQueue(from source: IndexSet, to destination: Int) {
        guard let ctx = modelContext else { return }
        var items = loadQueue()
        items.move(fromOffsets: source, toOffset: destination)
        // Renumber with a 1000-wide gap so future inserts have room.
        for (i, item) in items.enumerated() {
            item.position = i * 1000
        }
        try? ctx.save()
    }

    /// Clear the entire queue. Doesn't touch the currently-playing player.
    func clearQueue() {
        guard let ctx = modelContext else { return }
        for item in loadQueue() {
            ctx.delete(item)
        }
        try? ctx.save()
    }

    /// Pop the head (just-finished episode) and start the next one. Called
    /// from `markFinished` on `onFinished`.
    private func advanceQueue(finishedEpisodeID: String) {
        guard let ctx = modelContext else { return }
        // Remove the just-finished head item.
        if let head = existingQueueItem(for: finishedEpisodeID, in: ctx) {
            ctx.delete(head)
            try? ctx.save()
        }
        // Pick the new head (smallest position) and play it.
        let items = loadQueue()
        guard let next = items.first, let ep = next.episode else {
            // Queue is empty — stop.
            player.teardown()
            return
        }
        startPlaying(ep)
    }

    private func existingQueueItem(for id: String, in ctx: ModelContext) -> QueueItem? {
        let descriptor = FetchDescriptor<QueueItem>(
            predicate: #Predicate<QueueItem> { $0.id == id }
        )
        return try? ctx.fetch(descriptor).first
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
