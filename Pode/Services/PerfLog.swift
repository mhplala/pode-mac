import SwiftUI
import os

/// In-app live performance counters + HUD. Designed for debugging the
/// "why is playback laggy" class of issue without an Instruments trace.
///
/// Bump counters from the relevant call sites:
///   PerfCounters.shared.bodyEval()          // EpisodeView body re-eval
///   PerfCounters.shared.dockEval()          // ScrubberRow body re-eval
///   PerfCounters.shared.tick()              // player.currentTime onChange
///   PerfCounters.shared.scrollFired()       // auto-scrollTo invocation
///   PerfCounters.shared.activeLineChanged() // activeLineIdx flipped
///
/// `PerfHUD()` overlays them on the screen. Each window is 1 second.
@MainActor
@Observable
final class PerfCounters {
    static let shared = PerfCounters()

    // Per-1s normalized snapshots (events per second).
    var bodyEvalsPerSec: Int = 0
    var dockEvalsPerSec: Int = 0
    var ticksPerSec: Int = 0
    var scrollsPerSec: Int = 0
    var activeLineChangesPerSec: Int = 0

    /// Total counters since launch — useful for sanity-checking trends.
    var totalBodyEvals: Int = 0
    var totalDockEvals: Int = 0
    var totalScrolls: Int = 0

    // Running counts in the current window
    private var bodyEvals = 0
    private var dockEvals = 0
    private var ticks = 0
    private var scrolls = 0
    private var activeLineChanges = 0
    private var windowStart = Date()

    private static let log = Logger(subsystem: "studio.steve.pode",
                                    category: "perf")

    func bodyEval()           { bodyEvals += 1; totalBodyEvals += 1; flushIfDue() }
    func dockEval()           { dockEvals += 1; totalDockEvals += 1; flushIfDue() }
    func tick()               { ticks += 1; flushIfDue() }
    func scrollFired()        { scrolls += 1; totalScrolls += 1; flushIfDue() }
    func activeLineChanged()  { activeLineChanges += 1; flushIfDue() }

    private func flushIfDue() {
        let now = Date()
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed >= 1.0 else { return }
        // Normalize to events/sec — if the user backgrounded the app
        // for 3 seconds the count would otherwise look artificially
        // small in the resumed window.
        let factor = 1.0 / elapsed
        bodyEvalsPerSec        = Int((Double(bodyEvals)        * factor).rounded())
        dockEvalsPerSec        = Int((Double(dockEvals)        * factor).rounded())
        ticksPerSec            = Int((Double(ticks)            * factor).rounded())
        scrollsPerSec          = Int((Double(scrolls)          * factor).rounded())
        activeLineChangesPerSec = Int((Double(activeLineChanges) * factor).rounded())

        Self.log.info("body=\(self.bodyEvalsPerSec) dock=\(self.dockEvalsPerSec) tick=\(self.ticksPerSec) scroll=\(self.scrollsPerSec) lineChange=\(self.activeLineChangesPerSec)")

        bodyEvals = 0
        dockEvals = 0
        ticks = 0
        scrolls = 0
        activeLineChanges = 0
        windowStart = now
    }
}

/// Compact monospace HUD that lives in the top-right of EpisodeView (or
/// wherever you attach it). Updates once per second.
struct PerfHUD: View {
    @Bindable private var c = PerfCounters.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("body",   c.bodyEvalsPerSec,        warnAt: 10)
            row("dock",   c.dockEvalsPerSec,        warnAt: 5)
            row("tick",   c.ticksPerSec,            warnAt: 4)
            row("scroll", c.scrollsPerSec,          warnAt: 2)
            row("line",   c.activeLineChangesPerSec, warnAt: 6)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.62))
        )
        .allowsHitTesting(false)   // never block the UI underneath
    }

    /// Each row colors red when above its warn threshold — so a glance
    /// at the HUD during a laggy moment immediately surfaces which
    /// metric spiked.
    private func row(_ label: String, _ value: Int, warnAt: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 42, alignment: .leading)
            Text("\(value)")
                .bold()
                .foregroundColor(value >= warnAt ? Color(hex: "#ff7e6b") : .white)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
