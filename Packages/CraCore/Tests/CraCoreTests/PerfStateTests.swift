import CraCore
import Foundation
import Testing

/// GitHub #91: what the recorder keeps, the report made from it, and its readings.
struct PerfStateTests {
    static let start = Date(timeIntervalSince1970: 1_793_000_000)

    static func session(previous: PerfPreviousSession? = nil, uptime: Double = 600) -> PerfSessionInfo {
        PerfSessionInfo(id: "0123abcd", launch: 2, startedAt: start, uptimeSeconds: uptime, craVersion: "0.1.27",
                        chromiumVersion: "156.0.7445.0", onboarding: false, firstLaunchAt: start.addingTimeInterval(-86400),
                        previous: previous, writesFiles: true)
    }

    /// A made-up session: a swipe that froze for 1.2 s on a site, a held menu, a crashed renderer.
    static func sampleState() -> PerfState {
        var s = PerfState()
        s.visibleSite = "video.example.com"
        var passes = LogHistogram()
        for ms in [0.2, 0.4, 3, 12, 300, 1200] { passes.record(ms) }
        s.addPasses(passes)
        s.mark("swipe-begin", at: 100)
        s.mark("page-shown", at: 100.5)
        s.pass(ms: 300, endedAt: 50, mode: "kCFRunLoopDefaultMode")
        s.pass(ms: 1200, endedAt: 101.7, mode: "kCFRunLoopDefaultMode")
        s.pass(ms: 4000, endedAt: 200, mode: "NSEventTrackingRunLoopMode")
        s.time(.tabSwitch, ms: 6)
        s.time(.tabSwitch, ms: 40)
        s.time(.pageCreate, ms: 110)
        s.count(.rendererTerminated, key: "crashed", at: 300, site: "video.example.com")
        s.count(.loadError, key: "-105", at: 310)
        s.count(.sleepRefusal, key: "typed", at: 320)
        s.pageLongTasks(count: 3, totalMs: 420, durations: [60, 120, 240])
        s.phase("main", ms: 12)
        s.phase("cefStarted", ms: 480)
        s.phase("main", ms: 999)
        s.processes = [PerfProcessGroup(kind: .browser, count: 1, cpuPct: 4.5, footprintBytes: 300 << 20, diskReadBytes: 1 << 20,
                                        diskWriteBytes: 2 << 20, wakeups: 1000, started: 0, ended: 0, available: true),
                       PerfProcessGroup(kind: .renderer, count: 3, cpuPct: 12.25, footprintBytes: 900 << 20, diskReadBytes: 0,
                                        diskWriteBytes: 0, wakeups: 5000, started: 4, ended: 1, available: true)]
        s.system = PerfSystemSample(cpuPct: 23, memoryPressure: .normal, thermalState: "nominal", lowPowerMode: false, freeDiskBytes: 100 << 30)
        s.tabs = PerfTabCounts(tabs: 40, live: 6, visible: 1, slept: 3, incognito: 0, windows: 1)
        return s
    }

    static func sampleReport() -> PerfReport {
        sampleState().report(generatedAt: start.addingTimeInterval(600), session: session(),
                             selfCost: PerfSelfCost(cpuMs: 120, cpuPct: 0.02, observerCallbacks: 50000, observerMs: 4,
                                                    bytesWritten: 70000, writes: 2, memoryBytes: 9000),
                             storage: .init(profileBytes: 500 << 20, cacheBytes: 200 << 20))
    }

    @Test func stallsAreCountedByKindAndHeldMenusAreNotFreezes() {
        let r = Self.sampleReport()
        let m = r.mainThread
        #expect(m.stalls == 2)
        #expect(m.longStalls == 1)
        #expect(m.hangs == 0)
        #expect(m.outsideFreezes == 1)
        #expect(m.longestMs == 1200)
        #expect(m.recent.count == 3)
        #expect(m.recent[1].marks == ["swipe-begin", "page-shown"])
        #expect(m.recent[1].site == "video.example.com")
        #expect(m.passes.count == 6)
        #expect(r.events.map(\.kind) == ["freeze", "renderer", "load"])
        #expect(r.events[0].detail == "after page-shown")
        #expect(r.startup == ["main": 12, "cefStarted": 480])
        #expect(r.counters["sleepRefusal"] == ["typed": 1])
        #expect(r.timings["longTask"]?.count == 3)
        #expect(r.tabs.longTasks == 3 && r.tabs.longTaskMs == 420)
        #expect(r.storage.freeDiskBytes == 100 << 30)
        #expect(r.sites == ["video.example.com"])
    }

