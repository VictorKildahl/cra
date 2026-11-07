import Foundation

/// Everything the recorder holds in memory for one session, and the report made from it. The
/// recorder keeps one behind a lock; every change is a call here, so what a report says is
/// decided (and tested) in one place. Times are seconds since Cra started (PerfSessionInfo.startedAt).
public struct PerfState: Sendable {
    public var policy = PerfStallPolicy()
    public private(set) var passes = LogHistogram()
    public private(set) var timings: [PerfMetric: LogHistogram] = [:]
    public private(set) var counters: [PerfCounter: [String: Int]] = [:]
    public private(set) var stalls = PerfRing<PerfStall>(capacity: 40)
    public private(set) var freezeCount = 0
    public private(set) var longFreezeCount = 0
    public private(set) var hangCount = 0
    public private(set) var outsideFreezes = 0
    public private(set) var longestFreezeMs: Double = 0
    /// The longest stall of any mode, and its mode.
    public private(set) var longestStall: (ms: Double, mode: String)?
    public var slowPass: PerfHang?
    public private(set) var marks = PerfRing<PerfMark>(capacity: 64)
    public private(set) var events = PerfRing<PerfEvent>(capacity: 150)
    public private(set) var longTasks = 0
    public private(set) var longTaskMs: Double = 0
    public private(set) var page = PerfPageFrames()
    public private(set) var idle = PerfReport.Idle()
    public private(set) var startup: [String: Double] = [:]
    public var processes: [PerfProcessGroup] = []
    public var system: PerfSystemSample?
    public var tabs: PerfTabCounts?
    /// The host of the page Cra put on screen last (nil for none or incognito), for stalls.
    public var visibleSite: String?
    /// Cra the active app, and a window of it on screen; nil until the app says.
    public var appActive: Bool?
    public var appOnScreen: Bool?
    /// No keyboard or mouse input on the Mac for a minute, as of the last main-thread sample.
    public var userIdle = false
    private var historyBase = (stalls: 0, long: 0, longTasks: 0, crashes: 0)

    public init() {}

    public mutating func mark(_ label: String, at: Double) { marks.append(PerfMark(at: at, label: label)) }

    public mutating func time(_ metric: PerfMetric, ms: Double) { timings[metric, default: LogHistogram()].record(ms) }

    /// Main-loop passes measured since the last call (the observer keeps its own histogram so the
    /// main thread never waits on this state for a short pass).
    public mutating func addPasses(_ h: LogHistogram) { passes.add(h) }

    /// A pass of `ms` that ended at `at`: counted, and returned when it is a stall.
    @discardableResult
    public mutating func pass(ms: Double, endedAt at: Double, mode: String) -> PerfStall? {
        guard let s = policy.stall(at: at, ms: ms, mode: mode, marks: marks.elements, site: visibleSite,
                                   active: appActive, onScreen: appOnScreen) else { return nil }
        stalls.append(s)
        if ms > longestStall?.ms ?? 0 { longestStall = (ms, s.mode) }
        guard s.freeze else { outsideFreezes += 1; return s }
        freezeCount += 1
        if s.kind != .stall { longFreezeCount += 1 }
        if s.kind == .hang { hangCount += 1 }
        longestFreezeMs = max(longestFreezeMs, ms)
        if s.kind != .stall {
            events.append(PerfEvent(at: at, kind: s.kind == .hang ? "hang" : "freeze",
                                    detail: s.marks.last.map { "after \($0)" } ?? "", ms: ms, site: s.site))
        }
        return s
    }

    /// A counted fact; renderer trouble and failed loads are events as well.
    public mutating func count(_ counter: PerfCounter, key: String, at: Double, site: String? = nil) {
        counters[counter, default: [:]][key, default: 0] += 1
        switch counter {
        case .rendererTerminated: events.append(PerfEvent(at: at, kind: "renderer", detail: key, site: site))
        case .rendererUnresponsive: events.append(PerfEvent(at: at, kind: "renderer", detail: "unresponsive", site: site))
        case .rendererResponsive: events.append(PerfEvent(at: at, kind: "renderer", detail: "responsive again", site: site))
        case .loadError: events.append(PerfEvent(at: at, kind: "load", detail: "error \(key)", site: site))
        case .tabSlept, .sleepRefusal, .sleepRetry, .sleepSkip, .fileSaved: break
        }
    }

    /// The visible tab's long tasks since the last read (count, total, and each duration).
    public mutating func pageLongTasks(count: Int, totalMs: Double, durations: [Double]) {
        guard count > 0 else { return }
        longTasks += count
        longTaskMs += max(0, totalMs)
        for d in durations.prefix(100) { time(.longTask, ms: d) }
    }

    /// The visible tab's late frames and video frames since the last read.
    public mutating func pageFrames(_ f: PerfPageFrames) { page.add(f) }

