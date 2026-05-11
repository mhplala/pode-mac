import Foundation
import SwiftData

@Model
final class Show {
    @Attribute(.unique) var id: String
    var title: String
    var host: String
    var publisher: String?
    var feedUrl: String
    var artworkUrl: String
    var showDescription: String?
    var category: String?
    var itunesId: Int?
    var addedAt: Date
    /// What to do when this show's RSS gains a new episode. Values are
    /// `AutoQueueMode.rawValue`: `"off"` / `"top"` / `"bottom"`.
    /// Stored as String (not enum) so SwiftData doesn't need to migrate
    /// when we add a future mode.
    var autoQueue: String = "off"

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    var episodes: [Episode] = []

    init(id: String, title: String, host: String, feedUrl: String, artworkUrl: String,
         publisher: String? = nil, showDescription: String? = nil,
         category: String? = nil, itunesId: Int? = nil, addedAt: Date = .now,
         autoQueue: String = "off") {
        self.id = id
        self.title = title
        self.host = host
        self.feedUrl = feedUrl
        self.artworkUrl = artworkUrl
        self.publisher = publisher
        self.showDescription = showDescription
        self.category = category
        self.itunesId = itunesId
        self.addedAt = addedAt
        self.autoQueue = autoQueue
    }
}

enum AutoQueueMode: String, CaseIterable, Identifiable {
    case off, top, bottom
    var id: String { rawValue }
}

@Model
final class Episode {
    @Attribute(.unique) var id: String
    var guid: String
    var title: String
    var episodeDescription: String?
    var pubDate: Date
    var duration: Double  // seconds
    var audioUrl: String
    var audioType: String?
    var audioSize: Int64?

    var played: Double = 0   // 0..1
    var position: Double = 0 // seconds
    /// Last time the user pressed Play on this episode. Used by the Show
    /// page's "Resume" button to pick which episode to continue. Optional
    /// so existing rows from before this field migrate cleanly to nil.
    var lastPlayedAt: Date?

    var downloaded: Bool = false
    var downloadedAt: Date?
    var localFilePath: String?

    var transcribed: Bool = false
    var transcribedAt: Date?

    var aiSummary: String?
    var aiTakeaways: [String]?
    var aiConcepts: [String]?

    var show: Show?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptLineModel.episode)
    var transcriptLines: [TranscriptLineModel] = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.episode)
    var highlights: [Highlight] = []

    /// Transcript lines in audio-time order. We sort on `t` (not
    /// `lineIndex`) because live streaming inserts lines as the WhisperKit
    /// VAD pipeline discovers them, which is parallel + out-of-order.
    /// `lineIndex` is kept as a stable unique identity for SwiftUI
    /// ForEach but is no longer a sort key.
    var sortedTranscriptLines: [TranscriptLineModel] {
        transcriptLines.sorted { $0.t < $1.t }
    }

    init(id: String, guid: String, title: String, pubDate: Date, duration: Double, audioUrl: String,
         episodeDescription: String? = nil, audioType: String? = nil, audioSize: Int64? = nil) {
        self.id = id
        self.guid = guid
        self.title = title
        self.pubDate = pubDate
        self.duration = duration
        self.audioUrl = audioUrl
        self.episodeDescription = episodeDescription
        self.audioType = audioType
        self.audioSize = audioSize
    }
}

@Model
final class TranscriptLineModel {
    var t: Double
    var text: String
    var speaker: String?
    var lineIndex: Int

    var episode: Episode?

    init(t: Double, text: String, speaker: String? = nil, lineIndex: Int) {
        self.t = t
        self.text = text
        self.speaker = speaker
        self.lineIndex = lineIndex
    }
}

@Model
final class Highlight {
    @Attribute(.unique) var id: String
    var at: Double  // seconds
    var quote: String
    var note: String?
    var createdAt: Date

    var episode: Episode?

    init(id: String, at: Double, quote: String, note: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.at = at
        self.quote = quote
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class Concept {
    @Attribute(.unique) var name: String
    var cluster: String
    var count: Int
    var episodeIDs: [String]
    var firstSeen: Date
    /// LLM-generated short definition shown in `ConceptDrawer`. Generated
    /// lazily on first drawer-open; preserved by `AppStore.rebuildConcepts`
    /// across rebuilds (which would otherwise wipe it).
    var aiDefinition: String?
    var aiDefinedAt: Date?

    init(name: String, cluster: String, count: Int = 1, episodeIDs: [String] = [], firstSeen: Date = .now,
         aiDefinition: String? = nil, aiDefinedAt: Date? = nil) {
        self.name = name
        self.cluster = cluster
        self.count = count
        self.episodeIDs = episodeIDs
        self.firstSeen = firstSeen
        self.aiDefinition = aiDefinition
        self.aiDefinedAt = aiDefinedAt
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var key: String
    var stringValue: String?
    var doubleValue: Double?
    var boolValue: Bool?

    init(key: String, stringValue: String? = nil, doubleValue: Double? = nil, boolValue: Bool? = nil) {
        self.key = key
        self.stringValue = stringValue
        self.doubleValue = doubleValue
        self.boolValue = boolValue
    }
}

/// Persistent listening queue. The smallest-`position` item is the
/// currently-playing episode (head); items behind it are "Up next" in
/// `position` order. New inserts at head get `head.position - 1000` and at
/// the tail get `tail.position + 1000`, so we almost never have to renumber.
@Model
final class QueueItem {
    /// = `episode.id`. Lets us upsert by episode without holding a stale
    /// reference; also enforces "an episode appears at most once in queue".
    @Attribute(.unique) var id: String
    var position: Int
    var addedAt: Date
    /// "manual" — user added (or click-to-play insert at head).
    /// "auto"   — auto-enqueued by a Show's `autoQueue` rule on refresh.
    var addedReason: String

    var episode: Episode?

    init(id: String, position: Int, addedReason: String = "manual", addedAt: Date = .now) {
        self.id = id
        self.position = position
        self.addedReason = addedReason
        self.addedAt = addedAt
    }
}
