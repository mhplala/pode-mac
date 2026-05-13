import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Episode sharing + transcript export helpers. Pure functions over
/// `Episode` plus a couple of AppKit-level entry points (pasteboard,
/// save panel). Sits at the boundary so EpisodeView stays thin.
enum ShareExport {

    /// Marketing site URL appended to every outgoing share payload as
    /// a discreet attribution. Doubles as a friction-free path for
    /// recipients to discover Pode.
    private static let websiteURL = "https://podecast.cc"

    // MARK: - Episode share

    /// Best "link" we have for an episode — typically the original
    /// audio URL, which is publicly reachable for any RSS-distributed
    /// podcast. Falls back to the show's feed URL if audio is missing.
    static func shareURL(for ep: Episode) -> URL? {
        if let url = URL(string: ep.audioUrl), !ep.audioUrl.isEmpty {
            return url
        }
        if let show = ep.show, let url = URL(string: show.feedUrl) {
            return url
        }
        return nil
    }

    /// One-line text suitable for messages / email subject:
    /// "Episode Title — Show Name"
    static func shareSubject(for ep: Episode) -> String {
        if let show = ep.show, !show.title.isEmpty {
            return "\(ep.title) — \(show.title)"
        }
        return ep.title
    }

    /// Multi-line plain text payload for share sheets that want a
    /// body (e.g. Mail, Notes, Messages). Includes the link inline so
    /// receivers can click through without further context, plus a
    /// discreet "via pode" attribution that links recipients back to
    /// the marketing site.
    static func shareBody(for ep: Episode) -> String {
        var parts: [String] = []
        if let show = ep.show, !show.title.isEmpty {
            parts.append("\(ep.title) — \(show.title)")
        } else {
            parts.append(ep.title)
        }
        parts.append(Fmt.date(ep.pubDate))
        if let url = shareURL(for: ep) {
            parts.append(url.absoluteString)
        }
        parts.append("")
        parts.append("via pode · \(websiteURL)")
        return parts.joined(separator: "\n")
    }

    /// Compact Markdown block ready to paste into a note. Resolves to:
    ///
    ///     [Episode Title](https://…) — Show · 2026-05-13 · _via [pode](https://podecast.cc)_
    static func shareMarkdown(for ep: Episode) -> String {
        let dateStr = Fmt.date(ep.pubDate)
        let show = ep.show?.title ?? ""
        let attribution = " · _via [pode](\(websiteURL))_"
        if let url = shareURL(for: ep) {
            return "[\(ep.title)](\(url.absoluteString))\(show.isEmpty ? "" : " — \(show)") · \(dateStr)\(attribution)"
        }
        // No URL — still useful as a citation.
        return "**\(ep.title)**\(show.isEmpty ? "" : " — \(show)") · \(dateStr)\(attribution)"
    }

    /// Copy the raw share URL to the system pasteboard.
    static func copyLinkToPasteboard(for ep: Episode) {
        guard let url = shareURL(for: ep) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    /// Copy the Markdown citation block to the pasteboard.
    static func copyMarkdownToPasteboard(for ep: Episode) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(shareMarkdown(for: ep), forType: .string)
    }

    // MARK: - Transcript export

    enum TranscriptFormat {
        case plainText
        case markdown
        case srt

        var fileExtension: String {
            switch self {
            case .plainText: return "txt"
            case .markdown:  return "md"
            case .srt:       return "srt"
            }
        }
        var contentType: UTType {
            switch self {
            case .plainText: return .plainText
            case .markdown:  return UTType(filenameExtension: "md") ?? .plainText
            case .srt:       return UTType(filenameExtension: "srt") ?? .plainText
            }
        }
    }

    /// Build the transcript export string. Operates on a pre-sorted
    /// snapshot so this is pure and safe to call from any actor.
    static func transcriptExport(ep: Episode, format: TranscriptFormat,
                                 sortedLines: [TranscriptLineModel]) -> String {
        switch format {
        case .plainText:  return plainTextExport(ep: ep, lines: sortedLines)
        case .markdown:   return markdownExport(ep: ep, lines: sortedLines)
        case .srt:        return srtExport(lines: sortedLines)
        }
    }

    private static func plainTextExport(ep: Episode, lines: [TranscriptLineModel]) -> String {
        var out = ""
        out += "\(ep.title)\n"
        if let show = ep.show {
            out += "\(show.title) · \(Fmt.date(ep.pubDate))\n"
        }
        out += "\n"
        for line in lines {
            out += "[\(timeStamp(line.t))] \(line.text)\n"
        }
        return out
    }

    private static func markdownExport(ep: Episode, lines: [TranscriptLineModel]) -> String {
        var out = "# \(ep.title)\n\n"
        if let show = ep.show {
            out += "**\(show.title)** · \(Fmt.date(ep.pubDate))"
            if !show.host.isEmpty { out += " · \(show.host)" }
            out += "\n\n"
        }

        if let summary = ep.aiSummary, !summary.isEmpty {
            out += "## Summary\n\n\(summary)\n\n"
        }

        if let takeaways = ep.aiTakeaways, !takeaways.isEmpty {
            out += "## Takeaways\n\n"
            let times = ep.aiTakeawayTimes ?? []
            for (i, text) in takeaways.enumerated() {
                let stamp: String = {
                    guard i < times.count, times[i] >= 0 else { return "" }
                    return " _(\(timeStamp(times[i])))_"
                }()
                out += "- \(text)\(stamp)\n"
            }
            out += "\n"
        }

        out += "## Transcript\n\n"
        for line in lines {
            out += "**[\(timeStamp(line.t))]** \(line.text)\n\n"
        }

        let highlights = ep.highlights.sorted(by: { $0.at < $1.at })
        if !highlights.isEmpty {
            out += "## Highlights\n\n"
            for h in highlights {
                out += "> \(h.quote)\n> — \(timeStamp(h.at))\n\n"
            }
        }

        // Attribution footer — keeps the file traceable back to Pode
        // and gives recipients a one-click path to the app.
        out += "---\n\n_Generated by [pode](\(websiteURL)) — local-first podcast transcripts on macOS._\n"
        return out
    }

    private static func srtExport(lines: [TranscriptLineModel]) -> String {
        // SRT requires an end time per cue. We use the next line's t
        // as the end, with a 3s cap so a final monologue doesn't
        // stretch into a 30-minute caption. Last line gets +3s by
        // default.
        var out = ""
        for (i, line) in lines.enumerated() {
            let start = line.t
            let nextT = (i + 1 < lines.count) ? lines[i + 1].t : (start + 3)
            let end = min(nextT, start + 8)   // hard cap each cue at 8s
            out += "\(i + 1)\n"
            out += "\(srtTime(start)) --> \(srtTime(end))\n"
            out += "\(line.text)\n\n"
        }
        return out
    }

    /// "h:mm:ss" when > 1h else "mm:ss". Used in markdown / plain text.
    private static func timeStamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// SRT requires `HH:MM:SS,mmm` (comma decimal separator).
    private static func srtTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let ms = Int((seconds - Double(total)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// Open a Save panel and write `content` to the chosen location.
    /// `defaultName` should NOT include the extension — we add it
    /// from `format`.
    @MainActor
    static func saveToFile(_ content: String, defaultName: String,
                           format: TranscriptFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(defaultName).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Sanitize an episode title for use as a filename. Strips slashes
    /// and control chars, caps length at 80 to keep Finder happy.
    static func suggestedFilename(for ep: Episode) -> String {
        var name = ep.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*|\""))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > 80 { name = String(name.prefix(80)) }
        return name.isEmpty ? "transcript" : name
    }
}
