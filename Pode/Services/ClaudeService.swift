import Foundation

// MARK: - Public types

struct AIAnalysis {
    let summary: String
    let takeaways: [String]
    let concepts: [(name: String, cluster: String)]
}

struct AIAnswer {
    let answer: String
    let citations: [(line: Int, t: Double)]
}

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic, openai, gemini, custom

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai:    return "OpenAI"
        case .gemini:    return "Google Gemini"
        case .custom:    return "Custom (OpenAI-compatible)"
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-haiku-4-5-20251001"
        case .openai:    return "gpt-4o-mini"
        case .gemini:    return "gemini-3.1-flash"
        case .custom:    return ""
        }
    }
}

struct AIClientConfig {
    var provider: AIProvider
    var apiKey: String
    var model: String
    /// Only used for `.custom`. Trailing slashes are stripped at call time.
    var baseURL: String
    /// Output language directive (e.g. "Simplified Chinese (中文/简体)").
    /// Empty → no directive; the model picks based on input language.
    var language: String

    init(provider: AIProvider, apiKey: String, model: String,
         baseURL: String = "", language: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.language = language
    }

    /// Build a config from `AppSettings` based on the active `summaryProvider`.
    init(settings: AppSettings) {
        let provider = AIProvider(rawValue: settings.summaryProvider) ?? .anthropic
        self.provider = provider
        switch provider {
        case .anthropic:
            self.apiKey = settings.anthropicKey ?? ""
            self.model = settings.claudeModel.isEmpty ? provider.defaultModel : settings.claudeModel
            self.baseURL = ""
        case .openai:
            self.apiKey = settings.openaiKey ?? ""
            self.model = settings.openaiSummaryModel.isEmpty ? provider.defaultModel : settings.openaiSummaryModel
            self.baseURL = ""
        case .gemini:
            self.apiKey = settings.geminiKey ?? ""
            self.model = settings.geminiModel.isEmpty ? provider.defaultModel : settings.geminiModel
            self.baseURL = ""
        case .custom:
            self.apiKey = settings.customKey ?? ""
            self.model = settings.customModel
            self.baseURL = settings.customBaseURL
        }
        // Output-language directive — driven by the global app-language
        // setting (`auto` resolves to the live system locale's directive).
        let lang = AppLanguage(rawValue: settings.appLanguage) ?? .auto
        if lang == .auto {
            // Auto → resolve to the system locale for non-English systems.
            // English systems leave the directive empty so the model follows
            // the transcript's natural language.
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            switch code {
            case "zh": self.language = AppLanguage.zh_Hans.aiDirective
            case "ja": self.language = AppLanguage.ja.aiDirective
            case "es": self.language = AppLanguage.es.aiDirective
            case "fr": self.language = AppLanguage.fr.aiDirective
            case "de": self.language = AppLanguage.de.aiDirective
            default:   self.language = ""
            }
        } else {
            self.language = lang.aiDirective
        }
    }
}

enum AIError: Error, LocalizedError {
    case missingKey(AIProvider)
    case missingModel(AIProvider)
    case missingBaseURL
    case http(provider: AIProvider, code: Int, body: String)
    case noJSON(AIProvider)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p):
            return "Add your \(p.displayName) API key in Settings."
        case .missingModel(let p):
            return "Pick a model for \(p.displayName) in Settings."
        case .missingBaseURL:
            return "Set the custom provider's base URL in Settings."
        case .http(let p, let code, let body):
            return "\(p.displayName) failed (\(code)): \(body.prefix(200))"
        case .noJSON(let p):
            return "\(p.displayName) returned no JSON."
        }
    }
}

// MARK: - Backwards-compatible aliases

typealias ClaudeAnalysis = AIAnalysis
typealias ClaudeAnswer = AIAnswer
typealias ClaudeError = AIError

// MARK: - AIService

enum AIService {
    static let validClusters: Set<String> = ["Editorial", "Mind", "Body", "Craft", "Other"]

    // MARK: Public