    @Test func aHangCountsAsAllThreeAndIsAnEvent() {
        var s = PerfState()
        #expect(s.pass(ms: 100, endedAt: 1, mode: "kCFRunLoopDefaultMode") == nil)
        let hang = s.pass(ms: 2500, endedAt: 3, mode: "kCFRunLoopDefaultMode")
        #expect(hang?.kind == .hang)
        #expect(s.stallCount == 1 && s.longStallCount == 1 && s.hangCount == 1)
        #expect(s.events.elements.map(\.kind) == ["hang"])
        s.count(.rendererUnresponsive, key: "", at: 4)
        s.count(.rendererResponsive, key: "", at: 5)
        s.count(.tabSlept, key: "idle", at: 6)
        #expect(s.events.elements.map(\.detail) == ["", "unresponsive", "responsive again"])
        s.pageLongTasks(count: 0, totalMs: 0, durations: [])
        #expect(s.longTasks == 0)
    }

    @Test func historySamplesCountWhatHappenedSinceTheLastOne() {
        var s = Self.sampleState()
        let first = s.historySample()
        #expect(first.stalls == 2 && first.longStalls == 1 && first.longTasks == 3 && first.rendererCrashes == 1)
        #expect(first.liveTabs == 6)
        #expect(abs(first.cpuPct - 16.75) < 1e-9)
        #expect(first.footprintBytes == 1200 << 20)
        s.pass(ms: 260, endedAt: 400, mode: "kCFRunLoopDefaultMode")
        let second = s.historySample()
        #expect(second.stalls == 1 && second.longStalls == 0 && second.rendererCrashes == 0)
    }

    @Test func memoryStaysSmallWhateverHappens() {
        var s = PerfState()
        for i in 0..<100_000 {
            s.mark("mark \(i)", at: Double(i))
            s.pass(ms: 300, endedAt: Double(i), mode: "kCFRunLoopDefaultMode")
            s.count(.loadError, key: "-\(i % 50)", at: Double(i))
        }
        #expect(s.marks.count == 64 && s.stalls.count == 40 && s.events.count == 150)
        #expect(s.estimatedBytes < 100_000)
    }

    @Test func aHangFileRoundTrips() throws {
        let h = PerfHang(session: "0123abcd", number: 1, at: 12.5, stalledMs: 2100, mode: "default", marks: ["page-shown"],
                         site: "example.com", stack: ["10 main [Cra]"])
        #expect(try PerfReport.decoder.decode(PerfHang.self, from: PerfReport.encoder().encode(h)) == h)
    }

    /// The schema as it ships: a change that moves or renames a field shows up here. Re-record with
    /// CRA_RECORD_GOLDEN=1 swift test --package-path Packages/CraCore, then say why in the PR.
    @Test func reportMatchesTheGoldenFile() throws {
        let json = String(decoding: try PerfReport.encoder().encode(Self.sampleReport()), as: UTF8.self) + "\n"
        if ProcessInfo.processInfo.environment["CRA_RECORD_GOLDEN"] == "1" {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Perf/perf-golden.json")
            try json.write(to: source, atomically: true, encoding: .utf8)
        }
        let url = try #require(Bundle.module.url(forResource: "perf-golden", withExtension: "json", subdirectory: "Fixtures/Perf"))
        let golden = try String(contentsOf: url, encoding: .utf8)
        #expect(json == golden)
        let decoded = try PerfReport.decoder.decode(PerfReport.self, from: Data(golden.utf8))
        #expect(decoded == Self.sampleReport())
    }
}

