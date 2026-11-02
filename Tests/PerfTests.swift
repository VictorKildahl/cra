import Foundation

/// GitHub #91: the performance recorder on a real main run loop, with its files in a temporary
/// folder. Stalls are made the way Cra makes them (work blocking the main queue), and the hang
/// file's stack comes from the real /usr/bin/sample.
@main
enum PerfTests {
    private static var checks = 0
    private static let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-perf-tests-\(getpid())")

    @MainActor
    static func main() {
        defer { try? FileManager.default.removeItem(at: root) }
        stallsAreRecordedWithTheirBreadcrumbs()
        aHangIsWrittenWhileItLastsWithItsStack()
        aSessionThatNeverQuitIsAbnormalNextLaunch()
        aSecondCraWritesNothing()
        recordingOffStopsSamplingAndWriting()
        theFacadeWaitsForTheRecorderAndTimesWork()
        aSlowLaunchIsAStallButNotAFreeze()
        print("Perf recorder: \(checks) checks passed")
    }

    static func config(_ name: String, hangMs: Double = 2000, stacks: Int = 0) -> PerfRecorder.Config {
        var c = PerfRecorder.Config(folder: root.appendingPathComponent(name))
        c.sampleInterval = 0.2
        c.blackBoxEvery = 2
        c.historyEvery = 3
        c.policy.hangMs = hangMs
        c.stacks = stacks
        return c
    }

    @MainActor static func start(_ c: PerfRecorder.Config, owner: Bool = true, recording: Bool = true) {
        PerfRecorder.configure(owner: owner, recording: recording, config: c, craVersion: "test", chromiumVersion: "0", onboarding: false)
    }

    /// Runs the main run loop, as Cra's does, for `seconds`.
    static func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    @MainActor static func report() -> PerfReport? {
        var out: PerfReport?
        PerfRecorder.shared?.snapshot { out = $0 }
        for _ in 0..<50 where out == nil { spin(0.05) }
        return out
    }

    @inline(never) static func busyMainThreadForPerfTest(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        var x = 0.0
        while Date() < end { x += sin(x) + 1 }
        if x < 0 { print(x) }
    }

    @MainActor static func stallsAreRecordedWithTheirBreadcrumbs() {
        let c = config("stall")
        start(c)
        spin(0.3)
        DispatchQueue.main.async {
            Perf.mark("cra://debug?stall=500")
            usleep(500_000)
        }
        spin(0.5)
        DispatchQueue.main.async { usleep(300_000) }
        spin(1.2)
        guard let r = report() else { return expect(false, "a report while recording") }
        expect(r.mainThread.stalls == 2, "both stalls counted (\(r.mainThread.stalls))")
        expect(r.mainThread.recent.allSatisfy { $0.mode != "launch" }, "a quick start is no stall")
        let first = r.mainThread.recent.first
        expect(first.map { $0.ms >= 500 && $0.ms < 900 } == true, "the injected 500 ms stall measured as such (\(first?.ms ?? 0))")
        expect(first?.marks == ["cra://debug"], "with its breadcrumb, cut before the query (\(first?.marks ?? []))")
        expect(first?.mode == "default" && first?.freeze == true, "in the default mode: a freeze")
        expect(r.mainThread.passes.count > 2 && r.mainThread.passes.maxMs >= 500, "every pass in the histogram")
        expect(r.processes.contains { $0.kind == .browser && $0.count == 1 && $0.footprintBytes > 0 }, "libproc read this process")
        expect(r.system?.memoryPressure != nil && r.system?.thermalState.isEmpty == false, "the Mac sampled")
        expect(r.selfCost.cpuPct < 5 && r.selfCost.observerCallbacks > 0, "self-cost reported (\(r.selfCost.cpuPct) %)")
        expect(r.session.launch == 1 && r.session.previous == nil && r.session.writesFiles, "a first launch, writing")
        let files = PerfFiles(folder: c.folder)
        expect(FileManager.default.fileExists(atPath: files.marker.path), "session.open while running")
        expect(files.read(PerfReport.self, from: files.blackBox) != nil, "the black box written on its schedule")

        var exported: [(name: String, text: String)] = []
        var sites: Set<String> = ["unset"]
        PerfRecorder.exportFiles { exported = $0; sites = $1 }
        for _ in 0..<100 where exported.isEmpty { spin(0.05) }
        expect(exported.first?.name == "perf.json" && exported.first!.text.contains("\"stalls\" : 2"), "perf.json in the export")
        expect(sites.isEmpty, "no sites: no page was on screen")

        PerfRecorder.quit()
        expect(!FileManager.default.fileExists(atPath: files.marker.path), "a clean quit removes the marker")
        let history = files.read(PerfHistory.self, from: files.history)
        expect(history?.lastSession?.abnormal == false && history?.launches == 1, "and records the session as quit")
        expect(!Perf.isRecording, "the facade lets go")

        start(c)
        expect(PerfRecorder.shared.map { _ in report()?.session.previous?.abnormal == false } == true, "the next launch: previous quit normally")
        expect(report()?.session.launch == 2, "launch 2")
        expect(FileManager.default.fileExists(atPath: files.previousBlackBox.path), "the last black box kept as the previous one")
        PerfRecorder.quit()
    }

