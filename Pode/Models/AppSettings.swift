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
}
