import Foundation
import AppKit
import Observation

/// Lightweight SemVer for "x.y.z" comparisons. Stores numeric parts;
/// treats missing trailing components as zero so `0.5 == 0.5.0`.
struct SemVer: Comparable {
    let parts: [Int]

    init?(_ s: String) {
        // Strip optional `v` prefix and any pre-release tag after `-`
        // — for Pode versions we don't use pre-release tags, but it's
        // cheap insurance against future variations like "1.0.0-beta".
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")
        let core = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        let a = lhs.parts, b = rhs.parts
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

/// Periodically polls `podecast.cc/version.json` to see whether a newer
/// build of Pode is published. Notification-style (NOT silent auto-
/// update) — when an update is available we surface a chip in the UI;
/// the user clicks through to download the DMG.
///
/// Match the spirit of Claude Code's "new version available, run `npm
/// install -g ...`" banner — no Sparkle, no helper-tool dance, no
/// system-extension permissions. Cheap, transparent, ergonomic.
@MainActor
@Observable
final class UpdateChecker {

    /// Currently-published payload from the server. `nil` until we've
    /// successfully fetched, or after the user skips a version.
    private(set) var available: AvailableUpdate? = nil

    /// Set after a successful (or failed) check so the UI can show
    /// "Last checked 2 minutes ago".
    private(set) var lastCheckAt: Date? = nil

    /// `true` while a check is in flight — drives a small spinner on
    /// the Settings → About "Check now" button.
    private(set) var isChecking: Bool = false

    /// User-dismissed version. Persisted in UserDefaults so a quit
    /// doesn't bring back the banner for a release the user said
    /// "skip" to. Cleared when an even-newer version supersedes.
    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.skippedKey) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: Self.skippedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.skippedKey)
            }
        }
    }
    private static let skippedKey = "pode.update.skippedVersion"

    /// `version.json` endpoint — published alongside each DMG.
    private let endpoint = URL(string: "https://podecast.cc/version.json")!

    /// Throttle: skip in-flight if we already checked within this window.
    private let checkInterval: TimeInterval = 24 * 60 * 60   // 24h

    struct AvailableUpdate: Equatable {
        let version: String
        let downloadURL: URL
        let releaseNotes: String
        let publishedAt: Date?
    }

    /// Fire on app launch + bind to `Scene` phase so we check again
    /// after long backgrounding. Internally throttled — safe to call
    /// from many sites.
    func checkIfDue() async {
        if let last = lastCheckAt,
           Date().timeIntervalSince(last) < checkInterval { return }
        await checkNow()
    }

    /// Force-fetch ignoring the throttle window. Wire to "Check for
    /// updates" buttons.
    func checkNow() async {
        if isChecking { return }
        isChecking = true
        defer { isChecking = false }
        defer { lastCheckAt = .now }

        do {
            // Cache-busting query so a stale GitHub Pages CDN entry
            // doesn't pin us on an old version for hours.
            let url = endpoint.appending(queryItems: [
                URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
            ])
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)

            guard let remoteVer = SemVer(decoded.version),
                  let currentVer = SemVer(currentVersionString),
                  remoteVer > currentVer else {
                available = nil
                return
            }

            // Respect "skip this version" — but only for the EXACT
            // version skipped. A subsequent release re-surfaces.
            if let skipped = skippedVersion,
               let skippedVer = SemVer(skipped),
               skippedVer == remoteVer {
                available = nil
                return
            }

            // Minimum-OS gate — don't tempt the user with an upgrade
            // they can't install.
            if let minOS = decoded.minimumOS,
               let minSemVer = SemVer(minOS),
               currentOSVersion < minSemVer {
                available = nil
                return
            }

            guard let dlURL = URL(string: decoded.downloadURL) else {
                available = nil
                return
            }

            available = AvailableUpdate(
                version: decoded.version,
                downloadURL: dlURL,
                releaseNotes: decoded.releaseNotes ?? "",
                publishedAt: decoded.publishedAt.flatMap { Self.iso.date(from: $0) }
            )
        } catch {
            // Silent: network blips / proxy issues shouldn't bother
            // the user. The chip just stays hidden until next check.
        }
    }

    /// User clicked "Skip this version". Remembers across launches.
    func skipCurrent() {
        guard let v = available?.version else { return }
        skippedVersion = v
        available = nil
    }

    /// Opens the DMG URL in the user's default browser. They click
    /// → Safari downloads → drag to /Applications. Same as today,
    /// just discovered automatically.
    func openDownload() {
        guard let url = available?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private struct Response: Decodable {
        let version: String
        let downloadURL: String
        let releaseNotes: String?
        let publishedAt: String?
        let minimumOS: String?
    }

    private var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var currentOSVersion: SemVer {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return SemVer("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)") ?? SemVer("0.0.0")!
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private extension URL {
    /// Backport of `appending(queryItems:)` for macOS 14 (it landed
    /// in 13 but the variant taking a sequence is sometimes ambiguous).
    func appending(queryItems items: [URLQueryItem]) -> URL {
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        var existing = comps.queryItems ?? []
        existing.append(contentsOf: items)
        comps.queryItems = existing
        return comps.url ?? self
    }
}
