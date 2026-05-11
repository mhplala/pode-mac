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

    /// Total ms spent in EpisodeView body in the last 1s window.
    /// Maxes out around 1000 (entire window inside body). > 200ms ≈
    /// stuttering; > 500ms ≈ visibly frozen.
    private(set) var bodyMsPerSec: Int = 0
    /// Same idea for ScrubberRow (dock).
    private(set) var dockMsPerSec: Int = 0
    /// The slowest individual body re-eval seen in the last window.
    /// A single 200ms hitch is worse than 20×10ms ones.
    private(set) var worstBodyMs: Int = 0
    private(set) var worstDockMs: Int = 0

    private(set) var totalBodyEvals: Int = 0
    private(set) var totalDockEvals: Int = 0
    private(set) var totalScrolls: Int = 0

    // Running counts in the current 1s window
    private var bodyEvals = 0
    private var dockEvals = 0
    private var ticks = 0
    private var scrolls = 0
    private var activeLineChanges = 0
    private var bodyNs: UInt64 = 0
    private var dockNs: UInt64 = 0
    private var worstBodyNs: UInt64 = 0
    private var worstDockNs: UInt64 = 0
    private var windowStart = Date()

    private static let log = Logger(subsystem: "studio.steve.pode",
                                    category: "perf")

    func bodyEval()           { bodyEvals += 1; totalBodyEvals += 1; flushIfDue() }
    func dockEval()           { dockEvals += 1; totalDockEvals += 1; flushIfDue() }
    func tick()               { ticks += 1; flushIfDue() }
    func scrollFired()        { scrolls += 1; totalScrolls += 1; flushIfDue() }
    func activeLineChanged()  { activeLineChanges += 1; flushIfDue() }

    /// Record nanoseconds spent in one body re-eval. Call sites wrap
    /// their body in `measure { ... }` (defined below).
    func recordBody(ns: UInt64) {
        bodyNs &+= ns
        if ns > worstBodyNs { worstBodyNs = ns }
        if ns > 33_000_000 {   // > 33ms = missed 2 frames at 60fps
            Self.log.warning("SLOW body \(ns / 1_000_000)ms")
        }
    }
    func recordDock(ns: UInt64) {
        dockNs &+= ns
        if ns > worstDockNs { worstDockNs = ns }
        if ns > 33_000_000 {
            Self.log.warning("SLOW dock \(ns / 1_000_000)ms")
        }
    }

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
        bodyMsPerSec = Int((Double(bodyNs) / 1_000_000 * factor).rounded())
        dockMsPerSec = Int((Double(dockNs) / 1_000_000 * factor).rounded())
        worstBodyMs = Int(worstBodyNs / 1_000_000)
        worstDockMs = Int(worstDockNs / 1_000_000)

        Self.log.info("body=\(self.bodyEvalsPerSec)/\(self.bodyMsPerSec)ms(worst \(self.worstBodyMs)) dock=\(self.dockEvalsPerSec)/\(self.dockMsPerSec)ms(worst \(self.worstDockMs)) tick=\(self.ticksPerSec) scroll=\(self.scrollsPerSec) line=\(self.activeLineChangesPerSec)")

        bodyEvals = 0
        dockEvals = 0
        ticks = 0
        scrolls = 0
        activeLineChanges = 0
        bodyNs = 0
        dockNs = 0
        worstBodyNs = 0
        worstDockNs = 0
        windowStart = now
    }
}

/// Wrap a SwiftUI body expression to measure its evaluation time. The
/// timing is the cost of *constructing* the View tree (and any work
/// done inline), not the cost of actually rendering it — but
/// expensive constructs (sorts, predicate scans, allocs) show up here
/// and are usually the proximate cause of "this re-eval costs 80ms".
@MainActor
func measureBody<Content: View>(_ kind: BodyMeasureKind, @ViewBuilder _ build: () -> Content) -> Content {
    let start = DispatchTime.now()
    let v = build()
    let ns = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
    switch kind {
    case .episode:    PerfCounters.shared.recordBody(ns: ns)
    case .scrubber:   PerfCounters.shared.recordDock(ns: ns)
    }
    return v
}

enum BodyMeasureKind {
    case episode, scrubber
}

/// Compact monospace HUD overlaid on EpisodeView. Polls
/// `PerfCounters.shared` every 0.5s via Timer — does NOT bind to it
/// directly. That keeps the counter writes (which happen inside view
/// bodies) totally invisible to SwiftUI's dependency graph; only this
/// HUD's local @State drives any re-render, and it changes at a
/// throttled, predictable rate.
struct PerfHUD: View {
    @State private var bodyVal: Int = 0
    @State private var bodyMs: Int = 0
    @State private var worstBodyMs: Int = 0
    @State private var dockVal: Int = 0
    @State private var dockMs: Int = 0
    @State private var worstDockMs: Int = 0
    @State private var tickVal: Int = 0
    @State private var scrollVal: Int = 0
    @State private var lineVal: Int = 0

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Per-row format: label ·  count · totalMs · worstMs
            // Counts are events/sec; totalMs is main-thread time spent
            // in that body in the last 1s window; worst is the single
            // slowest re-eval (frame-budget at 60fps = 16ms).
            timeRow("body",   bodyVal, bodyMs, worstBodyMs, warnMs: 100, warnWorst: 33)
            timeRow("dock",   dockVal, dockMs, worstDockMs, warnMs: 50,  warnWorst: 33)
            row("tick",   tickVal, warnAt: 4)
            row("scroll", scrollVal, warnAt: 2)
            row("line",   lineVal, warnAt: 6)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
        )
        .allowsHitTesting(false)
        .onReceive(tick) { _ in
            let c = PerfCounters.shared
            if bodyVal      != c.bodyEvalsPerSec        { bodyVal      = c.bodyEvalsPerSec }
            if bodyMs       != c.bodyMsPerSec            { bodyMs       = c.bodyMsPerSec }
            if worstBodyMs  != c.worstBodyMs             { worstBodyMs  = c.worstBodyMs }
            if dockVal      != c.dockEvalsPerSec        { dockVal      = c.dockEvalsPerSec }
            if dockMs       != c.dockMsPerSec            { dockMs       = c.dockMsPerSec }
            if worstDockMs  != c.worstDockMs             { worstDockMs  = c.worstDockMs }
            if tickVal      != c.ticksPerSec            { tickVal      = c.ticksPerSec }
            if scrollVal    != c.scrollsPerSec          { scrollVal    = c.scrollsPerSec }
            if lineVal      != c.activeLineChangesPerSec { lineVal      = c.activeLineChangesPerSec }
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

    private func timeRow(_ label: String, _ count: Int, _ totalMs: Int, _ worstMs: Int,
                         warnMs: Int, warnWorst: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 42, alignment: .leading)
            Text("\(count)")
                .bold()
                .frame(width: 24, alignment: .trailing)
            Text("\(totalMs)ms")
                .foregroundColor(totalMs >= warnMs ? Color(hex: "#ff7e6b") : .white.opacity(0.85))
                .frame(width: 48, alignment: .trailing)
            Text("w\(worstMs)")
                .foregroundColor(worstMs >= warnWorst ? Color(hex: "#ff7e6b") : .white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)
        }
    }
}
