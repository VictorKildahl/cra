import Foundation

/// Cra's own performance, recorded on this Mac (GitHub #91, docs/performance.md). Data flows one
/// way. The main thread records small facts under one lock (Perf, the run-loop observer); the
/// watchdog thread writes a hang file itself while the main thread is blocked; one serial queue
/// samples processes and the system every 5 s, writes the black box every 60 s and the history
/// every 15 minutes, and builds the export. Nothing on the main thread does file I/O, JSON
/// encoding or libproc calls. Nothing here touches the network (lint: perf-no-network).
final class PerfRecorder: @unchecked Sendable {
    struct Config {
        var sampleInterval: Double = 5
        var blackBoxEvery = 12        // samples: 60 s
        var historyEvery = 180        // samples: 15 min
        var policy = PerfStallPolicy()
        /// `/usr/bin/sample` on Cra at a hang, at most this many times a session (0: never).
        var stacks = 3
        var folder: URL
        var chromiumFolder: URL?
    }

    /// The running recorder; nil while recording is off.
    nonisolated(unsafe) private(set) static var shared: PerfRecorder?
    /// Whether this Cra owns the data folder (only the owner writes), from main.swift.
    nonisolated(unsafe) private static var owner = false
    nonisolated(unsafe) private static var config: Config?
    nonisolated(unsafe) private static var appInfo = (cra: "", chromium: "", onboarding: false)

    /// Called on the main thread every sample: the app counts tabs and reads the visible page's
    /// long tasks (PerfCEF), then reports back through `tabs(_:)` and `pageLongTasks`.
    nonisolated(unsafe) static var mainSampler: (@MainActor (PerfRecorder) -> Void)?

    let config: Config
    let writesFiles: Bool
    let sessionID = String(UUID().uuidString.prefix(8)).lowercased()
    private let files: PerfFiles
    private let queue = DispatchQueue(label: "dk.kildahl.cra.perf", qos: .utility)
    private let lock = NSLock()
    private var state = PerfState()
    private var history = PerfHistory()
    private var session: PerfSessionInfo
    private let startedAt = Date()
    private var observer: MainLoopObserver?
    private var timer: DispatchSourceTimer?
    private var processes = PerfProcessTable()
    private var processSampler = PerfProcessSampler()
    private var system = PerfSystemSampler()
    private var samples = 0
    private var hangs = 0
    private var hangFiles: [UInt64: URL] = [:]
    /// What recording costs, under `lock` (the queue, the watchdog and the main thread add to it).
    private var cost = (cpuNs: UInt64(0), observerNs: UInt64(0), callbacks: 0, bytes: 0, writes: 0)
    private var stopped = false

    // MARK: Lifecycle (main.swift, the settings observer)

    /// After Chromium started: `owner` is CraLog's answer, `recording` the setting and CRA_PERF.
    static func configure(owner: Bool, recording: Bool, config: Config, craVersion: String, chromiumVersion: String, onboarding: Bool) {
        Self.owner = owner
        Self.config = config
        appInfo = (craVersion, chromiumVersion, onboarding)
        setRecording(recording)
    }

    /// Settings ▸ Performance ▸ "Record performance". Off: no samples, no timers, no writes
    /// (files already written stay until Clear).
    static func setRecording(_ on: Bool) {
        guard let config else { return }
        if on, shared == nil {
            let r = PerfRecorder(config: config, writesFiles: PerfSessionRules.writesFiles(owner: owner, recording: true))
            shared = r
            Perf.attach { [weak r] fact in r?.record(fact) }
            r.start()
        } else if !on {
            Perf.attach(nil)
            shared?.stop(clean: false)
            shared = nil
        }
    }

    /// Cra quits: the history is saved and the marker removed, so the next launch knows this one
    /// ended normally.
    static func quit() {
        Perf.attach(nil)
        shared?.stop(clean: true)
        shared = nil
    }

    init(config: Config, writesFiles: Bool) {
        self.config = config
        self.writesFiles = writesFiles
        files = PerfFiles(folder: config.folder)
        state.policy = config.policy
        session = PerfSessionInfo(id: sessionID, launch: 0, startedAt: startedAt, uptimeSeconds: 0, craVersion: Self.appInfo.cra,
                                  chromiumVersion: Self.appInfo.chromium, onboarding: Self.appInfo.onboarding, firstLaunchAt: nil,
                                  previous: nil, writesFiles: writesFiles)
    }

