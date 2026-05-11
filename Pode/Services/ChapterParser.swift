import Foundation

/// One parsed timestamp from an episode's description (or an explicit
/// chapter feed). Timestamp `t` is seconds from the start of the audio.
struct Chapter: Hashable, Identifiable {
    let t: Double
    let title: String
    var id: Double { t }
}

/// Pulls chapter / timestamped section markers out of a podcast description.
///
/// Real-world podcast descriptions are wildly inconsistent. The parser
/// scans the entire description for time-shaped tokens (`HH:MM:SS` /
/// `MM:SS`) anywhere they appear — start of a line, mid-paragraph,
/// embedded in a list item, wrapped in HTML — and uses the gap between
/// successive timestamps as each chapter's title text.
///
/// To keep prose-y mentions like "we talked at 12:30 about X" from
/// polluting the result, two safety filters are applied:
///
/// 1. There must be **at least two** time tokens in the description
///    (a single bare time in running text is almost never a chapter).
/// 2. Tokens must be **monotonically ascending**; any timestamp less
///    than the previous one is dropped as a likely false positive.
///
/// Inputs are HTML-stripped and full-width colon `：` is normalized to
/// `:` before scanning, so feeds that ship `<p>00：02：00 标题</p>`
/// parse exactly the same as `00:02:00 标题`.
enum ChapterParser {
    /// Tiny LRU-ish cache keyed by description text. The dock re-renders
    /// at ~2Hz during playback and `.body` runs the parser each time —
    /// without caching, a 50KB description means the regex + HTML strip
    /// run twice a second, which is enough to wedge layout on entry to
    /// long episodes.
    private static let cacheLock = NSLock()
    private static var cache: [String: [Chapter]] = [:]
    /// Hard-cap the cache size so we don't retain every description the
    /// user has ever scrolled past.
    private static let cacheLimit = 64

    /// Parse chapters out of `description`. `episodeDuration` bounds
    /// the upper time so a stale timestamp from a different cut of the
    /// episode doesn't end up rendered as a chapter past the end of
    /// the audio.
    static func chapters(from description: String?, episodeDuration: Double) -> [Chapter] {
        guard let raw = description, !raw.isEmpty else { return [] }

        // Cache key combines description + duration bound so we don't
        // serve stale chapter sets when the episode's duration was
        // updated post-RSS-refresh.
        let key = "\(Int(episodeDuration))::\(raw)"
        cacheLock.lock()
        if let hit = cache[key] { cacheLock.unlock(); return hit }
        cacheLock.unlock()

        let result = computeChapters(from: raw, episodeDuration: episodeDuration)

        cacheLock.lock()
        if cache.count >= cacheLimit {
            // Cheap eviction: drop everything. Avoids tracking access
            // order; the next round of episodes refills naturally.
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = result
        cacheLock.unlock()
        return result
    }

    private static func computeChapters(from raw: String, episodeDuration: Double) -> [Chapter] {

        // Normalize for *parsing only* — display still uses the original
        // text. HTML strip yields newlines for block-level tags so things
        // that were `<p>...</p>` end up on their own lines, which keeps
        // titles from running into each other.
        var text = HTMLStripper.toPlainText(raw)
        // Full-width colons (Chinese fullwidth `：`) are very common in
        // Chinese podcast feeds: `00：02：00 标题`. Treat as ASCII colon.
        text = text.replacingOccurrences(of: "：", with: ":")

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Time-shaped tokens must:
        //   - be at start-of-string OR preceded by whitespace / common
        //     punctuation (so `12:30` inside `用了 12:30 比例` requires the
        //     whitespace boundary, but stuff like `,06:20`, `；06:20` works)
        //   - be followed by whitespace / a separator / sentence boundary
        //     (so we don't grab `12:30比例` where the time slammed into
        //     CJK text — that's prose, not a chapter)
        let leading  = #"(?:^|[\s,，、。;；()\.\[\]【】])"#
        let timeCap  = #"((?:\d{1,2}:)?\d{1,2}:\d{1,2})"#
        let trailing = #"(?=[\s\-—–·:|\.,，。)\]】]|$)"#
        guard let regex = try? NSRegularExpression(
            pattern: leading + timeCap + trailing,
            options: []
        ) else { return [] }

        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard matches.count >= 2 else { return [] }

        // Pull out (seconds, time-token range) for every match.
        struct Hit { let t: Double; let start: Int; let end: Int }
        var hits: [Hit] = []
        for m in matches {
            let timeRange = m.range(at: 1)
            let raw = nsText.substring(with: timeRange)
            let parts = raw.split(separator: ":").compactMap { Int($0) }
            let t: Double = {
                switch parts.count {
                case 3: return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
                case 2: return Double(parts[0] * 60 + parts[1])
                default: return -1
                }
            }()
            guard t >= 0 else { continue }
            if episodeDuration > 0, t > episodeDuration + 60 { continue }
            hits.append(Hit(
                t: t,
                start: timeRange.location,
                end: timeRange.location + timeRange.length
            ))
        }

        // Keep only ascending timestamps. A non-ascending entry is almost
        // always a stray time mention in running prose; better to drop it
        // than to invert chapter order.
        var ascending: [Hit] = []
        for h in hits {
            if (ascending.last?.t ?? -.infinity) < h.t {
                ascending.append(h)
            }
        }
        guard ascending.count >= 2 else { return [] }

        // Build titles by carving out the text between successive time
        // tokens (or up to end-of-input for the last one).
        var seen = Set<Double>()
        var out: [Chapter] = []
        for i in 0..<ascending.count {
            if seen.contains(ascending[i].t) { continue }
            seen.insert(ascending[i].t)

            let titleStart = ascending[i].end
            let titleEnd: Int = i + 1 < ascending.count
                ? ascending[i + 1].start
                : nsText.length
            guard titleEnd > titleStart else { continue }
            let titleNS = nsText.substring(
                with: NSRange(location: titleStart, length: titleEnd - titleStart)
            )
            guard let title = cleanTitle(titleNS) else { continue }
            out.append(Chapter(t: ascending[i].t, title: title))
        }
        return out
    }

    /// Trim a slice of description text into something that reads like a
    /// chapter title: drop leading/trailing whitespace + separator chars,
    /// drop the leading-paragraph-break that HTML-strip produced, cap
    /// length at first sentence terminator if too long.
    private static func cleanTitle(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop a leading separator the format may have left: `00:00 - title`,
        // `00:00 · title`, `00:00 — title`, `00:00. title`, etc.
        while let head = s.first, "-·.:|—–,，".contains(head) {
            s.removeFirst()
            s = String(s.drop(while: { $0.isWhitespace }))
        }
        // If the snippet runs long (we grabbed a whole paragraph because
        // the next chapter is far away), cut at the first sentence
        // terminator so the title stays scannable. ~80 chars is a generous
        // single-line limit.
        if s.count > 80 {
            let terminators: Set<Character> = ["。", "！", "？", "!", "?"]
            if let stop = s.firstIndex(where: { terminators.contains($0) }) {
                s = String(s[..<stop])
            } else {
                s = String(s.prefix(80))
            }
        }
        // Trim trailing punctuation / whitespace. Done last so the
        // mid-string cut above can decide where to stop.
        while let tail = s.last, "。！？!?., ，\n\t".contains(tail) {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject vacuous titles (single char or just punctuation).
        return s.count >= 2 ? s : nil
    }
}
