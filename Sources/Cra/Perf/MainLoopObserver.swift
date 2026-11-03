import Foundation
import os

/// How long the main thread works between two points where what it did reaches the screen,
/// measured from the run loop itself. A pass starts when the loop wakes up and ends where Core
/// Animation commits: before the loop goes to sleep, or when the loop returns to AppKit (exit),
/// which then handles the event it returned for, so the next pass starts there. A slept-through
/// time is never a pass, and an event, its handler, layout and commit are one pass, not several.
/// Unlike HitchMonitor it sends the main thread nothing; the cost is a clock read and an
/// uncontended lock per callback.
///
/// A long pass is seen while it lasts by a watchdog thread (2 Hz), which reports it from its own
/// thread (the main thread is the one that's stuck): once at `slowMs`, again at `hangMs`.
final class MainLoopObserver: @unchecked Sendable {
    struct Drained {
        var passes: LogHistogram
        var callbacks: Int
        /// Estimated main-thread time spent in the callbacks, and the watchdog thread's CPU time.
        var observerNs: UInt64
        var watchdogNs: UInt64
    }

    private struct Shared {
        /// When the current pass started; 0 while the run loop sleeps or before it first runs.
        var passStart: UInt64 = 0
        var passes = LogHistogram()
        var callbacks = 0
        var sampledNs: UInt64 = 0
        var sampled = 0
        var reportedPass: UInt64 = 0
        var reportedSlow: UInt64 = 0
        /// Until the run loop first sleeps: AppKit finishes launching (Cra's bootstrap) inside
        /// -[NSApplication run] before the loop's first pass, where no observer sees it.
        var launching = true
        var watchdogNs: UInt64 = 0
        var stopped = false
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private var observers: [CFRunLoopObserver] = []
    private let stallMs: Double
    private let slowMs: Double
    private let hangMs: Double
    private let onStall: (_ ms: Double, _ endedAt: UInt64, _ mode: String) -> Void
    private let onSlow: (_ ms: Double, _ passStart: UInt64, _ mode: String) -> Void
    private let onHang: (_ ms: Double, _ passStart: UInt64, _ mode: String) -> Void
    private let onWatch: () -> Void

    /// `onStall` runs on the main thread when a pass of `stallMs` or more ends; `onSlow` and
    /// `onHang` on the watchdog thread, once per pass that reaches `slowMs` (below `hangMs`) and
    /// `hangMs` while it still lasts; `onWatch` there at every look (twice a second).
    init(stallMs: Double, slowMs: Double, hangMs: Double, onStall: @escaping (Double, UInt64, String) -> Void,
         onSlow: @escaping (Double, UInt64, String) -> Void, onHang: @escaping (Double, UInt64, String) -> Void,
         onWatch: @escaping () -> Void) {
        self.stallMs = stallMs
        self.slowMs = slowMs
        self.hangMs = hangMs
        self.onStall = onStall
        self.onSlow = onSlow
        self.onHang = onHang
        self.onWatch = onWatch
    }

    func start() {
        guard observers.isEmpty else { return }
        // A pass starts before anyone else's observer runs and ends after everyone's: Core
        // Animation commits (layout, drawing) in a before-waiting and exit observer, and that is
        // main-thread time too. Entry and before-timers are no boundary: a loop entered or turned
        // without sleeping or committing is still the same pass (GitHub #135).
        let first: CFRunLoopActivity = [.afterWaiting]
        let last: CFRunLoopActivity = [.beforeWaiting, .exit]
        for (activities, order) in [(first, Int.min), (last, Int.max)] {
            let o = CFRunLoopObserverCreateWithHandler(nil, activities.rawValue, true, order) { [weak self] _, activity in
                self?.callback(activity)
            }!
            observers.append(o)
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
        }
        // From here (main.swift, before the run loop starts) the main thread is busy launching.
        let now = Perf.now()
        shared.withLock { $0.passStart = now }
        let thread = Thread { [weak self] in self?.watch() }
        thread.name = "PerfWatchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// The observer goes and the watchdog ends within half a second.
    func stop() {
        for o in observers { CFRunLoopObserverInvalidate(o); CFRunLoopRemoveObserver(CFRunLoopGetMain(), o, .commonModes) }
        observers = []
        shared.withLock { $0.stopped = true; $0.passStart = 0 }
    }

    /// What was measured since the last call.
    func drain() -> Drained {
        shared.withLock { s in
            let estimate = s.sampled > 0 ? s.sampledNs / UInt64(s.sampled) * UInt64(s.callbacks) : 0
            let d = Drained(passes: s.passes, callbacks: s.callbacks, observerNs: estimate, watchdogNs: s.watchdogNs)
            s.passes = LogHistogram()
            s.callbacks = 0
            s.sampledNs = 0
            s.sampled = 0
            s.watchdogNs = 0
            return d
        }
    }

    private func callback(_ activity: CFRunLoopActivity) {
        let now = Perf.now()
        let (ended, launch, timed): (Double?, Bool, Bool) = shared.withLock { s in
            s.callbacks += 1
            var ms: Double?
            let launch = s.launching
            switch activity {
            case .afterWaiting:
                if s.passStart == 0 { s.passStart = now }
            default:
                // Before waiting or exit: the pass ends. After an exit AppKit goes on to handle
                // the event the loop returned for, which is the next pass; asleep, nothing is.
                if s.passStart != 0 {
                    let pass = Double(now &- s.passStart) / 1e6
                    s.passes.record(pass)
                    if pass >= stallMs { ms = pass }
                }
                s.passStart = activity == .beforeWaiting ? 0 : now
                if activity == .beforeWaiting { s.launching = false }
            }
            // One callback in 256 is timed, for the self-cost estimate.
            return (ms, launch, s.callbacks & 255 == 0)
        }
        if let ended { onStall(ended, now, launch ? "launch" : Self.currentMode()) }
        if timed {
            let cost = Perf.now() &- now
            shared.withLock { $0.sampledNs += cost; $0.sampled += 1 }
        }
    }

    private func watch() {
        while true {
            usleep(500_000)
            let start = Self.threadCPU()
            let (passStart, stopped, reported, slow, launch) = shared.withLock {
                ($0.passStart, $0.stopped, $0.reportedPass, $0.reportedSlow, $0.launching)
            }
            if stopped { return }
            if passStart != 0, passStart != reported {
                let ms = Double(Perf.now() &- passStart) / 1e6
                let mode = { launch ? "launch" : Self.currentMode() }
                if ms >= hangMs {
                    shared.withLock { $0.reportedPass = passStart; $0.reportedSlow = passStart }
                    onHang(ms, passStart, mode())
                } else if ms >= slowMs, passStart != slow {
                    shared.withLock { $0.reportedSlow = passStart }
                    onSlow(ms, passStart, mode())
                }
            }
            onWatch()
            let cost = Self.threadCPU() &- start
            shared.withLock { $0.watchdogNs += cost + 2_000 }   // + the wakeup itself, about 2 µs
        }
    }

    /// The main run loop's mode right now ("none" between runs).
    static func currentMode() -> String {
        guard let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()) else { return "none" }
        return mode.rawValue as String
    }

    /// CPU time the calling thread has used, in nanoseconds.
    static func threadCPU() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }
}
