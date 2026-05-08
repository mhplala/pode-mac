import Foundation

struct ClaudeAnalysis {
    let summary: String
    let takeaways: [String]
    let concepts: [(name: String, cluster: String)]
}

struct ClaudeAnswer {
    let answer: String
    let citations: [(line: Int, t: Double)]
}

enum ClaudeError: Error, LocalizedError {
    case missingKey
    case http(Int, String)
    case noJSON

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your Anthropic API key in Settings."
        case .http(let code, let body): return "Claude failed (\(code)): \(body.prefix(200))"
        case .noJSON: return "Claude returned no JSON."
        }
    }
}

enum ClaudeService {
    static let validClusters: Set<String> = ["Editorial", "Mind", "Body", "Craft", "Other"]

    private struct MessageRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }
    private struct Message: Encodable {
        let role: String
        let content: String
    }
    private struct MessageResponse: Decodable {
        struct Block: Decodable { let text: String? }
        let content: [Block]
    }

    static func analyze(transcript: [String], episodeTitle: String, showTitle: String,
                        apiKey: String, model: String = "claude-haiku-4-5-20251001") async throws -> ClaudeAnalysis {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw ClaudeError.missingKey }

        let joined = transcript.joined(separator: " ")
        let trimmed = String(joined.prefix(24000))

        let system = """
You are an editorial AI helping a thoughtful listener build a "personal canon" of ideas from podcast transcripts. Output strict JSON only — no prose, no markdown. Keys: summary (string, 2-3 sentences, in the voice of a careful editor), takeaways (array of 3-5 short crisp insights), concepts (array of 4-8 objects with {name: short noun phrase, cluster: one of "Editorial","Mind","Body","Craft","Other"}). Cluster meanings: Editorial = writing, the slow web, ideas about reading; Mind = perception, prediction, cognition; Body = sleep, attention, biology; Craft = sound, making, technique. Keep concept names ≤4 words.
"""
        let user = """
Show: \(showTitle)
Episode: \(episodeTitle)

Transcript excerpt:
\(trimmed)

Return JSON.
"""
        let raw = try await callClaude(apiKey: key, model: model, maxTokens: 1200, system: system, user: user)
        guard let json = extractJSON(from: raw) else { throw ClaudeError.noJSON }
        let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let takeaways = (json["takeaways"] as? [String])?.prefix(6).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let conceptsRaw = (json["concepts"] as? [[String: Any]]) ?? []
        let concepts: [(name: String, cluster: String)] = conceptsRaw.prefix(10).compactMap {
            guard let name = ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            let cluster = $0["cluster"] as? String ?? "Other"
            return (name, validClusters.contains(cluster) ? cluster : "Other")
        }
        return ClaudeAnalysis(summary: summary, takeaways: Array(takeaways), concepts: concepts)
    }

    static func ask(question: String, episodeTitle: String, lines: [(index: Int, t: Double, text: String)],
                    apiKey: String, model: String = "claude-haiku-4-5-20251001") async throws -> ClaudeAnswer {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw ClaudeError.missingKey }
        let numbered = lines.map { "[\($0.index)@\(Int($0.t))s] \($0.text)" }.joined(separator: "\n")
        let user = """
Episode: \(episodeTitle)

Lines:
\(String(numbered.prefix(30000)))

Question: \(question)

Return JSON.
"""
        let system = "Answer questions about a podcast transcript using only the supplied lines. Each line has a [index@seconds] tag. Cite the most relevant 1-3 lines as JSON. Output strict JSON: { \"answer\": string (2-4 sentences), \"citations\": [{ \"line\": index, \"t\": seconds }] }."
        let raw = try await callClaude(apiKey: key, model: model, maxTokens: 700, system: system, user: user)
        guard let json = extractJSON(from: raw) else { throw ClaudeError.noJSON }
        let answer = (json["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let citationsRaw = (json["citations"] as? [[String: Any]]) ?? []
        let citations: [(line: Int, t: Double)] = citationsRaw.prefix(4).compactMap {
            guard let line = $0["line"] as? Int else { return nil }
            let t: Double = ($0["t"] as? Double) ?? Double(($0["t"] as? Int) ?? 0)
            return (line, t)
        }
        return ClaudeAnswer(answer: answer, citations: citations)
    }

    private static func callClaude(apiKey: String, model: String, maxTokens: Int,
                                   system: String, user: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let payload = MessageRequest(
            model: model, max_tokens: maxTokens, system: system,
            messages: [Message(role: "user", content: user)]
        )
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(http.statusCode, bodyText)
        }
        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        return decoded.content.compactMap { $0.text }.joined()
    }

    private static func extractJSON(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        // Strip ```json fences
        if let start = trimmed.range(of: "```"),
           let end = trimmed.range(of: "```", options: .backwards),
           start.upperBound < end.lowerBound {
            var inner = String(trimmed[start.upperBound..<end.lowerBound])
            if inner.hasPrefix("json") { inner.removeFirst(4) }
            inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = inner.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        // First { ... last }
        if let open = trimmed.firstIndex(of: "{"),
           let close = trimmed.lastIndex(of: "}"),
           open < close {
            let slice = String(trimmed[open...close])
            if let data = slice.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return nil
    }
}
