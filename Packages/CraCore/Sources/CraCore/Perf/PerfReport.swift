import Foundation

/// perf.json in Help ▸ Export Diagnostics, and the black box Cra keeps in `Perf/blackbox.json`
/// (GitHub #91). Numbers and site names only: no addresses, paths, titles or page text. Sites
/// appear where something happened on one (a stall while it was on screen, a renderer that
/// crashed) and become `site-N` with "Hide site names".
public struct PerfReport: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning or goes away; new fields don't bump it. 2: a pass ends
    /// only where Core Animation commits, the freeze counts say so in their names, one clock
    /// for `at` and `startedAt` (GitHub #135).
    public static let currentSchema = 2

    public var schema = PerfReport.currentSchema
    public var generatedAt: Date
    public var session: PerfSessionInfo
    public var selfCost: PerfSelfCost
    public var mainThread: MainThread
    public var processes: [PerfProcessGroup]
    public var system: PerfSystemSample?
    public var tabs: Tabs
    public var timings: [String: LogHistogram]
    public var counters: [String: [String: Int]]
    public var startup: [String: Double]
    public var storage: Storage
    public var events: [PerfEvent]
    public var idle: Idle
    public var insights: [PerfInsight]

    /// Every pass is in `passes`. A stall (250 ms or more) in the default mode is a freeze; one in
    /// a menu, a drag, an alert or start-up is counted in `outsideFreezes` instead, and both are
    /// in `longestPassMs`, the honest answer to how long the main thread was blocked.
    public struct MainThread: Codable, Equatable, Sendable {
        public var passes: LogHistogram
        public var freezes: Int
        /// Freezes of 1 s or more, and of 2 s or more.
        public var longFreezes: Int
        public var hangs: Int
        public var outsideFreezes: Int
        public var longestFreezeMs: Double
        public var longestPassMs: Double
        /// The mode of the longest pass that was a stall (nil: none was).
        public var longestPassMode: String?
        public var recent: [PerfStall]
        /// The session's first pass that lasted `slowStackMs` while the watchdog looked, with the
        /// main thread's stack from `sample` (number 0: not a hang file).
        public var slowPass: PerfHang?

        public init(passes: LogHistogram = LogHistogram(), freezes: Int = 0, longFreezes: Int = 0, hangs: Int = 0,
                    outsideFreezes: Int = 0, longestFreezeMs: Double = 0, longestPassMs: Double = 0, longestPassMode: String? = nil,
                    recent: [PerfStall] = [], slowPass: PerfHang? = nil) {
            self.passes = passes
            self.freezes = freezes
            self.longFreezes = longFreezes
            self.hangs = hangs
            self.outsideFreezes = outsideFreezes
            self.longestFreezeMs = longestFreezeMs
            self.longestPassMs = longestPassMs
            self.longestPassMode = longestPassMode
            self.recent = recent
            self.slowPass = slowPass
        }
    }

    /// The visible tab's page, summed since launch (history.json has long tasks per 5 minutes).
    public struct Tabs: Codable, Equatable, Sendable {
        public var latest: PerfTabCounts?
        public var longTasks: Int
        public var longTaskMs: Double
        /// Chromium's long animation frames (50 ms or more from input or rAF to the frame), and
        /// the longest: frames the page was late with.
        public var longFrames: Int
        public var longestFrameMs: Double
        /// `getVideoPlaybackQuality()` over the page's videos while they played on screen.
        public var videoFrames: Int
        public var droppedVideoFrames: Int

        public init(latest: PerfTabCounts? = nil, longTasks: Int = 0, longTaskMs: Double = 0, longFrames: Int = 0,
                    longestFrameMs: Double = 0, videoFrames: Int = 0, droppedVideoFrames: Int = 0) {
            self.latest = latest
            self.longTasks = longTasks
            self.longTaskMs = longTaskMs
            self.longFrames = longFrames
            self.longestFrameMs = longestFrameMs
            self.videoFrames = videoFrames
            self.droppedVideoFrames = droppedVideoFrames
        }
    }

    /// Cra and its helpers while nobody used the Mac (no keyboard or mouse input for a minute).
    public struct Idle: Codable, Equatable, Sendable {
        /// 5-second samples taken while idle, and Cra's average CPU over them (percent of a core).
        public var samples: Int
        public var cpuPct: Double

        public init(samples: Int = 0, cpuPct: Double = 0) {
            self.samples = samples
            self.cpuPct = cpuPct
        }
    }

    public struct Storage: Codable, Equatable, Sendable {
        /// The Chromium profile without its caches, and the caches; measured at export.
        public var profileBytes: Int64?
        public var cacheBytes: Int64?
        public var freeDiskBytes: Int64?

        public init(profileBytes: Int64? = nil, cacheBytes: Int64? = nil, freeDiskBytes: Int64? = nil) {
            self.profileBytes = profileBytes
            self.cacheBytes = cacheBytes
            self.freeDiskBytes = freeDiskBytes
        }
    }

    public init(generatedAt: Date, session: PerfSessionInfo, selfCost: PerfSelfCost, mainThread: MainThread,
                processes: [PerfProcessGroup], system: PerfSystemSample?, tabs: Tabs, timings: [String: LogHistogram],
                counters: [String: [String: Int]], startup: [String: Double], storage: Storage, events: [PerfEvent],
                idle: Idle = Idle(), insights: [PerfInsight]) {
        self.generatedAt = generatedAt
        self.session = session
        self.selfCost = selfCost
        self.mainThread = mainThread
        self.processes = processes
        self.system = system
        self.tabs = tabs
        self.timings = timings
        self.counters = counters
        self.startup = startup
        self.storage = storage
        self.events = events
        self.idle = idle
        self.insights = insights
    }

    /// The encoder for every Perf file: sorted keys (a diff between two reports reads), ISO dates.
    public static func encoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Every site name in the report, for "Hide site names".
    public var sites: Set<String> {
        var s = Set(mainThread.recent.compactMap(\.site))
        s.formUnion(events.compactMap(\.site))
        if let site = mainThread.slowPass?.site { s.insert(site) }
        return s
    }
}

