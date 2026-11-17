import CraCore
import Foundation
import Testing

/// A 0.1.44 report (16 Nov 2026): 14–17 GB and 440–500 % CPU with four tabs while the Mac sat idle,
/// and the history held only Cra's totals, so nothing said which process it was or what it hosted.
struct PerfRunawayTests {
    static let gb: Int64 = 1 << 30
    static let start = Date(timeIntervalSince1970: 1_793_000_000)

    static func usage(_ pid: Int32, _ kind: PerfProcessKind = .renderer, cpu: Double = 0, gb: Double = 0.1) -> PerfProcessUsage {
        PerfProcessUsage(pid: pid, kind: kind, cpuPct: cpu, footprintBytes: Int64(gb * Double(Self.gb)))
    }

    @Test func historyBucketNamesTheProcessThatHeldTheMemoryAndTheOneThatBurnedTheCPU() {
        var s = PerfState()
        s.processSites = [301: ["x.com"], 302: ["www.instagram.com"]]
        var h = PerfHistory()
        // As in the report's 21:10 bucket: one renderer grows while another one spins.
        for (i, x) in [(4.0, 120.0), (14.0, 90.0), (9.0, 30.0)].enumerated() {
            s.processUsage = [Self.usage(1, .browser, cpu: 5, gb: 0.3), Self.usage(2, .gpu, cpu: 20, gb: 0.8),
                              Self.usage(301, cpu: x.1, gb: x.0), Self.usage(302, cpu: 400 - Double(i), gb: 0.6)]
            h.record(s.historySample(), at: Self.start.addingTimeInterval(Double(i) * 5))
        }
        let b = h.buckets.last!
        #expect(b.largest == PerfHistoryProcess(kind: .renderer, footprintMB: 14336, cpuPct: 90, sites: ["x.com"]))
        #expect(b.busiest == PerfHistoryProcess(kind: .renderer, footprintMB: 614, cpuPct: 400, sites: ["www.instagram.com"]))
    }

    @Test func aHistoryFromBeforeKeepsLoadingWithoutTheProcesses() throws {
        let json = #"{"launches":43,"buckets":{"capacity":288,"elements":[{"start":815000000,"samples":60,"cpuPct":441.5,"footprintMB":14038,"stalls":0,"longStalls":0,"longTasks":0,"rendererCrashes":0,"liveTabs":4}]}}"#
        let h = try JSONDecoder().decode(PerfHistory.self, from: Data(json.utf8))
        #expect(h.buckets.last?.footprintMB == 14038)
        #expect(h.buckets.last?.largest == nil)
        let again = try JSONDecoder().decode(PerfHistory.self, from: JSONEncoder().encode(h))
        #expect(again == h)
    }

    @Test func processTableKeepsEachProcessesShare() {
        var t = PerfProcessTable()
        let r = { (pid: Int32, cpuNs: UInt64, gb: Int64) in
            PerfProcessReading(pid: pid, kind: .renderer, cpuNs: cpuNs, footprintBytes: gb * Self.gb, diskReadBytes: 0, diskWriteBytes: 0, wakeups: 0)
        }
        _ = t.update([r(7, 0, 1), r(8, 0, 2)], atNs: 1_000_000_000)
        _ = t.update([r(7, 4_000_000_000, 14), r(8, 500_000_000, 2)], atNs: 2_000_000_000)
        #expect(t.usage == [Self.usage(7, cpu: 400, gb: 14), Self.usage(8, cpu: 50, gb: 2)])
    }

    @Test func aProcessGrowingPastEachDoublingIsNamedOnce() {
        var w = PerfRunawayWatch()
        #expect(w.update([Self.usage(5, gb: 1.5)]).isEmpty)
        #expect(w.update([Self.usage(5, gb: 2.2)]).map(\.reason) == [.memory(gb: 2)])
        #expect(w.update([Self.usage(5, gb: 3.9)]).isEmpty)
        // From 3.9 to 14 GB between two samples: one line, at the level it reached.
        #expect(w.update([Self.usage(5, gb: 14)]).map(\.reason) == [.memory(gb: 8)])
        #expect(w.update([Self.usage(5, gb: 15.9)]).isEmpty)
        #expect(w.update([Self.usage(5, gb: 16.9)]).map(\.reason) == [.memory(gb: 16)])
        // Another process starts from the first level.
        #expect(w.update([Self.usage(5, gb: 16.9), Self.usage(6, gb: 2)]).map(\.usage.pid) == [6])
    }

