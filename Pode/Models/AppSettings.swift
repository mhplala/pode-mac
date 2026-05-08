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
    /// Use Claude to infer speaker labels after transcribing.
    var inferSpeakers: Bool = true
    /// Whisper language hint. Empty = auto-detect (uses WhisperKit's
    /// dedicated language-detection step on the first chunk, then pins the
    /// detected language for the rest). Specific value = pin from the start.
    var transcribeLanguage: String = ""
    /// Convert Whisper's Traditional Chinese output to Simplified.
    /// Whisper's pretrained text bias produces Traditional; we convert with
    /// Apple's built-in `Hant-Hans` transform.
    var simplifiedChinese: Bool = true
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
}