    /// A 5-second sample of Cra's CPU (percent of a core, all processes), counted when idle.
    public mutating func idleSample(cpuPct: Double) {
        guard userIdle else { return }
        idle.cpuPct = (idle.cpuPct * Double(idle.samples) + cpuPct) / Double(idle.samples + 1)
        idle.samples += 1
    }

    /// A start-up phase, the first time it is reached (milliseconds since the process started).
    public mutating func phase(_ name: String, ms: Double) {
        if startup[name] == nil { startup[name] = ms }
    }

    /// The counts since the last history sample, with the current levels.
    public mutating func historySample() -> PerfHistorySample {
        let crashes = counters[.rendererTerminated]?.values.reduce(0, +) ?? 0
        let s = PerfHistorySample(cpuPct: processes.reduce(0) { $0 + $1.cpuPct },
                                  footprintBytes: processes.reduce(0) { $0 + $1.footprintBytes },
                                  stalls: freezeCount - historyBase.stalls, longStalls: longFreezeCount - historyBase.long,
                                  longTasks: longTasks - historyBase.longTasks, rendererCrashes: crashes - historyBase.crashes,
                                  liveTabs: tabs?.live ?? 0)
        historyBase = (freezeCount, longFreezeCount, longTasks, crashes)
        return s
    }

    public func report(generatedAt: Date, session: PerfSessionInfo, selfCost: PerfSelfCost,
                       storage: PerfReport.Storage = PerfReport.Storage()) -> PerfReport {
        var storage = storage
        if storage.freeDiskBytes == nil { storage.freeDiskBytes = system?.freeDiskBytes }
        var r = PerfReport(
            generatedAt: generatedAt, session: session, selfCost: selfCost,
            mainThread: .init(passes: passes, freezes: freezeCount, longFreezes: longFreezeCount, hangs: hangCount,
                              outsideFreezes: outsideFreezes, longestFreezeMs: longestFreezeMs,
                              // The histogram is pulled every 5 s; a stall is known as soon as it ends.
                              longestPassMs: max(passes.maxMs, longestStall?.ms ?? 0), longestPassMode: longestStall?.mode,
                              recent: stalls.elements, slowPass: slowPass),
            processes: processes, system: system,
            tabs: .init(latest: tabs, longTasks: longTasks, longTaskMs: longTaskMs, longFrames: page.longFrames,
                        longestFrameMs: page.longestFrameMs, videoFrames: page.videoFrames, droppedVideoFrames: page.droppedVideoFrames),
            timings: Dictionary(uniqueKeysWithValues: timings.map { ($0.key.rawValue, $0.value) }),
            counters: Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) }),
            startup: startup, storage: storage, events: events.elements, idle: idle, insights: [])
        r.insights = PerfInsights.evaluate(r)
        return r
    }

    /// About how much memory this holds: the budget is 5 MB.
    public var estimatedBytes: Int {
        let histograms = (timings.count + 1) * (LogHistogram.bucketCount + 3) * 8
        let marksBytes = marks.elements.reduce(0) { $0 + 32 + $1.label.utf8.count }
        let stallBytes = stalls.elements.reduce(0) { $0 + 96 + $1.marks.reduce(0) { $0 + $1.utf8.count + 16 } }
        let eventBytes = events.elements.reduce(0) { $0 + 80 + $1.detail.utf8.count + ($1.site?.utf8.count ?? 0) }
        let slowBytes = slowPass.map { 128 + $0.stack.reduce(0) { $0 + $1.utf8.count + 16 } } ?? 0
        return 1024 + histograms + marksBytes + stallBytes + eventBytes + slowBytes + processes.count * 96
    }
}

/// What the visible page reports about its frames between two reads (PageScript's `__cra.lf`
/// and `getVideoPlaybackQuality()`), added up over the session.
public struct PerfPageFrames: Equatable, Sendable {
    public var longFrames = 0
    public var longestFrameMs: Double = 0
    public var videoFrames = 0
    public var droppedVideoFrames = 0

    public init(longFrames: Int = 0, longestFrameMs: Double = 0, videoFrames: Int = 0, droppedVideoFrames: Int = 0) {
        self.longFrames = longFrames
        self.longestFrameMs = longestFrameMs
        self.videoFrames = videoFrames
        self.droppedVideoFrames = droppedVideoFrames
    }

    /// A page can answer garbage: negative counts are dropped, a dropped count never exceeds the frames.
    public mutating func add(_ f: PerfPageFrames) {
        longFrames += max(0, f.longFrames)
        if f.longestFrameMs.isFinite { longestFrameMs = max(longestFrameMs, f.longestFrameMs) }
        let total = max(0, f.videoFrames)
        videoFrames += total
        droppedVideoFrames += min(max(0, f.droppedVideoFrames), total)
    }
}
