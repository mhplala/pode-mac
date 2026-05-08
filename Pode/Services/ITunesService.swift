import Foundation

struct ITunesPodcast: Identifiable, Hashable, Codable {
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let feedUrl: String?
    let artworkUrl600: String?
    let artworkUrl100: String?
    let primaryGenreName: String?
    let trackCount: Int?

    var id: Int { collectionId }
}

struct ITunesGenre: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct ITunesRegion: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

private let sharedJSONDecoder = JSONDecoder()

enum ITunesService {
    static let regions: [ITunesRegion] = [
        .init(code: "cn", name: "中国"),
        .init(code: "tw", name: "台湾"),
        .init(code: "hk", name: "香港"),
        .init(code: "us", name: "United States"),
        .init(code: "jp", name: "日本"),
        .init(code: "gb", name: "United Kingdom"),
    ]

    // Chinese-friendly genre presets — these IDs work across regions.
    static let genresCN: [ITunesGenre] = [
        .init(id: 1324, name: "社会与文化"),
        .init(id: 1304, name: "教育"),
        .init(id: 1303, name: "喜剧"),
        .init(id: 1318, name: "科技"),
        .init(id: 1321, name: "商业"),
        .init(id: 1487, name: "新闻"),
        .init(id: 1310, name: "音乐"),
        .init(id: 1301, name: "艺术"),
        .init(id: 1477, name: "科学"),
        .init(id: 1488, name: "犯罪实录"),
        .init(id: 1512, name: "健康"),
        .init(id: 1545, name: "体育"),
    ]

    static let genresEN: [ITunesGenre] = [
        .init(id: 1303, name: "Comedy"),
        .init(id: 1310, name: "Music"),
        .init(id: 1318, name: "Technology"),
        .init(id: 1321, name: "Business"),
        .init(id: 1324, name: "Society & Culture"),
        .init(id: 1477, name: "Science"),
        .init(id: 1487, name: "News"),
        .init(id: 1488, name: "True Crime"),
        .init(id: 1304, name: "Education"),
        .init(id: 1545, name: "Sports"),
        .init(id: 1314, name: "Religion"),
    ]

    static func genres(for region: String) -> [ITunesGenre] {
        switch region {
        case "cn", "tw", "hk", "jp": return genresCN
        default: return genresEN
        }
    }

    // Kept for back-compat
    static var genres: [ITunesGenre] { genresCN }

    private struct SearchResult: Decodable {
        let results: [ITunesPodcast]
    }

    private struct TopFeed: Decodable {
        struct Feed: Decodable {
            struct Entry: Decodable {
                struct ImID: Decodable {
                    let attributes: [String: String]?
                }
                let id: ImID
                enum CodingKeys: String, CodingKey { case id = "id" }
            }
            let entry: [Entry]?
        }
        let feed: Feed
    }

    static func search(term: String, limit: Int = 30) async throws -> [ITunesPodcast] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let url = URL(string: "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=\(limit)&term=\(escaped)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try sharedJSONDecoder.decode(SearchResult.self, from: data)
        return decoded.results.filter { $0.feedUrl != nil }
    }

    static func top(country: String = "cn", genreId: Int? = nil, limit: Int = 30) async throws -> [ITunesPodcast] {
        let genrePart = genreId.map { "/genre=\($0)" } ?? ""
        let topURL = URL(string: "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=\(limit)\(genrePart)/json")!
        let (data, _) = try await URLSession.shared.data(from: topURL)
        let top = try sharedJSONDecoder.decode(TopFeed.self, from: data)
        let ids = (top.feed.entry ?? []).compactMap { $0.id.attributes?["im:id"] }
        guard !ids.isEmpty else { return [] }
        let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(ids.joined(separator: ","))&entity=podcast")!
        let (lookupData, _) = try await URLSession.shared.data(from: lookupURL)
        let result = try sharedJSONDecoder.decode(SearchResult.self, from: lookupData)
        return result.results.filter { $0.feedUrl != nil }
    }
}
