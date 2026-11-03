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
    /// long tasks and frames (PerfCEF), then reports back through `tabs(_:)`, `userIdle`,
    /// `pageLongTasks` and `pageFrames`.
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
    /// Cra's start, not the recorder's, cut to the second because the files keep dates to the
    /// second; `at` counts from there, so `startedAt + at` is the wall time (GitHub #135).
    private let startedAt: Date
    private let startedAtFraction: Double
    /// When this recorder started, for what recording cost per awake second.
    private let recordingStart = Perf.now()
    private var observer: MainLoopObserver?
    private var timer: DispatchSourceTimer?
    private var processes = PerfProcessTable()
    private var processSampler = PerfProcessSampler()
    private var system = PerfSystemSampler()
    private var samples = 0
    private var hangs = 0
    private var hangFiles: [UInt64: URL] = [:]
    /// `sample` runs this session (at most `config.stacks`), and the pass the slow-pass one is of;
    /// both under `lock`.
    private var stacksTaken = 0
    private var slowPassStart: UInt64?
    /// The slow pass's `sample` while it runs (the watchdog thread's alone).
    private var slowSample: Sample?
    /// What recording costs, under `lock` (the queue, the watchdog and the main thread add to it).
    private struct Cost {
        var observerNs: UInt64 = 0, watchdogNs: UInt64 = 0, processNs: UInt64 = 0, systemNs: UInt64 = 0
        var filesNs: UInt64 = 0, mainNs: UInt64 = 0
        var callbacks = 0, bytes = 0, writes = 0
        var totalNs: UInt64 { observerNs &+ watchdogNs &+ processNs &+ systemNs &+ filesNs &+ mainNs }
    }
    private var cost = Cost()
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
        let launched = Date().timeIntervalSince1970 - Perf.secondsSinceLaunch(Perf.now())
        startedAt = Date(timeIntervalSince1970: launched.rounded(.down))
        startedAtFraction = launched - launched.rounded(.down)
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

        let o = MainLoopObserver(stallMs: config.policy.stallMs, slowMs: config.policy.slowStackMs, hangMs: config.policy.hangMs,
                                 onStall: { [weak self] ms, end, mode in self?.passEnded(ms: ms, at: end, mode: mode) },
                                 onSlow: { [weak self] ms, start, mode in self?.slowPassSeen(ms: ms, at: start, mode: mode) },
                                 onHang: { [weak self] ms, start, mode in self?.hangStarted(ms: ms, at: start, mode: mode) },
                                 onWatch: { [weak self] in self?.watchSlowSample() })
        observer = o
        o.start()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + config.sampleInterval, repeating: config.sampleInterval, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        queue.async { [weak self] in self?.sampleProcesses() }
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

    private func seconds(_ at: UInt64) -> Double { Perf.secondsSinceLaunch(at) + startedAtFraction }

    private func record(_ fact: Perf.Fact) {
        lock.lock()
        defer { lock.unlock() }
        switch fact {
        case .time(let metric, let ms): state.time(metric, ms: ms)
        case .count(let counter, let key, let site, let at): state.count(counter, key: key, at: seconds(at), site: site)
        case .mark(let label, let at): state.mark(label, at: seconds(at))
        case .phase(let name, let ms): state.phase(name, ms: ms)
        case .visibleSite(let host): state.visibleSite = host
        case .app(let active, let onScreen):
            state.appActive = active
            state.appOnScreen = onScreen
        }
    }

    /// The main thread, after a pass of a quarter second or more.
    private func passEnded(ms: Double, at: UInt64, mode: String) {
        let start = at &- UInt64(ms * 1e6)
        let stall: PerfStall? = lock.withLock {
            if let s = slowPassStart, abs(Int64(bitPattern: s &- start)) < 50_000_000 { state.slowPass?.endedMs = ms }
            return state.pass(ms: ms, endedAt: seconds(at), mode: mode)
        }
        if let stall, stall.kind != .stall { CraLog.note("perf: main thread blocked \(Int(ms)) ms (\(stall.mode))\(stall.marks.last.map { " after \($0)" } ?? "")") }
        // The hang file of this pass learns how it ended.
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
        let (number, marks, site, sampling): (Int, [String], String?, Bool) = lock.withLock {
            hangs += 1
            let marks = state.policy.breadcrumbs(at: seconds(Perf.now()), ms: ms, marks: state.marks.elements)
            let sampling = writesFiles && hangs <= 3 && stacksTaken < config.stacks
            if sampling { stacksTaken += 1 }
            return (hangs, marks, state.visibleSite, sampling)
        }
        guard writesFiles, number <= 3 else { return }
        let hang = PerfHang(session: sessionID, number: number, at: seconds(start), stalledMs: ms,
                            mode: PerfStallPolicy.shortMode(mode), marks: marks, site: site,
                            stackNote: sampling ? "sampling" : config.stacks == 0 ? "stacks off" : "stack limit reached")
        let url = files.hang(session: sessionID, number: number)
        write(hang, to: url)
        queue.async { [weak self] in self?.hangFiles[start] = url }
        guard sampling else { return }
        var stack: [String] = []
        if let sample = Sample() {
            while !sample.ended { usleep(100_000) }
            stack = sample.stack()
        }
        // On the queue, after any `endedMs` the main thread's recovery queued while `sample` ran.
        queue.sync {
            var latest = files.read(PerfHang.self, from: url) ?? hang
            latest.stack = stack
            latest.stackNote = stack.isEmpty ? "sample gave no main thread" : nil
            write(latest, to: url)
        }
    }

    /// The watchdog thread, at the first pass of the session that lasts `slowStackMs` (below a
    /// hang): one `sample` while it still lasts, kept in memory for the report. It doesn't wait
    /// for the stack, so the watchdog still sees the pass turn into a hang.
    private func slowPassSeen(ms: Double, at start: UInt64, mode: String) {
        let take: Bool = lock.withLock {
            guard slowPassStart == nil, stacksTaken < config.stacks else { return false }
            stacksTaken += 1
            slowPassStart = start
            state.slowPass = PerfHang(session: sessionID, number: 0, at: seconds(start), stalledMs: ms, mode: PerfStallPolicy.shortMode(mode),
                                      marks: state.policy.breadcrumbs(at: seconds(Perf.now()), ms: ms, marks: state.marks.elements),
                                      site: state.visibleSite, stackNote: "sampling")
            return true
        }
        guard take else { return }
        slowSample = Sample()
        if slowSample == nil { lock.withLock { state.slowPass?.stackNote = "sample did not start" } }
    }

    /// The watchdog thread, twice a second: the slow pass's stack once `sample` has ended.
    private func watchSlowSample() {
        guard let sample = slowSample, sample.ended else { return }
        slowSample = nil
        let stack = sample.stack()
        lock.withLock {
            state.slowPass?.stack = stack
            state.slowPass?.stackNote = stack.isEmpty ? "sample gave no main thread" : nil
        }
    }

    /// One second of `/usr/bin/sample` on Cra, every 10 ms. Started with posix_spawn and checked
    /// with waitpid rather than Process: inside Cra, Process never learnt that `sample` ended (its
    /// termination handler never ran and `waitUntilExit` would never return), though it did in
    /// the test harness, which has no Chromium (GitHub #135).
    private final class Sample {
        let pid: pid_t
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cra-hang-\(UUID().uuidString).txt")
        let started = Perf.now()

        init?() {
            let args = ["/usr/bin/sample", String(getpid()), "1", "10", "-mayDie", "-file", out.path]
            var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
            // None of Chromium's descriptors go along.
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
            var child: pid_t = 0
            guard posix_spawn(&child, args[0], &actions, &attributes, &argv, environ) == 0 else { return nil }
            pid = child
        }

        /// Reaped here, or already by whoever else waits for Cra's children (ECHILD). One that
        /// takes 20 s is ended: a CI runner's `sample` is slow to attach, never that slow.
        var ended: Bool {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) != 0 { return true }
            guard Perf.now() &- started > 20_000_000_000 else { return false }
            kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0)
            return true
        }

        /// The main thread's stack, once `ended`; the output file goes.
        func stack() -> [String] {
            defer { try? FileManager.default.removeItem(at: out) }
            return (try? String(contentsOf: out, encoding: .utf8)).map { PerfSampleStack.mainThread(from: $0) } ?? []
        }
    }

    /// From the main sampler.
    @MainActor func tabs(_ counts: PerfTabCounts) { lock.withLock { state.tabs = counts } }

    @MainActor func pageLongTasks(count: Int, totalMs: Double, durations: [Double]) {
        lock.withLock { state.pageLongTasks(count: count, totalMs: totalMs, durations: durations) }
    }

    @MainActor func pageFrames(_ f: PerfPageFrames) { lock.withLock { state.pageFrames(f) } }

    /// The session's slow pass as recorded so far (scripts/test-perf.sh waits for its stack).
    var slowPass: PerfHang? { lock.withLock { state.slowPass } }

    /// Whether the Mac had no keyboard or mouse input for a minute: the next samples count as idle.
    @MainActor func userIdle(_ idle: Bool) { lock.withLock { state.userIdle = idle } }

    @MainActor func addMainThreadCost(ns: UInt64) { lock.withLock { cost.mainNs &+= ns } }

    // MARK: The queue

    private func tick() {
        samples += 1
        sampleProcesses()
        measured(\.filesNs) {
            pullObserver()
            history.record(lock.withLock { state.historySample() }, at: Date())
            if writesFiles, samples % config.blackBoxEvery == 0 { write(buildReport(), to: files.blackBox) }
            if writesFiles, samples % config.historyEvery == 0 { write(history, to: files.history, pretty: false) }
        }
        if let sampler = Self.mainSampler {
            DispatchQueue.main.async { [weak self] in if let self { sampler(self) } }
        }
    }

    /// The queue's CPU time for `work`, added to one part of the self-cost.
    private func measured(_ part: WritableKeyPath<Cost, UInt64>, _ work: () -> Void) {
        let start = MainLoopObserver.threadCPU()
        work()
        let used = MainLoopObserver.threadCPU() &- start
        lock.withLock { cost[keyPath: part] &+= used }
    }

    private func sampleProcesses() {
        var groups: [PerfProcessGroup] = []
        var sys: PerfSystemSample?
        measured(\.processNs) { groups = processes.update(processSampler.read(), atNs: Perf.now()) }
        measured(\.systemNs) { sys = system.read(dataFolder: config.folder) }
        lock.withLock {
            state.processes = groups
            state.system = sys
            state.idleSample(cpuPct: groups.reduce(0) { $0 + $1.cpuPct })
        }
    }

    private func pullObserver() {
        guard let d = observer?.drain() else { return }
        lock.withLock {
            state.addPasses(d.passes)
            cost.observerNs &+= d.observerNs
            cost.watchdogNs &+= d.watchdogNs
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
        let now = Perf.now()
        info.uptimeSeconds = seconds(now)
        // Two clock reads apart, a Mac that never slept can come out a few nanoseconds below zero.
        info.asleepSeconds = max(0, Double(Int64(bitPattern: Perf.asleepNs() &- Perf.launchedAsleep)) / 1e9)
        // Over the awake time this recorder ran (it can start after launch, from Settings).
        let recordingMs = max(Double(now &- recordingStart) / 1e6, 1)
        let (snapshot, c) = lock.withLock { (state, cost) }
        func ms(_ ns: UInt64) -> Double { Double(ns) / 1e6 }
        let selfCost = PerfSelfCost(cpuMs: ms(c.totalNs), cpuPct: ms(c.totalNs) / recordingMs * 100,
                                    observerCallbacks: c.callbacks, observerMs: ms(c.observerNs), watchdogMs: ms(c.watchdogNs),
                                    processSampleMs: ms(c.processNs), systemSampleMs: ms(c.systemNs), filesMs: ms(c.filesNs),
                                    mainSamplerMs: ms(c.mainNs), bytesWritten: c.bytes, writes: c.writes,
                                    memoryBytes: snapshot.estimatedBytes + history.buckets.count * 120)
        return snapshot.report(generatedAt: Date(), session: info, selfCost: selfCost, storage: storage)
    }

    // MARK: Reading (the pane, the export, scenarios)

    /// The report as of now, on the main thread.
    func snapshot(_ done: @escaping @MainActor (PerfReport) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.measured(\.filesNs) { self.pullObserver() }
            let r = self.buildReport()
            DispatchQueue.main.async { done(r) }
        }
    }

    /// Help ▸ Export Diagnostics: `perf.json` (with the profile's size, measured now), the previous
    /// session's black box, the 24-hour history (5-minute buckets: when the stalls and long tasks
    /// happened) and the hang files, as text for the zip (Diagnostics redacts them).
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
                for url in [files.previousBlackBox, files.history] + files.hangFiles() {
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
