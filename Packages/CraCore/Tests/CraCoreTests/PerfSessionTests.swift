import CraCore
import Foundation
import Testing

/// GitHub #91: when Cra records, when it writes, and how the session before ended.
struct PerfSessionTests {
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    @Test(arguments: [(true, [:], true), (false, [:], false), (true, ["CRA_PERF": "0"], false), (true, ["CRA_PERF": "1"], true)]
          as [(Bool, [String: String], Bool)])
    func recordingFollowsTheSettingUnlessTheEnvironmentTurnsItOff(setting: Bool, env: [String: String], on: Bool) {
        #expect(PerfSessionRules.recording(setting: setting, environment: env) == on)
    }

    @Test func onlyTheOwnerWritesAndOnlyWhileRecording() {
        #expect(PerfSessionRules.writesFiles(owner: true, recording: true))
        #expect(!PerfSessionRules.writesFiles(owner: false, recording: true))
        #expect(!PerfSessionRules.writesFiles(owner: true, recording: false))
    }

    @Test func aMarkerLeftBehindIsAnAbnormalEnd() {
        let marker = PerfSessionMarker(id: "abc", launch: 3, startedAt: start, pid: 42, craVersion: "0.1.26")
        var history = PerfHistory()
        history.lastSession = PerfPreviousSession(id: "old", launch: 2, startedAt: start, craVersion: "0.1.25", abnormal: false, endedAt: start)
        let p = PerfSessionRules.previous(marker: marker, history: history)
        #expect(p == PerfPreviousSession(id: "abc", launch: 3, startedAt: start, craVersion: "0.1.26", abnormal: true, endedAt: nil))
        #expect(PerfSessionRules.previous(marker: nil, history: history)?.abnormal == false)
        #expect(PerfSessionRules.previous(marker: nil, history: PerfHistory()) == nil)
    }

    @Test func historyKeepsFiveMinuteBuckets() {
        var h = PerfHistory()
        h.record(PerfHistorySample(cpuPct: 10, footprintBytes: 100 << 20, stalls: 1, liveTabs: 3), at: start)
        h.record(PerfHistorySample(cpuPct: 20, footprintBytes: 300 << 20, stalls: 2, longStalls: 1, longTasks: 4, rendererCrashes: 1, liveTabs: 2),
                 at: start.addingTimeInterval(60))
        #expect(h.buckets.count == 1)
        let b = h.buckets.elements[0]
        #expect(b.samples == 2)
        #expect(b.cpuPct == 15)
        #expect(b.footprintMB == 300)
        #expect(b.stalls == 3 && b.longStalls == 1 && b.longTasks == 4 && b.rendererCrashes == 1)
        #expect(b.liveTabs == 3)
        #expect(b.start.timeIntervalSince1970.truncatingRemainder(dividingBy: 300) == 0)
        h.record(PerfHistorySample(cpuPct: 1, footprintBytes: 0), at: start.addingTimeInterval(400))
        #expect(h.buckets.count == 2)
        // A clock set back starts a new bucket rather than changing an old one.
        h.record(PerfHistorySample(cpuPct: 1, footprintBytes: 0), at: start.addingTimeInterval(-3600))
        #expect(h.buckets.count == 3)
        #expect(h.recent(600, now: start.addingTimeInterval(400)).count == 2)
    }

    @Test func historyHoldsADayAndLoadsWhatOlderFilesLack() throws {
        var h = PerfHistory()
        for i in 0..<(PerfHistory.capacity + 10) {
            h.record(PerfHistorySample(cpuPct: 1, footprintBytes: 0), at: start.addingTimeInterval(Double(i) * 300))
        }
        #expect(h.buckets.count == PerfHistory.capacity)
        h.launches = 4
        let data = try PerfReport.encoder().encode(h)
        #expect(try PerfReport.decoder.decode(PerfHistory.self, from: data) == h)
        let empty = try PerfReport.decoder.decode(PerfHistory.self, from: Data("{}".utf8))
        #expect(empty.launches == 0 && empty.buckets.isEmpty && empty.firstLaunchAt == nil)
    }
}

struct PerfProcessTableTests {
    func reading(_ pid: Int32, _ kind: PerfProcessKind, cpuMs: UInt64?, mb: Int64 = 10) -> PerfProcessReading {
        PerfProcessReading(pid: pid, kind: kind, cpuNs: cpuMs.map { $0 * 1_000_000 }, footprintBytes: mb << 20,
                           diskReadBytes: 1, diskWriteBytes: 2, wakeups: 3)
    }

    @Test(arguments: [("Cra", true, PerfProcessKind.browser), ("Cra Helper (Renderer)", false, .renderer),
                      ("CraX Helper (GPU)", false, .gpu), ("Cra Helper (Plugin)", false, .utility), ("Cra Helper", false, .utility),
                      ("sample", false, .other)])
    func processKindsComeFromTheirNames(name: String, isSelf: Bool, kind: PerfProcessKind) {
        #expect(PerfProcessKind.of(name: name, isSelf: isSelf) == kind)
    }