    private func start() {
        // Reading is allowed to anyone; only the owner moves, prunes or writes.
        history = files.read(PerfHistory.self, from: files.history) ?? PerfHistory()
        let marker = writesFiles ? files.read(PerfSessionMarker.self, from: files.marker) : nil
        session.previous = PerfSessionRules.previous(marker: marker, history: history)
        if writesFiles {
            files.prepare()
            files.rotate(keepingHangsOf: session.previous?.id)
            history.launches += 1
            if history.firstLaunchAt == nil { history.firstLaunchAt = startedAt }
            write(PerfSessionMarker(id: sessionID, launch: history.launches, startedAt: startedAt, pid: getpid(), craVersion: session.craVersion),
                  to: files.marker)
        }
        session.launch = history.launches
        session.firstLaunchAt = history.firstLaunchAt
        if session.previous?.abnormal == true { CraLog.note("perf: the previous session (\(session.previous!.id)) ended without quitting") }

        let o = MainLoopObserver(stallMs: config.policy.stallMs, hangMs: config.policy.hangMs,
                                 onStall: { [weak self] ms, end, mode in self?.passEnded(ms: ms, at: end, mode: mode) },
                                 onHang: { [weak self] ms, start, mode in self?.hangStarted(ms: ms, at: start, mode: mode) })
        observer = o
        o.start()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + config.sampleInterval, repeating: config.sampleInterval, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        queue.async { [weak self] in self?.measured { self?.sampleProcesses() } }
    }

    private func stop(clean: Bool) {
        guard !stopped else { return }
        stopped = true
        observer?.stop()
        timer?.cancel()
        queue.sync {
            guard writesFiles else { return }
            if clean {
                pullObserver()
                history.record(lock.withLock { state.historySample() }, at: Date())
                history.lastSession = PerfPreviousSession(id: sessionID, launch: session.launch, startedAt: startedAt,
                                                          craVersion: session.craVersion, abnormal: false, endedAt: Date())
                write(history, to: files.history, pretty: false)
                write(buildReport(), to: files.blackBox)
            }
            try? FileManager.default.removeItem(at: files.marker)
        }
    }

    // MARK: Facts

    private func seconds(_ at: UInt64) -> Double { Double(Int64(bitPattern: at &- Perf.launchedAt)) / 1e9 }

    private func record(_ fact: Perf.Fact) {
        lock.lock()
        defer { lock.unlock() }
        switch fact {
        case .time(let metric, let ms): state.time(metric, ms: ms)
        case .count(let counter, let key, let site, let at): state.count(counter, key: key, at: seconds(at), site: site)
        case .mark(let label, let at): state.mark(label, at: seconds(at))
        case .phase(let name, let ms): state.phase(name, ms: ms)
        case .visibleSite(let host): state.visibleSite = host
        }
    }

    /// The main thread, after a pass of a quarter second or more.
    private func passEnded(ms: Double, at: UInt64, mode: String) {
        let stall = lock.withLock { state.pass(ms: ms, endedAt: seconds(at), mode: mode) }
        if let stall, stall.kind != .stall { CraLog.note("perf: main thread blocked \(Int(ms)) ms (\(stall.mode))\(stall.marks.last.map { " after \($0)" } ?? "")") }
        // The hang file of this pass learns how it ended.
        let start = at &- UInt64(ms * 1e6)
        queue.async { [weak self] in
            guard let self, let url = self.hangFiles.first(where: { abs(Int64(bitPattern: $0.key &- start)) < 50_000_000 })?.value,
                  var hang = self.files.read(PerfHang.self, from: url) else { return }
            hang.endedMs = ms
            self.write(hang, to: url)
        }
    }

    /// The watchdog thread, while the main thread is still blocked: the file is written now, in
    /// case Cra never comes back (a force quit), then the stack is added.
    private func hangStarted(ms: Double, at start: UInt64, mode: String) {
        let (number, marks, site): (Int, [String], String?) = lock.withLock {
            hangs += 1
            let s = state.policy.stall(at: seconds(Perf.now()), ms: ms, mode: mode, marks: state.marks.elements, site: state.visibleSite)
            return (hangs, s?.marks ?? [], state.visibleSite)
        }
        guard writesFiles, number <= 3 else { return }
        var hang = PerfHang(session: sessionID, number: number, at: seconds(start), stalledMs: ms,
                            mode: PerfStallPolicy.shortMode(mode), marks: marks, site: site,
                            stackNote: number <= config.stacks ? "sampling" : "stacks off")
        let url = files.hang(session: sessionID, number: number)
        write(hang, to: url)
        queue.async { [weak self] in self?.hangFiles[start] = url }
        guard number <= config.stacks else { return }
        hang.stack = Self.sampleMainThread()
        hang.stackNote = hang.stack.isEmpty ? "sample gave no main thread" : nil
        // The pass may have ended while `sample` ran: keep what the main thread wrote.
        if let now = files.read(PerfHang.self, from: url) { hang.endedMs = now.endedMs }
        write(hang, to: url)
    }

    /// One second of `/usr/bin/sample` on Cra, every 10 ms, from the watchdog thread.
    private static func sampleMainThread() -> [String] {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cra-hang-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: out) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = [String(getpid()), "1", "10", "-mayDie", "-file", out.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        p.waitUntilExit()
        guard let text = try? String(contentsOf: out, encoding: .utf8) else { return [] }
        return PerfSampleStack.mainThread(from: text)
    }

    /// From the main sampler.
    @MainActor func tabs(_ counts: PerfTabCounts) { lock.withLock { state.tabs = counts } }