    @MainActor static func aHangIsWrittenWhileItLastsWithItsStack() {
        let c = config("hang", hangMs: 600, stacks: 1)
        start(c)
        spin(0.3)
        let files = PerfFiles(folder: c.folder)
        var seenDuring = false
        // The watchdog writes from its own thread while the main thread is still busy; the block
        // outlasts the 1 s sample that starts at 0.6 s (sample takes a moment to attach).
        DispatchQueue.main.async {
            busyMainThreadForPerfTest(2.6)
            seenDuring = !files.hangFiles().isEmpty
        }
        // `sample` takes about 2 s here and longer on a CI runner: wait for the stack, not a time.
        var hang: PerfHang?
        for _ in 0..<100 {
            spin(0.2)
            hang = files.hangFiles().first.flatMap { files.read(PerfHang.self, from: $0) }
            if hang?.stackNote != "sampling", hang?.endedMs != nil { break }
        }
        expect(seenDuring, "the hang file exists before the main thread comes back")
        expect(hang?.stalledMs ?? 0 >= 600, "it says how long the main thread had been blocked")
        expect(hang.map { $0.endedMs ?? 0 >= 2500 } == true, "and how long it was in the end (\(hang?.endedMs ?? -1))")
        expect(hang?.stack.contains { $0.contains("busyMainThreadForPerfTest") } == true,
               "with the main thread's stack from sample (\(hang?.stackNote ?? "")): \(hang?.stack.prefix(6) ?? [])")
        expect(hang?.stack.contains { $0.contains("/Users") || $0.contains("0x") } == false, "no paths or addresses")
        let r = report()
        expect(r?.mainThread.hangs == 1 && r?.events.first?.kind == "hang", "counted as a hang")
        PerfRecorder.quit()
    }

    @MainActor static func aSessionThatNeverQuitIsAbnormalNextLaunch() {
        let c = config("abnormal")
        start(c)
        spin(0.5)
        let files = PerfFiles(folder: c.folder)
        let id = PerfRecorder.shared?.sessionID
        // What kill -9 leaves: the marker, the black box, a hang file. Nothing gets to quit().
        let marker = files.read(PerfSessionMarker.self, from: files.marker)
        expect(marker?.id == id, "the marker names the session")
        PerfRecorder.setRecording(false)
        files.write(marker!, to: files.marker)
        files.write(PerfHang(session: id!, number: 1, at: 1, stalledMs: 3000, mode: "default", marks: [], site: nil), to: files.hang(session: id!, number: 1))
        files.write(PerfHang(session: "older000", number: 1, at: 1, stalledMs: 3000, mode: "default", marks: [], site: nil), to: files.hang(session: "older000", number: 1))

        start(c)
        let previous = report()?.session.previous
        expect(previous?.abnormal == true && previous?.id == id, "the next launch reports it as ended without quitting")
        expect(report()?.insights.first?.id == "previous-abnormal", "and says so first")
        expect(files.hangFiles().map(\.lastPathComponent) == ["hang-\(id!)-1.json"], "its hang file stays, older ones go")
        PerfRecorder.quit()
    }