    @Test(arguments: [("renderer", PerfProcessKind.renderer), ("gpu-process", .gpu), ("utility", .utility), ("zygote", .utility)])
    func chromiumsTypeArgumentWinsOverTheName(type: String, kind: PerfProcessKind) {
        // CEF's GPU process runs from the plain helper app.
        #expect(PerfProcessKind.of(name: "Cra Helper", isSelf: false, type: type) == kind)
        #expect(PerfProcessKind.of(name: "Cra", isSelf: true, type: type) == .browser)
    }

    @Test(arguments: [("Cra", true, "", PerfProcessKind.browser),
                      ("CraDev Helper (Renderer)", false, "renderer", .renderer),
                      ("Cra Helper (GPU)", false, "gpu-process", .gpu),
                      ("Cra Helper", false, "gpu-process", .gpu),
                      ("Cra Helper (Plugin)", false, "utility", .utility),
                      ("sample", false, "", .other)])
    func cheapClassificationPreservesProcessRoles(name: String, isSelf: Bool, type: String, kind: PerfProcessKind) {
        let argument = !isSelf && PerfProcessKind.needsType(name: name) ? type : nil
        #expect(PerfProcessKind.of(name: name, isSelf: isSelf, type: argument) == kind)
    }

    @Test func cpuIsMeasuredOverTheIntervalAndChurnCountsComingAndGoing() throws {
        var t = PerfProcessTable()
        let first = t.update([reading(1, .browser, cpuMs: 1000), reading(2, .renderer, cpuMs: 500), reading(3, .renderer, cpuMs: 0)],
                             atNs: 10_000_000_000)
        #expect(first.first { $0.kind == .browser }?.cpuPct == 0)
        #expect(first.first { $0.kind == .renderer }?.started == 0)
        #expect(first.first { $0.kind == .renderer }?.count == 2)
        #expect(first.first { $0.kind == .gpu } == nil)

        // 5 s later: the browser used 500 ms (10 %), renderer 2 ended, renderer 4 started.
        let second = t.update([reading(1, .browser, cpuMs: 1500), reading(3, .renderer, cpuMs: 250, mb: 30), reading(4, .renderer, cpuMs: nil)],
                              atNs: 15_000_000_000)
        let browser = try #require(second.first { $0.kind == .browser })
        #expect(abs(browser.cpuPct - 10) < 1e-9)
        let renderers = try #require(second.first { $0.kind == .renderer })
        #expect(abs(renderers.cpuPct - 5) < 1e-9)
        #expect(renderers.started == 1 && renderers.ended == 1)
        #expect(renderers.footprintBytes == 40 << 20)
        #expect(renderers.wakeups == 6)
        #expect(renderers.available)

        // Every renderer gone: the group stays for its churn.
        let third = t.update([reading(1, .browser, cpuMs: 1500)], atNs: 20_000_000_000)
        let gone = try #require(third.first { $0.kind == .renderer })
        #expect(gone.count == 0 && gone.ended == 3 && gone.available)
    }

    @Test func aGroupMacOSRefusedEntirelyIsUnavailable() throws {
        var t = PerfProcessTable()
        let g = t.update([reading(9, .gpu, cpuMs: nil)], atNs: 1)
        #expect(try #require(g.first { $0.kind == .gpu }).available == false)
    }
}

struct PerfSampleStackTests {
    static let sample = """
    Analysis of sampling Cra (pid 12876) every 10 milliseconds
    Path:            /Users/someone/Applications/Cra.app/Contents/MacOS/Cra
    ----

    Call graph:
        100 Thread_7920090   DispatchQueue_1: com.apple.main-thread  (serial)
        + 100 start  (in dyld) + 6992  [0x18aafc4e4]
        +   100 main  (in Cra) + 140  [0x104b68ad4]
        +     90 BrowserManager.show(_:focused:focus:)  (in Cra) + 156  [0x104b6903c]
        +     ! 88 -[CraBrowser initWithFrame:]  (in Cra) + 56  [0x18d0667d4]
        +     ! : 2 objc_msgSend  (in libobjc.A.dylib) + 2  [0x1]
        +     10 SidebarStore.save()  (in Cra) + 148,184  [0x104b69034,0x104b69058]
        100 Thread_7920229
        + 100 thread_start  (in libsystem_pthread.dylib) + 8  [0x18aec2c1c]

    Binary Images:
           0x104b68000 -        0x104b6bfff  Cra (0) <ABC> /Users/someone/Applications/Cra.app/Contents/MacOS/Cra
    """

    @Test func theMainThreadsHeavyFramesWithoutAddressesOrPaths() {
        let lines = PerfSampleStack.mainThread(from: Self.sample)
        #expect(lines == [
            "100 start [dyld]",
            " 100 main [Cra]",
            "  90 BrowserManager.show(_:focused:focus:) [Cra]",
            "   88 -[CraBrowser initWithFrame:] [Cra]",
            "  10 SidebarStore.save() [Cra]",
        ])
        #expect(!lines.joined().contains("/Users"))
        #expect(!lines.joined().contains("0x"))
    }

    @Test func noMainThreadNoLines() {
        #expect(PerfSampleStack.mainThread(from: "sample: failed to examine process").isEmpty)
        #expect(PerfSampleStack.mainThread(from: Self.sample, limit: 2).count == 2)
    }
}