/// Which launch this is, and how the one before it ended.
public struct PerfSessionInfo: Codable, Equatable, Sendable {
    /// Random per launch: matches a report to its hang files. Not an installation id.
    public var id: String
    /// How many times this data folder has been started, this launch included.
    public var launch: Int
    /// When Cra started (the top of main.swift), to the second. Every `at` in the report is seconds
    /// since then on a clock that counts the Mac's sleep, so `startedAt + at` is the time in cra.log.
    public var startedAt: Date
    /// Since `startedAt`, and how much of it the Mac slept.
    public var uptimeSeconds: Double
    public var asleepSeconds: Double
    public var craVersion: String
    public var chromiumVersion: String
    /// This launch ran the onboarding (a fresh install, or one that never finished it).
    public var onboarding: Bool
    public var firstLaunchAt: Date?
    public var previous: PerfPreviousSession?
    /// Whether this Cra writes files under Perf/ (it owns the data folder and recording is on).
    public var writesFiles: Bool

    public init(id: String, launch: Int, startedAt: Date, uptimeSeconds: Double, asleepSeconds: Double = 0, craVersion: String,
                chromiumVersion: String, onboarding: Bool, firstLaunchAt: Date?, previous: PerfPreviousSession?, writesFiles: Bool) {
        self.id = id
        self.launch = launch
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
        self.asleepSeconds = asleepSeconds
        self.craVersion = craVersion
        self.chromiumVersion = chromiumVersion
        self.onboarding = onboarding
        self.firstLaunchAt = firstLaunchAt
        self.previous = previous
        self.writesFiles = writesFiles
    }

    /// Awake time: what rates per hour and CPU shares are taken over.
    public var awakeSeconds: Double { max(uptimeSeconds - asleepSeconds, 0) }
}

/// What the profiler itself costs, so CI can hold it to its budget (`PerfInsights.selfCostBudgetPct`).
public struct PerfSelfCost: Codable, Equatable, Sendable {
    /// All of it, as a share of one core over the awake time recording was on.
    public var cpuMs: Double
    public var cpuPct: Double
    /// Main run-loop callbacks observed, and their estimated cost.
    public var observerCallbacks: Int
    public var observerMs: Double
    /// The rest of `cpuMs` by part: the watchdog, the 5-second process and Mac samples, the black
    /// box and history (building, encoding, writing) and the main thread's tab count and page read.
    public var watchdogMs: Double
    public var processSampleMs: Double
    public var systemSampleMs: Double
    public var filesMs: Double
    public var mainSamplerMs: Double
    public var bytesWritten: Int
    public var writes: Int
    /// The recorder's own data in memory, estimated from its counts.
    public var memoryBytes: Int

    public init(cpuMs: Double = 0, cpuPct: Double = 0, observerCallbacks: Int = 0, observerMs: Double = 0, watchdogMs: Double = 0,
                processSampleMs: Double = 0, systemSampleMs: Double = 0, filesMs: Double = 0, mainSamplerMs: Double = 0,
                bytesWritten: Int = 0, writes: Int = 0, memoryBytes: Int = 0) {
        self.cpuMs = cpuMs
        self.cpuPct = cpuPct
        self.observerCallbacks = observerCallbacks
        self.observerMs = observerMs
        self.watchdogMs = watchdogMs
        self.processSampleMs = processSampleMs
        self.systemSampleMs = systemSampleMs
        self.filesMs = filesMs
        self.mainSamplerMs = mainSamplerMs
        self.bytesWritten = bytesWritten
        self.writes = writes
        self.memoryBytes = memoryBytes
    }
}