    @Test func aProcessOverTwoCoresFor30sIsNamedOnceUntilItCalmsDown() {
        var w = PerfRunawayWatch()
        let busy = { (cpu: Double) in w.update([Self.usage(9, cpu: cpu)]) }
        for _ in 1..<PerfRunawayWatch.busySamples { #expect(busy(450).isEmpty) }
        #expect(busy(450).map(\.reason) == [.cpu])
        for _ in 0..<20 { #expect(busy(500).isEmpty) }
        // Below two cores but over one: a pause in the count, not calm.
        #expect(busy(150).isEmpty)
        for _ in 0..<PerfRunawayWatch.busySamples { #expect(busy(450).isEmpty) }
        #expect(busy(20).isEmpty)
        for _ in 1..<PerfRunawayWatch.busySamples { #expect(busy(450).isEmpty) }
        #expect(busy(450).map(\.reason) == [.cpu])
    }

    /// The report's case: a hidden x.com page's process at 14 GB sleeps with the page; a process a
    /// shown page shares doesn't (it would load again at once); CPU alone never sleeps a page.
    @Test func aHiddenPageWhoseProcessRanAwaySleeps() {
        let pages: [(id: String, pids: Set<Int32>, shown: Bool)] = [
            ("outlook", [101], false), ("x.com", [301, 401], false), ("instagram", [302], false), ("x.com front", [303], true),
            ("same-site twin", [304], false), ("shown twin", [304], true),
        ]
        #expect(PerfRunawaySleep.pages(for: 301, among: pages) == ["x.com"])
        // A frame from another site in its own process: the page that embeds it goes.
        #expect(PerfRunawaySleep.pages(for: 401, among: pages) == ["x.com"])
        #expect(PerfRunawaySleep.pages(for: 304, among: pages).isEmpty)
        #expect(PerfRunawaySleep.pages(for: 999, among: pages).isEmpty)

        let at14 = PerfRunaway(usage: Self.usage(301, cpu: 450, gb: 14), reason: .memory(gb: 8))
        #expect(PerfRunawaySleep.applies(at14))
        #expect(!PerfRunawaySleep.applies(PerfRunaway(usage: Self.usage(301, gb: 4.5), reason: .memory(gb: 4))))
        #expect(!PerfRunawaySleep.applies(PerfRunaway(usage: Self.usage(301, cpu: 450, gb: 14), reason: .cpu)))
        #expect(!PerfRunawaySleep.applies(PerfRunaway(usage: Self.usage(2, .gpu, gb: 9), reason: .memory(gb: 8))))
        #expect(PerfRunawaySleep.applies(PerfRunaway(usage: Self.usage(301, gb: 2.2), reason: .memory(gb: 2)), bytes: 2 << 30))
    }

    @Test func aSleptRunawayIsLoggedAndShownInThePerformancePane() {
        var log = TabSleepPolicy.PassLog(reason: .runaway)
        log.closed(host: "x.com", hiddenFor: 11 * 60, discarded: true, processEnded: true)
        #expect(log.lines == ["tab sleep discards x.com (hidden 11 min, its renderer ended, its process ran away)"])

        var s = PerfState()
        s.count(.runawaySlept, key: "14.0 GB", at: 660, site: "x.com")
        s.count(.runawaySlept, key: "8.3 GB", at: 1300, site: "www.instagram.com")
        var r = s.report(generatedAt: Self.start, session: PerfStateTests.session(), selfCost: PerfSelfCost())
        r.insights = PerfInsights.evaluate(r)
        let i = r.insights.first { $0.id == "runaway-slept" }
        #expect(i?.severity == .warning)
        #expect(i?.title == "Cra put 2 tabs to sleep that used too much memory")
        #expect(i?.detail == "x.com, www.instagram.com grew past 8 GB while out of sight (14.0 GB, 8.3 GB). It loads again when you open it."
                + " Exporting diagnostics and sending them helps find out why.")
    }
}