    @MainActor func pageLongTasks(count: Int, totalMs: Double, durations: [Double]) {
        lock.withLock { state.pageLongTasks(count: count, totalMs: totalMs, durations: durations) }
    }

    @MainActor func addMainThreadCost(ns: UInt64) { lock.withLock { cost.cpuNs &+= ns } }

    // MARK: The queue

    private func tick() {
        measured {
            samples += 1
            sampleProcesses()
            pullObserver()
            history.record(lock.withLock { state.historySample() }, at: Date())
            if writesFiles, samples % config.blackBoxEvery == 0 { write(buildReport(), to: files.blackBox) }
            if writesFiles, samples % config.historyEvery == 0 { write(history, to: files.history, pretty: false) }
        }
        if let sampler = Self.mainSampler {
            DispatchQueue.main.async { [weak self] in if let self { sampler(self) } }
        }
    }

    private func measured(_ work: () -> Void) {
        let start = MainLoopObserver.threadCPU()
        work()
        let used = MainLoopObserver.threadCPU() &- start
        lock.withLock { cost.cpuNs &+= used }
    }

    private func sampleProcesses() {
        let groups = processes.update(processSampler.read(), atNs: Perf.now())
        let sys = system.read(dataFolder: config.folder)
        lock.withLock {
            state.processes = groups
            state.system = sys
        }
    }

    private func pullObserver() {
        guard let d = observer?.drain() else { return }
        lock.withLock {
            state.addPasses(d.passes)
            cost.cpuNs &+= d.observerNs &+ d.watchdogNs
            cost.observerNs &+= d.observerNs
            cost.callbacks += d.callbacks
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL, pretty: Bool = true) {
        let n = files.write(value, to: url, pretty: pretty)
        lock.withLock {
            cost.bytes += n
            cost.writes += 1
        }
    }

    /// On the queue.
    private func buildReport(storage: PerfReport.Storage = PerfReport.Storage()) -> PerfReport {
        var info = session
        info.uptimeSeconds = Date().timeIntervalSince(startedAt)
        let uptimeMs = max(info.uptimeSeconds * 1000, 1)
        let (snapshot, c) = lock.withLock { (state, cost) }
        let selfCost = PerfSelfCost(cpuMs: Double(c.cpuNs) / 1e6, cpuPct: Double(c.cpuNs) / 1e6 / uptimeMs * 100,
                                    observerCallbacks: c.callbacks, observerMs: Double(c.observerNs) / 1e6,
                                    bytesWritten: c.bytes, writes: c.writes,
                                    memoryBytes: snapshot.estimatedBytes + history.buckets.count * 120)
        return snapshot.report(generatedAt: Date(), session: info, selfCost: selfCost, storage: storage)
    }

    // MARK: Reading (the pane, the export, scenarios)

    /// The report as of now, on the main thread.
    func snapshot(_ done: @escaping @MainActor (PerfReport) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.measured { self.pullObserver() }
            let r = self.buildReport()
            DispatchQueue.main.async { done(r) }
        }
    }

    /// Help ▸ Export Diagnostics: `perf.json` (with the profile's size, measured now), the previous
    /// session's black box and the hang files, as text for the zip (Diagnostics redacts them).
    static func exportFiles(_ done: @escaping @MainActor ([(name: String, text: String)], Set<String>) -> Void) {
        let r = shared
        let folder = config?.folder
        let chromium = config?.chromiumFolder
        let work = {
            var out: [(String, String)] = []
            var sites = Set<String>()
            let sizes = chromium.map(PerfFolderSizes.measure)
            if let r {
                r.pullObserver()
                let report = r.buildReport(storage: .init(profileBytes: sizes?.profile, cacheBytes: sizes?.cache))
                sites = report.sites
                if let data = try? PerfReport.encoder().encode(report) { out.append(("perf.json", String(decoding: data, as: UTF8.self))) }
            } else {
                out.append(("perf.json", "{\n  \"recording\" : false\n}\n"))
            }
            if let folder {
                let files = PerfFiles(folder: folder)
                for url in [files.previousBlackBox] + files.hangFiles() {
                    if let data = try? Data(contentsOf: url) { out.append(("perf/" + url.lastPathComponent, String(decoding: data, as: UTF8.self))) }
                }
            }
            DispatchQueue.main.async { done(out, sites) }
        }
        if let r { r.queue.async(execute: work) } else { DispatchQueue.global(qos: .utility).async(execute: work) }
    }

    /// Settings ▸ Performance ▸ Clear: the files, and what this session recorded so far.
    static func clear() {
        if let r = shared {
            r.queue.async {
                r.lock.withLock {
                    let policy = r.state.policy
                    r.state = PerfState()
                    r.state.policy = policy
                }
                r.history = PerfHistory()
                if r.writesFiles { r.files.clear() }
            }
        } else if let folder = config?.folder {
            PerfFiles(folder: folder).clear()
        }
    }
}
