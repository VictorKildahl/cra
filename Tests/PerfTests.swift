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
        availableFilesystemCapacityIsSampled()
        stallsAreRecordedWithTheirBreadcrumbs()
        aHangIsWrittenWhileItLastsWithItsStack()
        aSessionThatNeverQuitIsAbnormalNextLaunch()
        aSecondCraWritesNothing()
        recordingOffStopsSamplingAndWriting()
        theFacadeWaitsForTheRecorderAndTimesWork()
        aSlowLaunchIsAStallButNotAFreeze()
        workAcrossATimerBoundaryIsOnePass()
        theFirstSlowPassGetsAStack()
        theObserversCostIsCPUNotWaiting()
        print("Perf recorder: \(checks) checks passed")
    }

    static func config(_ name: String, hangMs: Double = 2000, slowMs: Double = 1000, stacks: Int = 0) -> PerfRecorder.Config {
        var c = PerfRecorder.Config(folder: root.appendingPathComponent(name))
        c.sampleInterval = 0.2
        c.blackBoxEvery = 2
        c.historyEvery = 3
        c.policy.hangMs = hangMs
        c.policy.slowStackMs = slowMs
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

    /// Busy on the main thread until `done` (checked every 50 ms) or `limit` seconds.
    @inline(never) static func busyMainThreadForPerfTest(atLeast seconds: Double, limit: Double, until done: () -> Bool) {
        let start = Date()
        var x = 0.0, next = start
        while Date().timeIntervalSince(start) < limit {
            x += sin(x) + 1
            if Date() >= next {
                if Date().timeIntervalSince(start) >= seconds, done() { break }
                next = Date().addingTimeInterval(0.05)
            }
        }
        if x < 0 { print(x) }
    }

    static func availableFilesystemCapacityIsSampled() {
        let folder = FileManager.default.temporaryDirectory
        var sampler = PerfSystemSampler()
        expect((sampler.read(dataFolder: folder).freeDiskBytes ?? -1) > 0, "available filesystem blocks sampled")
        expect(PerfSystemSampler.availableDisk(root.appendingPathComponent("absent-volume-path")) == nil,
               "missing filesystem path has unknown capacity")
    }

    // promise: #91
    @MainActor static func stallsAreRecordedWithTheirBreadcrumbs() {
        let c = config("stall")
        start(c)
        spin(0.3)
        var stallEnded = Date.distantPast
        DispatchQueue.main.async {
            Perf.mark("cra://debug?stall=500")
            usleep(500_000)
            stallEnded = Date()
        }
        spin(0.5)
        DispatchQueue.main.async { usleep(300_000) }
        spin(1.2)
        guard let r = report() else { return expect(false, "a report while recording") }
        expect(r.mainThread.freezes == 2, "both stalls counted (\(r.mainThread.freezes))")
        expect(r.mainThread.longestPassMs >= 500 && r.mainThread.longestPassMode == "default", "the longest pass (\(r.mainThread.longestPassMs))")
        expect(r.mainThread.recent.allSatisfy { $0.mode != "launch" }, "a quick start is no stall")
        let first = r.mainThread.recent.first
        expect(first.map { $0.ms >= 500 && $0.ms < 900 } == true, "the injected 500 ms stall measured as such (\(first?.ms ?? 0))")
        expect(first?.marks == ["cra://debug"], "with its breadcrumb, cut before the query (\(first?.marks ?? []))")
        expect(first?.mode == "default" && first?.freeze == true, "in the default mode: a freeze")
        // Read back from the file, which keeps dates to the second.
        let file = (try? PerfReport.encoder().encode(r)).flatMap { try? PerfReport.decoder.decode(PerfReport.self, from: $0) }
        let drift = file.flatMap { f in f.mainThread.recent.first.map { f.session.startedAt.addingTimeInterval($0.at).timeIntervalSince(stallEnded) } } ?? 99
        expect(abs(drift) < 0.1, "startedAt + at in perf.json is the wall time the stall ended (off by \(drift) s)")
        expect(r.session.uptimeSeconds >= 2 && r.session.uptimeSeconds < 60 && r.session.asleepSeconds < 1,
               "uptime from Cra's start on the same clock (\(r.session.uptimeSeconds) s)")
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
        expect(exported.first?.name == "perf.json" && exported.first!.text.contains("\"freezes\" : 2"), "perf.json in the export")
        expect(exported.contains { $0.name == "perf/history.json" }, "with the 24-hour history")
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

    // promise: #91
    @MainActor static func aHangIsWrittenWhileItLastsWithItsStack() {
        let c = config("hang", hangMs: 600, stacks: 1)
        start(c)
        spin(0.3)
        let files = PerfFiles(folder: c.folder)
        var seenDuring = false
        // The watchdog writes from its own thread while the main thread is still busy. The block
        // lasts until the stack is in the file, however long `sample` takes to attach (a CI runner
        // is slower than a desk Mac).
        DispatchQueue.main.async {
            busyMainThreadForPerfTest(atLeast: 1, limit: 15) {
                files.hangFiles().first.flatMap { files.read(PerfHang.self, from: $0) }.map { $0.stackNote != "sampling" } ?? false
            }
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
        expect(hang.map { $0.endedMs ?? 0 >= 1000 } == true, "and how long it was in the end (\(hang?.endedMs ?? -1))")
        expect(hang?.stack.contains { $0.contains("busyMainThreadForPerfTest") } == true,
               "with the main thread's stack from sample (\(hang?.stackNote ?? "")): \(hang?.stack.prefix(6) ?? [])")
        expect(hang?.stack.contains { $0.contains("/Users") || $0.contains("0x") } == false, "no paths or addresses")
        let r = report()
        expect(r?.mainThread.hangs == 1 && r?.events.first?.kind == "hang", "counted as a hang")
        PerfRecorder.quit()
    }

    // promise: #91
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
        files.write(PerfHang(session: id!, number: 2, at: 1, stalledMs: 3000, mode: "default", marks: [], site: "old.example.com"),
                    to: files.hang(session: id!, number: 2))

        start(c)
        let previous = report()?.session.previous
        expect(previous?.abnormal == true && previous?.id == id, "the next launch reports it as ended without quitting")
        expect(report()?.insights.first?.id == "previous-abnormal", "and says so first")
        expect(files.hangFiles().map(\.lastPathComponent) == ["hang-\(id!)-1.json", "hang-\(id!)-2.json"], "its hang files stay, older ones go")
        var sites: Set<String> = []
        var exported = false
        PerfRecorder.exportFiles { _, s in sites = s; exported = true }
        for _ in 0..<100 where !exported { spin(0.05) }
        expect(sites.contains("old.example.com"), "the last session's sites are hidden with this one's (\(sites))")
        PerfRecorder.quit()
    }

    // promise: #91
    @MainActor static func aSecondCraWritesNothing() {
        let c = config("second")
        start(c, owner: false)
        spin(0.8)
        expect(PerfRecorder.shared?.writesFiles == false, "a Cra that doesn't own the data folder records in memory only")
        expect(!FileManager.default.fileExists(atPath: c.folder.path), "and makes no folder, no marker, no files")
        PerfRecorder.quit()
        expect(!FileManager.default.fileExists(atPath: c.folder.path), "not even when it quits")
    }

    // promise: #91
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
        expect(r?.mainThread.freezes == 0 && r?.mainThread.outsideFreezes == 1
               && r?.insights.contains { $0.id == "freezes" || $0.id == "stalls" } == false,
               "not a freeze, no freeze finding (\(r?.mainThread.freezes ?? -1), \(r?.mainThread.outsideFreezes ?? -1), \(r?.insights.map(\.id) ?? []))")
        expect(r?.mainThread.longestPassMs ?? 0 >= 400 && r?.mainThread.longestPassMode == "launch"
               && r?.insights.contains { $0.id == "outside-freezes" } == true,
               "but the longest pass, and a finding that says it was not counted (\(r?.mainThread.longestPassMs ?? -1))")
        PerfRecorder.quit()
    }

    // promise: #135
    /// GitHub #135: a timer and a queued block that run in one turn of the loop, with no sleep
    /// or commit between them, are one 300 ms pass. Split at before-timers they were two 150 ms
    /// halves and no stall at all. The timer queues the block: queued side by side, the block could
    /// run first and the loop sleep before a late timer (a slow CI runner), two passes after all.
    @MainActor static func workAcrossATimerBoundaryIsOnePass() {
        start(config("one-pass"))
        spin(0.5)
        let before = report()?.mainThread.passes.count ?? 0
        Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
            usleep(150_000)
            DispatchQueue.main.async { usleep(150_000) }
        }
        spin(0.6)
        let r = report()
        let stalls = r?.mainThread.recent ?? []
        expect(stalls.count == 1 && stalls[0].ms >= 300 && stalls[0].ms < 600 && r?.mainThread.freezes == 1,
               "one stall of 300 ms (\(stalls.map(\.ms)))")
        // A quiet loop sleeps between the 5 Hz samples and reports: a few passes a second, not hundreds.
        let after = r?.mainThread.passes.count ?? 0
        expect(after - before < 60, "one pass per wake, not one per observer callback (\(after - before) in 0.6 s)")
        expect(r.map { $0.selfCost.observerCallbacks < 4 * $0.mainThread.passes.count + 20 } == true,
               "two or three callbacks a pass (\(r?.selfCost.observerCallbacks ?? -1) for \(r?.mainThread.passes.count ?? -1))")
        PerfRecorder.quit()
    }

    // promise: #135
    /// GitHub #135: the first pass that lasts `slowStackMs` gets one `sample`, in memory, while the
    /// watchdog goes on watching; the report says how long the pass was in the end.
    @MainActor static func theFirstSlowPassGetsAStack() {
        start(config("slow", hangMs: 30_000, slowMs: 400, stacks: 1))
        spin(0.3)
        DispatchQueue.main.async {
            Perf.mark("slow-test")
            busyMainThreadForPerfTest(atLeast: 0.8, limit: 15) { PerfRecorder.shared?.slowPass.map { $0.stackNote != "sampling" } ?? false }
        }
        spin(0.5)
        let slow = report()?.mainThread.slowPass
        expect(slow?.stack.contains { $0.contains("busyMainThreadForPerfTest") } == true,
               "with the main thread's stack (\(slow?.stackNote ?? "no slow pass")): \(slow?.stack.prefix(6) ?? [])")
        expect(slow.map { $0.stalledMs >= 400 && ($0.endedMs ?? 0) >= 800 && $0.marks == ["slow-test"] && $0.number == 0 } == true,
               "how long it was when sampled and in the end, after what (\(slow?.stalledMs ?? -1), \(slow?.endedMs ?? -1))")
        expect(FileManager.default.fileExists(atPath: PerfFiles(folder: config("slow").folder).hangFiles().first?.path ?? "/nonexistent") == false,
               "no hang file below the hang threshold")
        PerfRecorder.quit()
    }

    static func snapshot(_ folder: URL) -> [String: Date] {
        var out: [String: Date] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            out[f.lastPathComponent] = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return out
    }

    /// The observer's self-cost counts the CPU its stall reports use, not time the main thread
    /// spent waiting in one, and never multiplies a report out as if every callback made one.
    /// Before, one callback in 256 was timed by the wall clock and multiplied by 256, a stall
    /// report included. Here each stall report waits 2 ms off the CPU.
    @MainActor static func theObserversCostIsCPUNotWaiting() {
        let observer = MainLoopObserver(stallMs: 0, slowMs: 60_000, hangMs: 60_000,
                                        onStall: { _, _, _ in usleep(2_000) }, onSlow: { _, _, _ in }, onHang: { _, _, _ in }, onWatch: {})
        observer.start()
        // One extra turn, so callbacks that end a pass (and report the stall) fall on the old
        // one-in-256 timing too.
        RunLoop.main.run(mode: .default, before: Date())
        // A turn every 5 ms, longer than the 2 ms wait, so the loop sleeps between turns: each
        // turn is a pass of two callbacks however slow the build (sanitizers) or the Mac.
        var turns = 0
        let timer = Timer(timeInterval: 0.005, repeats: true) { _ in turns += 1 }
        RunLoop.main.add(timer, forMode: .common)
        let limit = Date().addingTimeInterval(60)
        while turns < 400, Date() < limit { spin(0.1) }
        timer.invalidate()
        observer.stop()
        let d = observer.drain()
        let perCallback = Double(d.observerNs) / Double(max(d.callbacks, 1))
        expect(d.callbacks >= 512, "the loop turned often enough to time some callbacks (\(d.callbacks))")
        expect(perCallback < 100_000, "a callback costs its CPU, not the 2 ms it waited (\(Int(perCallback)) ns each)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