    @MainActor static func aSecondCraWritesNothing() {
        let c = config("second")
        start(c, owner: false)
        spin(0.8)
        expect(PerfRecorder.shared?.writesFiles == false, "a Cra that doesn't own the data folder records in memory only")
        expect(!FileManager.default.fileExists(atPath: c.folder.path), "and makes no folder, no marker, no files")
        PerfRecorder.quit()
        expect(!FileManager.default.fileExists(atPath: c.folder.path), "not even when it quits")
    }

    @MainActor static func recordingOffStopsSamplingAndWriting() {
        let c = config("off")
        start(c, recording: false)
        spin(0.5)
        expect(PerfRecorder.shared == nil && !Perf.isRecording, "off at launch: no recorder")
        expect(!FileManager.default.fileExists(atPath: c.folder.path), "and nothing written")

        PerfRecorder.setRecording(true)
        spin(0.6)
        let files = PerfFiles(folder: c.folder)
        expect(FileManager.default.fileExists(atPath: files.marker.path), "turned on: a session starts")
        PerfRecorder.setRecording(false)
        expect(!FileManager.default.fileExists(atPath: files.marker.path), "turned off: its marker goes")
        let before = snapshot(c.folder)
        spin(1)
        expect(snapshot(c.folder) == before, "and nothing is written after (\(before.count) files)")
        DispatchQueue.main.async { usleep(300_000) }
        spin(0.5)
        expect(PerfRecorder.shared == nil, "stalls with recording off reach nobody")

        PerfRecorder.clear()
        expect(PerfFiles(folder: c.folder).hangFiles().isEmpty && !FileManager.default.fileExists(atPath: files.history.path),
               "Clear removes the files while off")
    }

    @MainActor static func theFacadeWaitsForTheRecorderAndTimesWork() {
        let c = config("facade")
        start(c)
        Perf.time(.jsonSave, ms: 12)
        let n = Perf.time(.jsonLoad) { 41 + 1 }
        Perf.begin(.pageLoad, "tab")
        usleep(20_000)
        Perf.end(.pageLoad, "tab")
        Perf.begin(.tabWake, "gone")
        Perf.cancel(.tabWake, "gone")
        Perf.end(.tabWake, "gone")
        Perf.count(.loadError, "-105", site: "example.com")
        Perf.phase("test")
        let r = report()
        expect(n == 42, "a timed closure returns its value")
        expect(r?.timings["jsonSave"]?.count == 1 && r?.timings["jsonLoad"]?.count == 1, "durations recorded")
        expect(r.map { ($0.timings["pageLoad"]?.maxMs ?? 0) >= 20 } == true, "begin and end make one duration")
        expect(r?.timings["tabWake"] == nil, "a cancelled begin makes none")
        expect(r?.counters["loadError"] == ["-105": 1] && r?.events.last?.site == "example.com", "a failed load counted, with its site")
        expect(r?.sites == ["example.com"], "the report lists the sites it names, for Hide site names")
        expect(r?.startup["test"] != nil, "start-up phases")
        PerfRecorder.quit()
    }

    /// AppKit runs applicationDidFinishLaunching before the run loop's first pass: the recorder
    /// counts from its own start until the loop first sleeps.
    @MainActor static func aSlowLaunchIsAStallButNotAFreeze() {
        start(config("launch"))
        usleep(400_000)
        spin(0.5)
        let r = report()
        expect(r?.mainThread.recent.first?.mode == "launch" && r?.mainThread.recent.first?.freeze == false,
               "a slow start-up is a stall in the launch mode (\(r?.mainThread.recent.first?.mode ?? "none"))")
        expect(r?.mainThread.stalls == 0 && r?.mainThread.outsideFreezes == 1
               && r?.insights.contains { $0.id == "freezes" || $0.id == "stalls" } == false,
               "not a freeze, no freeze finding (\(r?.mainThread.stalls ?? -1), \(r?.mainThread.outsideFreezes ?? -1), \(r?.insights.map(\.id) ?? []))")
        PerfRecorder.quit()
    }

    static func snapshot(_ folder: URL) -> [String: Date] {
        var out: [String: Date] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            out[f.lastPathComponent] = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return out
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
