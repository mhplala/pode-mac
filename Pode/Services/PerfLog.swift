import SwiftUI
import os

/// In-app live performance counters + HUD. Designed for debugging the
/// "why is playback laggy" class of issue without an Instruments trace.
///
/// **Critical**: `PerfCounters` is a plain class (NOT @Observable). It's
/// safe to call its `bodyEval()` / `dockEval()` from inside a SwiftUI
/// view body because none of its writes are observed by SwiftUI — they
/// only flow through `PerfHUD`'s own @State via a Timer poll. An earlier
/// version made the counters @Observable, which caused SwiftUI to
/// detect mid-body state mutation, refuse to settle the dependency
/// graph, and freeze the entire EpisodeView at "loading…".
@MainActor
final class PerfCounters {
    static let shared = PerfCounters()

    // Per-1s normalized snapshots (events per second). Written by
    // `flushIfDue`, read by `PerfHUD` via Timer poll — never observed
    // by SwiftUI directly.
    private(set) var bodyEvalsPerSec: Int = 0
    private(set) var dockEvalsPerSec: Int = 0
    private(set) var ticksPerSec: Int = 0
    private(set) var scrollsPerSec: Int = 0
    private(set) var activeLineChangesPerSec: Int = 0

    private(set) var totalBodyEvals: Int = 0
    private(set) var totalDockEvals: Int = 0
    private(set) var totalScrolls: Int = 0

    // Running counts in the current 1s window
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

/// Compact monospace HUD overlaid on EpisodeView. Polls
/// `PerfCounters.shared` every 0.5s via Timer — does NOT bind to it
/// directly. That keeps the counter writes (which happen inside view
/// bodies) totally invisible to SwiftUI's dependency graph; only this
/// HUD's local @State drives any re-render, and it changes at a
/// throttled, predictable rate.
struct PerfHUD: View {
    @State private var bodyVal: Int = 0
    @State private var dockVal: Int = 0
    @State private var tickVal: Int = 0
    @State private var scrollVal: Int = 0
    @State private var lineVal: Int = 0

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("body",   bodyVal,   warnAt: 10)
            row("dock",   dockVal,   warnAt: 5)
            row("tick",   tickVal,   warnAt: 4)
            row("scroll", scrollVal, warnAt: 2)
            row("line",   lineVal,   warnAt: 6)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.62))
        )
        .allowsHitTesting(false)
        .onReceive(tick) { _ in
            // Pull the latest snapshot. Writing to @State here is safe
            // because it's a side effect of a Combine publisher, not a
            // mid-body mutation.
            let c = PerfCounters.shared
            if bodyVal   != c.bodyEvalsPerSec        { bodyVal   = c.bodyEvalsPerSec }
            if dockVal   != c.dockEvalsPerSec        { dockVal   = c.dockEvalsPerSec }
            if tickVal   != c.ticksPerSec            { tickVal   = c.ticksPerSec }
            if scrollVal != c.scrollsPerSec          { scrollVal = c.scrollsPerSec }
            if lineVal   != c.activeLineChangesPerSec { lineVal   = c.activeLineChangesPerSec }
        }
    }

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
