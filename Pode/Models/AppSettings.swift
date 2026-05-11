import Foundation

struct AppSettings: Codable, Equatable {
    var openaiKey: String?
    var anthropicKey: String?
    var whisperModel: String = "whisper-1"
    var claudeModel: String = "claude-haiku-4-5-20251001"
    var accentHex: String = "#d06a3a"
    var bloomStrength: Double = 0.85
    var glassBlur: Double = 28
    var showSecondaryBloom: Bool = true
    var userName: String = ""
    /// "local" (WhisperKit on-device) or "openai" (cloud).
    var transcribeEngine: String = "local"
    /// Persisted as `LocalWhisperModel.rawValue`; default Balanced.
    var localWhisperModel: String = "openai_whisper-medium"
    /// Have we completed the first-run model picker for the local engine?
    var localWhisperPicked: Bool = false
    /// Use the configured AI provider to infer speaker labels after transcribing.
    var inferSpeakers: Bool = true
    /// Whisper language hint. Empty = auto-detect (uses WhisperKit's
    /// dedicated language-detection step on the first chunk, then pins the
    /// detected language for the rest). Specific value = pin from the start.
    var transcribeLanguage: String = ""
    /// Convert Whisper's Traditional Chinese output to Simplified.
    /// Whisper's pretrained text bias produces Traditional; we convert with
    /// Apple's built-in `Hant-Hans` transform.
    var simplifiedChinese: Bool = true

    // MARK: - Summary / analysis provider
    /// "anthropic" | "openai" | "gemini" | "custom"
    var summaryProvider: String = "anthropic"
    /// Gemini key (separate from the OpenAI / Anthropic keys above).
    var geminiKey: String?
    /// Custom OpenAI-compatible endpoint key. Used with `customBaseURL`.
    var customKey: String?
    /// Base URL for an OpenAI-compatible service. Examples:
    /// `https://api.deepseek.com/v1`, `https://openrouter.ai/api/v1`,
    /// `https://api.together.xyz/v1`. Trailing slash stripped at call time.
    var customBaseURL: String = ""
    /// Default model name per provider. The active one is picked by `summaryProvider`.
    var openaiSummaryModel: String = "gpt-4o-mini"
    var geminiModel: String = "gemini-3.1-flash"
    var customModel: String = ""

    // MARK: - i18n
    /// App display language AND the language summaries / Q&A should be
    /// written in. Stored as `AppLanguage.rawValue`. `auto` follows the
    /// system locale.
    var appLanguage: String = "auto"

    // MARK: - Playback
    /// Preferred playback speed, applied to AVPlayer's rate when playing.
    /// Clamped on read to the supported preset range (0.5…3.0).
    var playbackRate: Double = 1.0
}

enum SettingsKey: String, CaseIterable {
    case openaiKey
    case anthropicKey
    case whisperModel
    case claudeModel
    case accentHex
    case bloomStrength
    case glassBlur
    case showSecondaryBloom
    case userName
    case transcribeEngine
    case localWhisperModel
    case localWhisperPicked
    case inferSpeakers
    case transcribeLanguage
    case simplifiedChinese
    case summaryProvider
    case geminiKey
    case customKey
    case customBaseURL
    case openaiSummaryModel
    case geminiModel
    case customModel
    case appLanguage
    case playbackRate
}
