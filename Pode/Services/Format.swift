import Foundation
import SwiftUI

enum Fmt {
    static func time(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    static func dur(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "—" }
        let total = Int(s)
        let h = total / 3600
        let m = Int((Double(total % 3600) / 60.0).rounded())
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let cal = Calendar.current
        if cal.isDate(d, equalTo: .now, toGranularity: .year) {
            f.dateFormat = "MMM d"
        } else {
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: d)
    }

    static func bytes(_ count: Int64?) -> String {
        guard let c = count, c > 0 else { return "—" }
        let mb = Double(c) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    /// Convert Traditional Chinese characters to Simplified using Apple's
    /// built-in `Hant-Hans` transform. Non-Chinese characters pass through
    /// unchanged, so it's safe to call on any text.
    static func toSimplifiedChinese(_ s: String) -> String {
        let mut = NSMutableString(string: s)
        CFStringTransform(mut, nil, "Hant-Hans" as CFString, false)
        return mut as String
    }

    /// Insert paragraph breaks into a wall-of-text description. If the source
    /// already has reasonable paragraph structure (≥3 blank-line breaks) we
    /// leave it alone; otherwise we split on sentence terminators (Chinese
    /// 。！？ or English . ! ?) and group every ~3 sentences (or ~180 chars)
    /// into a paragraph.
    static func segmented(_ s: String) -> String {
        let existingBreaks = s.components(separatedBy: "\n\n").count - 1
        if existingBreaks >= 3 { return s }

        let terminators: Set<Character> = ["。", "！", "？", "!", "?"]
        var sentences: [String] = []
        var current = ""
        for ch in s {
            current.append(ch)
            if terminators.contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            } else if ch == "." {
                // English period — only treat as terminator if followed by
                // whitespace or end-of-string. We approximate by checking the
                // last non-space character context at flush time.
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                // Heuristic: terminate if the period isn't part of "x.y" digits.
                let countDigitsAround = trimmed.suffix(3).filter { $0.isNumber }.count
                if countDigitsAround < 2 {
                    sentences.append(trimmed)
                    current = ""
                }
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        if sentences.count < 4 { return s }

        var paragraphs: [String] = []
        var buf: [String] = []
        var bufLen = 0
        for sentence in sentences {
            buf.append(sentence)
            bufLen += sentence.count
            if buf.count >= 3 || bufLen >= 180 {
                paragraphs.append(buf.joined(separator: " "))
                buf.removeAll()
                bufLen = 0
            }
        }
        if !buf.isEmpty {
            paragraphs.append(buf.joined(separator: " "))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    static let coverPalette: [(String, String)] = [
        ("#1f2530", "#3a4759"),
        ("#3a2a1d", "#6b4626"),
        ("#2a1f3a", "#4d3a6b"),
        ("#0f1a1f", "#1f3a4a"),
        ("#3a1d1d", "#7a3a2e"),
        ("#141413", "#2e2e2c"),
        ("#2a2519", "#5a4a2e"),
        ("#1d2d3a", "#3a5a78"),
        ("#2e1d3a", "#5a3a78"),
        ("#1d3a2e", "#2e7a5a"),
        ("#3a2e1d", "#7a5a2e"),
    ]

    static func colorsFor(_ key: String) -> (Color, Color) {
        var h: UInt64 = 0
        for c in key.unicodeScalars { h = (h &* 31) &+ UInt64(c.value) }
        let pair = coverPalette[Int(h % UInt64(coverPalette.count))]
        return (Color(hex: pair.0), Color(hex: pair.1))
    }

    static func glyph(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "·" : String(trimmed.first!).uppercased()
    }
}

extension Color {
    init(hex: String) {
        var s = hex.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            let chars = Array(s)
            s = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
        }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
