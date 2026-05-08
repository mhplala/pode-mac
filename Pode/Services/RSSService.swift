import Foundation

struct ParsedShow {
    var title: String
    var host: String
    var publisher: String?
    var artworkUrl: String
    var description: String?
    var category: String?
}

struct ParsedEpisode {
    var guid: String
    var title: String
    var description: String?
    var pubDate: Date
    var duration: Double
    var audioUrl: String
    var audioType: String?
    var audioSize: Int64?
}

struct ParsedFeed {
    var show: ParsedShow
    var episodes: [ParsedEpisode]
}

enum RSSError: Error, LocalizedError {
    case invalidXML
    case noChannel
    case fetchFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidXML: return "Couldn't parse the feed."
        case .noChannel: return "Feed has no channel."
        case .fetchFailed(let code): return "Feed fetch failed (HTTP \(code))."
        }
    }
}

enum RSSService {
    static func fetchAndParse(feedUrl: String) async throws -> ParsedFeed {
        guard let url = URL(string: feedUrl) else { throw RSSError.invalidXML }
        var req = URLRequest(url: url)
        req.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        req.setValue("Pode/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RSSError.fetchFailed(http.statusCode)
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ParsedFeed {
        let parser = XMLParser(data: data)
        let delegate = RSSParserDelegate()
        parser.delegate = delegate
        guard parser.parse(), let channel = delegate.channel else {
            throw RSSError.noChannel
        }
        return ParsedFeed(show: channel.show, episodes: channel.episodes)
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    struct Channel {
        var show: ParsedShow
        var episodes: [ParsedEpisode]
    }

    var channel: Channel?

    private var inChannel = false
    private var inItem = false

    private var showTitle = ""
    private var showAuthor = ""
    private var showOwnerName = ""
    private var showImageHref = ""
    private var showImageURL = ""
    private var showDescription = ""
    private var showCategory = ""

    private var item: ParsedEpisode = .init(
        guid: "", title: "", description: nil, pubDate: .now,
        duration: 0, audioUrl: "", audioType: nil, audioSize: nil
    )

    private var episodes: [ParsedEpisode] = []

    private var elementStack: [String] = []
    private var currentText = ""
    private var currentAttributes: [String: String] = [:]

    func parserDidStartDocument(_ parser: XMLParser) {}

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        elementStack.append(elementName)
        currentText = ""
        currentAttributes = attributeDict

        if elementName == "channel" {
            inChannel = true
        } else if elementName == "item" {
            inItem = true
            item = ParsedEpisode(
                guid: "", title: "", description: nil, pubDate: .now,
                duration: 0, audioUrl: "", audioType: nil, audioSize: nil
            )
        } else if elementName == "enclosure" && inItem {
            item.audioUrl = attributeDict["url"] ?? item.audioUrl
            item.audioType = attributeDict["type"]
            if let len = attributeDict["length"], let bytes = Int64(len) { item.audioSize = bytes }
        } else if elementName == "itunes:image" {
            if inItem == false, inChannel {
                if let href = attributeDict["href"], !href.isEmpty {
                    showImageHref = href
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.dropLast().last ?? ""

        if inItem {
            switch elementName {
            case "title": item.title = text
            case "guid": item.guid = text
            case "description":
                if item.description == nil { item.description = stripHTML(text) }
            case "content:encoded":
                item.description = stripHTML(text)
            case "itunes:summary":
                if item.description == nil { item.description = stripHTML(text) }
            case "pubDate":
                if let d = parseDate(text) { item.pubDate = d }
            case "itunes:duration":
                item.duration = parseDuration(text)
            case "item":
                if !item.audioUrl.isEmpty {
                    if item.guid.isEmpty { item.guid = item.audioUrl }
                    episodes.append(item)
                }
                inItem = false
            default: break
            }
        } else if inChannel {
            switch elementName {
            case "title" where parent == "channel":
                showTitle = text
            case "itunes:author":
                showAuthor = text
            case "itunes:name" where parent == "itunes:owner":
                showOwnerName = text
            case "url" where parent == "image":
                if showImageURL.isEmpty { showImageURL = text }
            case "description" where parent == "channel":
                if showDescription.isEmpty { showDescription = stripHTML(text) }
            case "itunes:summary":
                if showDescription.isEmpty { showDescription = stripHTML(text) }
            case "itunes:category":
                if showCategory.isEmpty {
                    showCategory = currentAttributes["text"] ?? showCategory
                }
            case "channel":
                let artwork = !showImageHref.isEmpty ? showImageHref : showImageURL
                let show = ParsedShow(
                    title: showTitle.isEmpty ? "Untitled" : showTitle,
                    host: showAuthor,
                    publisher: showOwnerName.isEmpty ? nil : showOwnerName,
                    artworkUrl: artwork,
                    description: showDescription.isEmpty ? nil : showDescription,
                    category: showCategory.isEmpty ? nil : showCategory
                )
                channel = Channel(show: show, episodes: episodes)
                inChannel = false
            default: break
            }
        }
        elementStack.removeLast()
        currentText = ""
    }

    private func parseDate(_ s: String) -> Date? {
        for f in DateFormatters.rss {
            if let d = f.date(from: s) { return d }
        }
        return DateFormatters.iso.date(from: s)
    }

    private func parseDuration(_ s: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        if let n = Double(trimmed) { return n }
        let parts = trimmed.split(separator: ":").map { Double($0) ?? 0 }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return 0
    }

    private func stripHTML(_ s: String) -> String {
        var result = s
        // crude tag strip
        let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [])
        if let r = tagRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = r.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return result
    }
}

// Cached date formatters — building these is non-trivially expensive, and a
// large feed parses hundreds of dates back-to-back.
enum DateFormatters {
    static let rss: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()
    static let iso = ISO8601DateFormatter()
}

enum IDFactory {
    static func showId(feedUrl: String) -> String {
        return "show_" + djb2(feedUrl)
    }
    static func episodeId(showId: String, guid: String) -> String {
        return "\(showId)_ep_" + djb2(guid)
    }
    private static func djb2(_ s: String) -> String {
        var h: UInt64 = 5381
        for c in s.unicodeScalars {
            h = (h &* 33) &+ UInt64(c.value)
        }
        return String(h, radix: 36)
    }
}
