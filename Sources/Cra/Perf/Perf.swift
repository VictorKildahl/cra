import Foundation

/// The one way the rest of Cra reaches the performance recorder (GitHub #91, docs/performance.md).
/// Small facts, recorded under one lock: a duration, a count, a breadcrumb. Nothing here does
/// file I/O, encoding or system calls, and it depends on neither CEF nor libproc, so the test
/// harnesses compile the files that call it unchanged. Until the recorder starts the facts wait
/// in a short buffer (start-up decodes JSON before Chromium is up); when recording is off they
/// are dropped.
enum Perf {
    /// One fact for the recorder; `at` is `Perf.now()`.
    enum Fact {
        case time(PerfMetric, ms: Double)
        case count(PerfCounter, key: String, site: String?, at: UInt64)
        case mark(String, at: UInt64)
        case phase(String, ms: Double)
        case visibleSite(String?)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var sink: ((Fact) -> Void)?
    nonisolated(unsafe) private static var early: [Fact]? = []
    nonisolated(unsafe) private static var started: [String: UInt64] = [:]
    nonisolated(unsafe) private(set) static var launchedAt: UInt64 = now()

    /// Monotonic nanoseconds (the clock DispatchTime and mach_absolute_time share).
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    static func ms(since t: UInt64) -> Double { Double(now() &- t) / 1e6 }

    /// The top of main.swift: start-up phases count from here.
    static func launch() { launchedAt = now() }

    /// The recorder, once it starts; nil when recording is off (buffered facts are dropped).
    static func attach(_ newSink: ((Fact) -> Void)?) {
        lock.lock()
        sink = newSink
        let pending = early ?? []
        early = nil
        started = [:]
        lock.unlock()
        if let newSink { pending.forEach(newSink) }
    }

    static var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sink != nil
    }

    private static func send(_ fact: Fact) {
        lock.lock()
        if early != nil {
            if early!.count < 256 { early!.append(fact) }
            lock.unlock()
            return
        }
        let s = sink
        lock.unlock()
        s?(fact)
    }

    static func time(_ metric: PerfMetric, ms: Double) { send(.time(metric, ms: ms)) }

    /// Times `work` on the calling thread.
    @discardableResult
    static func time<T>(_ metric: PerfMetric, _ work: () throws -> T) rethrows -> T {
        let t = now()
        defer { time(metric, ms: ms(since: t)) }
        return try work()
    }

    static func count(_ counter: PerfCounter, _ key: String = "", site: String? = nil) {
        send(.count(counter, key: key, site: site, at: now()))
    }

    /// A breadcrumb (HitchMonitor.mark forwards here): what a stall report says Cra did before it.
    static func mark(_ label: String) { send(.mark(label, at: now())) }

    /// A start-up phase reached, in milliseconds since `launch()`; only the first counts.
    static func phase(_ name: String) { send(.phase(name, ms: ms(since: launchedAt))) }

    /// The site of the page put on screen last, for the stalls that happen while it is (nil: none,
    /// or incognito).
    static func visibleSite(_ host: String?) { send(.visibleSite(host)) }

    /// A duration that ends on another call: `begin` and `end` with the same key. A begin
    /// without an end (a page closed while loading) is forgotten by `cancel` or the next begin.
    static func begin(_ metric: PerfMetric, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard sink != nil || early != nil else { return }
        // Keys are tab ids; a leak (begins that never end) is cut off rather than kept.
        if started.count > 512 { started = [:] }
        started[metric.rawValue + key] = now()
    }

    static func end(_ metric: PerfMetric, _ key: String) {
        lock.lock()
        let t = started.removeValue(forKey: metric.rawValue + key)
        lock.unlock()
        if let t { time(metric, ms: ms(since: t)) }
    }

    static func cancel(_ metric: PerfMetric, _ key: String) {
        lock.lock()
        started[metric.rawValue + key] = nil
        lock.unlock()
    }
}
