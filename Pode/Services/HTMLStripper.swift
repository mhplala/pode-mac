import Foundation

/// Lightweight HTML → plain text converter for podcast descriptions.
///
/// We intentionally don't pull in a full HTML parser. Podcast descriptions
/// are short and the universe of tags we care about is small:
/// `<br>`, `<p>`, `<div>`, `<li>`, `<h1..6>`, `<ul>`, `<ol>` collapse
/// into newlines (so paragraph breaks survive), and everything else is
/// stripped. Common HTML entities (`&nbsp;`, `&amp;`, `&lt;`, `&gt;`,
/// `&quot;`, `&#39;`, `&apos;`, `&hellip;`) are decoded back to their
/// glyph form.
///
/// This is used in two places:
///
/// - `ChapterParser` runs descriptions through it before scanning for
///   timestamps, so feeds that ship `<p>06:20 Intro</p>` parse the same
///   as `06:20 Intro`.
/// - The description tab renders the stripped text + URL detection on
///   top, so users see clean prose rather than `<p>...</p>` markup.
enum HTMLStripper {
    /// Strip HTML tags and decode common entities. Returns the original
    /// string unchanged if it contains no tag-shaped sequences (cheap
    /// fast-path for plain-text feeds, which is the common case for
    /// Chinese podcasts).
    static func toPlainText(_ s: String) -> String {
        // Fast path: no `<` means there's nothing to strip and probably
        // no entities either. Skip the regex work.
        guard s.contains("<") || s.contains("&") else { return s }

        var out = s

        // Block-level tags become paragraph breaks so the text isn't
        // run-on after stripping. Inline tags (a, b, i, em, strong,
        // span) leave no break — we want their contents glued in.
        out = out.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"</?(p|div|li|ul|ol|h[1-6]|tr|article|section)[^>]*>"#,
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip remaining tags, including comments and self-closing.
        out = out.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode the entities that actually show up in podcast feeds.
        // Anything more exotic than this is rare enough to not bother
        // with a full entity table.
        let entities: [(String, String)] = [
            ("&nbsp;",   " "),
            ("&amp;",    "&"),
            ("&lt;",     "<"),
            ("&gt;",     ">"),
            ("&quot;",   "\""),
            ("&apos;",   "'"),
            ("&#39;",    "'"),
            ("&hellip;", "…"),
            ("&mdash;",  "—"),
            ("&ndash;",  "–"),
            ("&ldquo;",  "“"),
            ("&rdquo;",  "”"),
            ("&lsquo;",  "‘"),
            ("&rsquo;",  "’")
        ]
        for (from, to) in entities {
            out = out.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }

        // Collapse 3+ consecutive newlines down to 2. After block-tag
        // replacement we can end up with `\n\n\n\n` between paragraphs,
        // which looks like dropouts in the rendered output.
        out = out.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