/// Cra's processes of one kind at the last sample, and over the session.
public struct PerfProcessGroup: Codable, Equatable, Sendable {
    public var kind: PerfProcessKind
    public var count: Int
    /// Percent of one core over the last sample interval, summed over the group.
    public var cpuPct: Double
    public var footprintBytes: Int64
    public var diskReadBytes: Int64
    public var diskWriteBytes: Int64
    /// Wakeups since the processes started: in the file, not the pane (the same call as CPU time).
    public var wakeups: Int64
    /// Processes of this kind that started and ended since launch (renderers coming and going).
    public var started: Int
    public var ended: Int
    /// False when macOS refused the numbers for every process of the group.
    public var available: Bool

    public init(kind: PerfProcessKind, count: Int = 0, cpuPct: Double = 0, footprintBytes: Int64 = 0, diskReadBytes: Int64 = 0,
                diskWriteBytes: Int64 = 0, wakeups: Int64 = 0, started: Int = 0, ended: Int = 0, available: Bool = true) {
        self.kind = kind
        self.count = count
        self.cpuPct = cpuPct
        self.footprintBytes = footprintBytes
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.wakeups = wakeups
        self.started = started
        self.ended = ended
        self.available = available
    }
}

/// The Mac as a whole at the last sample.
public struct PerfSystemSample: Codable, Equatable, Sendable {
    public enum Pressure: String, Codable, Sendable { case normal, warning, critical, unknown }

    /// All cores together, 0–100.
    public var cpuPct: Double?
    public var memoryPressure: Pressure
    /// ProcessInfo.ThermalState: nominal, fair, serious, critical.
    public var thermalState: String
    public var lowPowerMode: Bool
    public var freeDiskBytes: Int64?

    public init(cpuPct: Double?, memoryPressure: Pressure, thermalState: String, lowPowerMode: Bool, freeDiskBytes: Int64?) {
        self.cpuPct = cpuPct
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
        self.freeDiskBytes = freeDiskBytes
    }

    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical.
    public static func pressure(level: Int32?) -> Pressure {
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }
}

/// Tabs by state, counted every few seconds.
public struct PerfTabCounts: Codable, Equatable, Sendable {
    public var tabs: Int
    /// Tabs with a page in memory, those on screen, those tab sleeping closed (not shown since).
    public var live: Int
    public var visible: Int
    public var slept: Int
    public var incognito: Int
    public var windows: Int

    public init(tabs: Int, live: Int, visible: Int, slept: Int, incognito: Int, windows: Int) {
        self.tabs = tabs
        self.live = live
        self.visible = visible
        self.slept = slept
        self.incognito = incognito
        self.windows = windows
    }
}

/// One thing that happened: a stall, a renderer that crashed, a load that failed.
public struct PerfEvent: Codable, Equatable, Sendable {
    /// Seconds since the session started.
    public var at: Double
    public var kind: String
    public var detail: String
    public var ms: Double?
    public var site: String?

    public init(at: Double, kind: String, detail: String, ms: Double? = nil, site: String? = nil) {
        self.at = at
        self.kind = kind
        self.detail = detail
        self.ms = ms
        self.site = site
    }
}

/// `Perf/hang-<session>-<n>.json`: a main thread blocked for 2 s or more, written by the watchdog
/// while it lasted (so it survives a force quit), with the main thread's stack when `sample` ran.
public struct PerfHang: Codable, Equatable, Sendable {
    public var session: String
    public var number: Int
    /// Seconds since the session started, when the block began.
    public var at: Double
    /// How long it had lasted when the file was written, and in the end (nil: Cra never recovered).
    public var stalledMs: Double
    public var endedMs: Double?
    public var mode: String
    public var marks: [String]
    public var site: String?
    public var stack: [String]
    /// Why there is no stack (sampling off, the limit reached, `sample` failed).
    public var stackNote: String?

    public init(session: String, number: Int, at: Double, stalledMs: Double, endedMs: Double? = nil, mode: String,
                marks: [String], site: String?, stack: [String] = [], stackNote: String? = nil) {
        self.session = session
        self.number = number
        self.at = at
        self.stalledMs = stalledMs
        self.endedMs = endedMs
        self.mode = mode
        self.marks = marks
        self.site = site
        self.stack = stack
        self.stackNote = stackNote
    }
}