struct PerfInsightTests {
    func report(_ change: (inout PerfReport) -> Void) -> PerfReport {
        var r = PerfState().report(generatedAt: PerfStateTests.start, session: PerfStateTests.session(), selfCost: PerfSelfCost())
        change(&r)
        r.insights = PerfInsights.evaluate(r)
        return r
    }

    @Test func aQuietSessionSaysNothing() {
        #expect(report { _ in }.insights.isEmpty)
    }

    @Test func eachRuleFires() {
        let r = report {
            $0.session.previous = PerfPreviousSession(id: "x", launch: 1, startedAt: PerfStateTests.start, craVersion: "0.1.26",
                                                      abnormal: true, endedAt: nil)
            $0.mainThread.longStalls = 2
            $0.mainThread.hangs = 1
            $0.mainThread.longestMs = 2600
            $0.mainThread.stalls = 40
            $0.counters = ["rendererTerminated": ["crashed": 1], "rendererUnresponsive": ["": 2]]
            $0.system = PerfSystemSample(cpuPct: 90, memoryPressure: .critical, thermalState: "serious", lowPowerMode: true,
                                         freeDiskBytes: 1 << 30)
            $0.processes = [PerfProcessGroup(kind: .renderer, count: 30, footprintBytes: 9 << 30)]
            $0.tabs.latest = PerfTabCounts(tabs: 100, live: 30, visible: 1, slept: 0, incognito: 0, windows: 2)
        }
        #expect(r.insights.map(\.id) == ["previous-abnormal", "freezes", "stalls", "renderer-crashes", "unresponsive",
                                         "memory-pressure", "thermal", "low-power", "low-disk", "footprint"])
        #expect(r.insights[1].title == "Cra froze 2 times for a second or more")
        #expect(r.insights[1].detail == "The longest lasted 2.6 s; 1 went past 2 s.")
        #expect(r.insights[3].title == "1 page stopped (“Aw, Snap!”)")
        #expect(r.insights[8].detail.hasPrefix("1.0 GB free"))
        #expect(r.insights[9].title == "Cra uses 9.0 GB of memory")
        #expect(r.insights[9].detail.contains("4 hours"))
    }

    @Test func aFewStallsInALongSessionAreNotFrequent() {
        #expect(report { $0.mainThread.stalls = 5; $0.session.uptimeSeconds = 3600 }.insights.isEmpty)
        #expect(report { $0.mainThread.stalls = 5; $0.session.uptimeSeconds = 300 }.insights.map(\.id) == ["stalls"])
    }

    @Test func formatting() {
        #expect(PerfInsights.duration(250.4) == "250 ms")
        #expect(PerfInsights.duration(1500) == "1.5 s")
        #expect(PerfInsights.bytes(300 << 20) == "300 MB")
        #expect(PerfSystemSample.pressure(level: 2) == .warning)
        #expect(PerfSystemSample.pressure(level: 1) == .normal)
        #expect(PerfSystemSample.pressure(level: 4) == .critical)
        #expect(PerfSystemSample.pressure(level: nil) == .unknown)
    }

    @Test func theSummaryNeverNamesASite() {
        var r = PerfStateTests.sampleReport()
        r.session.previous = PerfPreviousSession(id: "x", launch: 1, startedAt: PerfStateTests.start, craVersion: "0.1.26",
                                                 abnormal: true, endedAt: nil)
        r.insights = PerfInsights.evaluate(r)
        let text = PerfSummary.text(r)
        #expect(!text.contains("example.com"))
        #expect(text.contains("Main thread: 2 stalls ≥250 ms, 1 ≥1 s, 0 ≥2 s, longest 1.2 s"))
        #expect(text.contains("renderer ×3: 12.2 % CPU, 900 MB"))
        #expect(text.contains("Previous session: ended without quitting (Cra 0.1.26)"))
        #expect(text.contains("Tabs: 40, 6 loaded, 3 asleep, 1 window"))
        #expect(text.contains("tab switch: median 8 ms, p95 40 ms (2)"))
        #expect(text.contains("loadError: -105 ×1"))
        #expect(text.contains("• The last session ended without quitting"))
    }
}