    static func analyze(transcript: [String], episodeTitle: String, showTitle: String,
                        config: AIClientConfig) async throws -> AIAnalysis {
        let joined = transcript.joined(separator: " ")
        let trimmed = String(joined.prefix(24000))
        let baseSystem = """
You are an editorial AI helping a thoughtful listener build a "personal canon" of ideas from podcast transcripts. Output strict JSON only — no prose, no markdown.

Keys:
- summary (string, 4-7 sentences in the voice of a careful editor): open with one sentence framing what the episode is about and who the guest is. Then trace the actual argument or arc — what's the main thesis, what evidence or stories carry it, what twist or turn does the conversation take. End with what someone walks away thinking. Be specific about content, not generic about "interesting topics".
- takeaways (array of strings): one entry per distinct insight in the conversation. DO NOT cap at 3 or 5 — capture every separable idea worth remembering, in the order they appear. A short episode might have 4 takeaways; a long technical one might have 12-20. Each takeaway is a crisp single sentence (under 30 words) that conveys the actual claim, not a vague reference.
- concepts (array of 4-10 objects with {name: short noun phrase ≤4 words, cluster: one of "Editorial","Mind","Body","Craft","Other"}).

Cluster meanings: Editorial = writing, the slow web, ideas about reading; Mind = perception, prediction, cognition; Body = sleep, attention, biology; Craft = sound, making, technique.
"""
        // Language directive — `summary` and `takeaways` follow this; concept
        // `cluster` values STAY in English (they're internal taxonomy).
        let system = languageDirected(baseSystem, language: config.language,
                                      affecting: "the `summary` and `takeaways` strings",
                                      stayEnglish: "concept `cluster` values")
        let user = """
Show: \(showTitle)
Episode: \(episodeTitle)

Transcript excerpt:
\(trimmed)

Return JSON.
"""
        // Higher token budget since the new prompt asks for a longer
        // summary + unbounded takeaway count. ~3500 ≈ 2500 words, plenty
        // for the JSON wrapping a richly-itemized analysis even on dense
        // technical conversations.
        let raw = try await call(config: config, system: system, user: user, maxTokens: 3500, jsonMode: true)
        guard let json = extractJSON(from: raw) else { throw AIError.noJSON(config.provider) }
        let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // No `prefix(...)` cap — takeaways length is now driven by the
        // conversation. Trim individual entries and drop any empties.
        let takeaways = ((json["takeaways"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let conceptsRaw = (json["concepts"] as? [[String: Any]]) ?? []
        let concepts: [(name: String, cluster: String)] = conceptsRaw.prefix(10).compactMap {
            guard let name = ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            let cluster = $0["cluster"] as? String ?? "Other"
            return (name, validClusters.contains(cluster) ? cluster : "Other")
        }
        return AIAnalysis(summary: summary, takeaways: Array(takeaways), concepts: concepts)
    }

    static func ask(question: String, episodeTitle: String,
                    lines: [(index: Int, t: Double, text: String)],
                    config: AIClientConfig) async throws -> AIAnswer {
        let numbered = lines.map { "[\($0.index)@\(Int($0.t))s] \($0.text)" }.joined(separator: "\n")
        let user = """
Episode: \(episodeTitle)

Lines:
\(String(numbered.prefix(30000)))

Question: \(question)

Return JSON.
"""
        let baseSystem = "Answer questions about a podcast transcript using only the supplied lines. Each line has a [index@seconds] tag. Cite the most relevant 1-3 lines as JSON. Output strict JSON: { \"answer\": string (2-4 sentences), \"citations\": [{ \"line\": index, \"t\": seconds }] }."
        let system = languageDirected(baseSystem, language: config.language,
                                      affecting: "the `answer` string", stayEnglish: nil)
        let raw = try await call(config: config, system: system, user: user, maxTokens: 700, jsonMode: true)
        guard let json = extractJSON(from: raw) else { throw AIError.noJSON(config.provider) }
        let answer = (json["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let citationsRaw = (json["citations"] as? [[String: Any]]) ?? []
        let citations: [(line: Int, t: Double)] = citationsRaw.prefix(4).compactMap {
            guard let line = $0["line"] as? Int else { return nil }
            let t: Double = ($0["t"] as? Double) ?? Double(($0["t"] as? Int) ?? 0)
            return (line, t)
        }
        return AIAnswer(answer: answer, citations: citations)
    }

    /// Generate 3-5 content-aware question prompts the user can click as
    /// shortcuts in the Ask pane. Prefers the precomputed summary +
    /// takeaways when available (cheap + already structured); falls back
    /// to a transcript excerpt otherwise.
    static func suggestQuestions(transcript: [String],
                                 summary: String?,
                                 takeaways: [String],
                                 episodeTitle: String,
                                 showTitle: String,
                                 config: AIClientConfig) async throws -> [String] {
        // Build a compact grounding block. When we already have a summary
        // and takeaways from `analyze`, lean on those — they're the model's
        // own distillation of the episode and produce far sharper question
        // suggestions than raw transcript chunks. Without them, fall back
        // to the first ~6000 characters of transcript.
        let grounding: String = {
            var parts: [String] = []
            if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                parts.append("Summary:\n\(s)")
            }
            if !takeaways.isEmpty {
                let listed = takeaways.enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
                parts.append("Takeaways:\n\(listed)")
            }
            if parts.isEmpty {
                let joined = transcript.joined(separator: " ")
                parts.append("Transcript excerpt:\n\(String(joined.prefix(6000)))")
            }
            return parts.joined(separator: "\n\n")
        }()

        let baseSystem = """
You generate short, content-aware question prompts that a curious listener might click as a shortcut after listening to a specific podcast episode. Output strict JSON only — no prose, no markdown.

Key:
- questions (array of 3-5 strings): each question must be specific to THIS episode's actual content — name the person, idea, framework, claim, or moment in the question. Avoid generic questions like "What's the main argument?" or "Summarize this". Each question is under 14 words, ends with a question mark, and reads naturally — like something the listener would actually type.

Examples of good (specific) vs bad (generic):
GOOD: "Why does Su Yu think LLMs need a 'language agent'?"
GOOD: "What's the difference between fast and slow reading they describe?"
BAD: "What is the main point?"
BAD: "Summarize the episode."
"""
        let system = languageDirected(baseSystem, language: config.language,
                                      affecting: "the `questions` strings", stayEnglish: nil)
        let user = """
Show: \(showTitle)
Episode: \(episodeTitle)

\(grounding)

Return JSON with a `questions` array.
"""
        let raw = try await call(config: config, system: system, user: user, maxTokens: 400, jsonMode: true)
        guard let json = extractJSON(from: raw) else { throw AIError.noJSON(config.provider) }
        let qs = ((json["questions"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(qs.prefix(5))
    }

    /// Generate a 2-4 sentence definition for a concept that surfaced
    /// across the user's transcribed episodes. `mentions` is a small list
    /// of `(episodeTitle, summaryOrSnippet)` pairs that ground the
    /// definition in HOW the concept appears here, not in a generic
    /// encyclopedia entry. Used by the Knowledge view's drawer.
    static func defineConcept(name: String,
                              cluster: String,
                              mentions: [(episodeTitle: String, snippet: String)],
                              config: AIClientConfig) async throws -> String {
        let body = mentions.prefix(6).enumerated().map { idx, m in
            "\(idx + 1). \"\(m.episodeTitle)\": \(String(m.snippet.prefix(800)))"
        }.joined(separator: "\n")
        let baseSystem = """
You write tight, intellectually honest definitions of recurring concepts a listener has heard across podcasts. Output strict JSON only — no prose, no markdown.

Key:
- definition (string, 2-4 sentences): start by defining what the concept actually means in plain language — not just "the idea of X" or "a concept relating to Y". Then ground it in HOW it appears in the episodes below — what specific angle, claim, or debate the concept carries here. End with what makes this concept worth holding onto, or what it's NOT. Avoid encyclopedia-speak and avoid restating the concept name in the first three words.
"""
        let system = languageDirected(baseSystem, language: config.language,
                                      affecting: "the `definition` string", stayEnglish: nil)
        let user = """
Concept: \(name)
Cluster: \(cluster)

Encountered across these episodes:
\(body)

Return JSON.
"""
        let raw = try await call(config: config, system: system, user: user, maxTokens: 600, jsonMode: true)
        guard let json = extractJSON(from: raw) else { throw AIError.noJSON(config.provider) }
        let def = (json["definition"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return def
    }

    /// Round-trip the configured provider with a tiny "say ok" prompt to
    /// verify auth + model + base URL all work. Returns the raw response so
    /// the UI can show it; throws an `AIError` with a human message on
    /// failure (missing key, missing base URL, HTTP error, etc).
    static func ping(config: AIClientConfig) async throws -> String {
        let raw = try await call(
            config: config,
            system: "Reply with the single word \"ok\" — nothing else.",
            user: "ping",
            maxTokens: 16,
            jsonMode: false
        )
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func inferSpeakers(
        lines: [(index: Int, text: String)],
        showTitle: String,
        showHost: String,
        episodeTitle: String,
        config: AIClientConfig
    ) async throws -> [Int: String] {
        let numbered = lines.map { "[\($0.index)] \($0.text)" }.joined(separator: "\n")
        let trimmed = String(numbered.prefix(60000))

        let system = """
        You are tagging each line of a podcast transcript with the speaker.
        Use natural names when context makes them clear (host introductions,
        "罗老师", "请问 X", proper-noun cues). When unsure, fall back to
        "Speaker A", "Speaker B"… consistently — same person, same label.
        Output STRICT JSON only:
        { "assignments": [ { "line": <int>, "speaker": <string> } ] }
        Only include lines whose speaker is reasonably confident — skip the
        rest. Don't invent speakers; only use names that appear in the text
        or generic Speaker A/B/C labels.
        """

        let user = """
        Show: \(showTitle)
        Host: \(showHost.isEmpty ? "(unknown)" : showHost)
        Episode: \(episodeTitle)

        Lines (numbered):
        \(trimmed)
        """

        let raw = try await call(config: config, system: system, user: user, maxTokens: 8000, jsonMode: true)
        guard let json = extractJSON(from: raw) else { throw AIError.noJSON(config.provider) }
        var out: [Int: String] = [:]
        let assignments = (json["assignments"] as? [[String: Any]]) ?? []
        for a in assignments {
            guard let line = a["line"] as? Int,
                  let speaker = (a["speaker"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !speaker.isEmpty else { continue }
            out[line] = speaker
        }
        return out
    }

    // MARK: - Provider dispatch

    private static func call(config: AIClientConfig, system: String, user: String,
                             maxTokens: Int, jsonMode: Bool) async throws -> String {
        let key = config.apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw AIError.missingKey(config.provider) }
        let model = config.model.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { throw AIError.missingModel(config.provider) }

        switch config.provider {
        case .anthropic:
            return try await callAnthropic(apiKey: key, model: model,
                                           maxTokens: maxTokens, system: system, user: user)
        case .openai:
            return try await callOpenAIChat(baseURL: "https://api.openai.com/v1",
                                            apiKey: key, model: model, maxTokens: maxTokens,
                                            system: system, user: user, jsonMode: jsonMode,
                                            providerLabel: .openai)
        case .gemini:
            return try await callGemini(apiKey: key, model: model, maxTokens: maxTokens,
                                        system: system, user: user, jsonMode: jsonMode)
        case .custom:
            let trimmed = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !trimmed.isEmpty else { throw AIError.missingBaseURL }
            return try await callOpenAIChat(baseURL: trimmed,
                                            apiKey: key, model: model, maxTokens: maxTokens,
                                            system: system, user: user, jsonMode: false,
                                            providerLabel: .custom)
        }
    }

    // MARK: - Anthropic

    private struct AnthropicMessage: Encodable { let role: String; let content: String }
    private struct AnthropicRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [AnthropicMessage]
    }
    private struct AnthropicResponse: Decodable {
        struct Block: Decodable { let text: String? }
        let content: [Block]
    }

    private static func callAnthropic(apiKey: String, model: String, maxTokens: Int,
                                      system: String, user: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let payload = AnthropicRequest(
            model: model, max_tokens: maxTokens, system: system,
            messages: [AnthropicMessage(role: "user", content: user)]
        )
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(provider: .anthropic, code: http.statusCode,
                               body: String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.compactMap { $0.text }.joined()
    }

    // MARK: - OpenAI Chat Completions (and OpenAI-compatible custom endpoints)

    private struct ChatMessage: Encodable { let role: String; let content: String }
    private struct ResponseFormat: Encodable { let type: String }
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let max_tokens: Int
        let temperature: Double
        let response_format: ResponseFormat?
    }
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg
        }
        let choices: [Choice]
    }

    private static func callOpenAIChat(baseURL: String, apiKey: String, model: String,
                                       maxTokens: Int, system: String, user: String,
                                       jsonMode: Bool, providerLabel: AIProvider) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            max_tokens: maxTokens,
            temperature: 0.4,
            // `response_format` is well-supported by OpenAI; many compatibles
            // (DeepSeek, Together, OpenRouter) accept it but a few reject it,
            // so it's only enabled when the provider is OpenAI proper.
            response_format: jsonMode ? ResponseFormat(type: "json_object") : nil
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(provider: providerLabel, code: http.statusCode,
                               body: String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    // MARK: - Gemini

    private struct GeminiPart: Encodable { let text: String }
    private struct GeminiContent: Encodable { let role: String?; let parts: [GeminiPart] }
    private struct GeminiSystem: Encodable { let parts: [GeminiPart] }
    private struct GeminiGenConfig: Encodable {
        let maxOutputTokens: Int
        let temperature: Double
        let responseMimeType: String?
    }
    private struct GeminiRequest: Encodable {
        let systemInstruction: GeminiSystem?
        let contents: [GeminiContent]
        let generationConfig: GeminiGenConfig
    }
    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    private static func callGemini(apiKey: String, model: String, maxTokens: Int,
                                   system: String, user: String, jsonMode: Bool) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = GeminiRequest(
            systemInstruction: GeminiSystem(parts: [GeminiPart(text: system)]),
            contents: [GeminiContent(role: "user", parts: [GeminiPart(text: user)])],
            generationConfig: GeminiGenConfig(
                maxOutputTokens: maxTokens,
                temperature: 0.4,
                responseMimeType: jsonMode ? "application/json" : nil
            )
        )
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(provider: .gemini, code: http.statusCode,
                               body: String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = (decoded.candidates ?? [])
            .compactMap { $0.content?.parts ?? [] }
            .flatMap { $0 }
            .compactMap { $0.text }
            .joined()
        return text
    }

    // MARK: - Language directive

    /// Append a "Respond in <language>" instruction to a system prompt.
    /// `stayEnglish` is for keys/taxonomy that should NOT translate (e.g. the
    /// concept-cluster names are internal identifiers, not user-facing).
    private static func languageDirected(_ base: String, language: String,
                                         affecting: String,
                                         stayEnglish: String?) -> String {
        let lang = language.trimmingCharacters(in: .whitespaces)
        guard !lang.isEmpty else { return base }
        var directive = "\n\nIMPORTANT: Write \(affecting) in \(lang). The user has selected this language in app settings."
        if let stay = stayEnglish {
            directive += " Keep \(stay) in English."
        }
        return base + directive
    }

    // MARK: - JSON extraction (lenient)

    private static func extractJSON(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
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

// MARK: - Shim: keep the old `ClaudeService.foo(... apiKey: ..., model: ...)`
// signatures working while we migrate call sites. New code should use
// `AIService.analyze(..., config:)` etc.

enum ClaudeService {
    static func analyze(transcript: [String], episodeTitle: String, showTitle: String,
                        apiKey: String, model: String = "claude-haiku-4-5-20251001") async throws -> AIAnalysis {
        let cfg = AIClientConfig(provider: .anthropic, apiKey: apiKey, model: model, baseURL: "")
        return try await AIService.analyze(transcript: transcript, episodeTitle: episodeTitle,
                                           showTitle: showTitle, config: cfg)
    }

    static func ask(question: String, episodeTitle: String,
                    lines: [(index: Int, t: Double, text: String)],
                    apiKey: String, model: String = "claude-haiku-4-5-20251001") async throws -> AIAnswer {
        let cfg = AIClientConfig(provider: .anthropic, apiKey: apiKey, model: model, baseURL: "")
        return try await AIService.ask(question: question, episodeTitle: episodeTitle,
                                       lines: lines, config: cfg)
    }

    static func inferSpeakers(
        lines: [(index: Int, text: String)],
        showTitle: String, showHost: String, episodeTitle: String,
        apiKey: String, model: String = "claude-haiku-4-5-20251001"
    ) async throws -> [Int: String] {
        let cfg = AIClientConfig(provider: .anthropic, apiKey: apiKey, model: model, baseURL: "")
        return try await AIService.inferSpeakers(lines: lines, showTitle: showTitle,
                                                 showHost: showHost, episodeTitle: episodeTitle,
                                                 config: cfg)
    }
}
