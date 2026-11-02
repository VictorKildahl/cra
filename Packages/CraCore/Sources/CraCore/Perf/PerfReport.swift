import Foundation

/// perf.json in Help ▸ Export Diagnostics, and the black box Cra keeps in `Perf/blackbox.json`
/// (GitHub #91). Numbers and site names only: no addresses, paths, titles or page text. Sites
/// appear where something happened on one (a stall while it was on screen, a renderer that
/// crashed) and become `site-N` with "Hide site names".
public struct PerfReport: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning or goes away; new fields don't bump it.
    public static let currentSchema = 1

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
    public var insights: [PerfInsight]

    public struct MainThread: Codable, Equatable, Sendable {
        public var passes: LogHistogram
        public var stalls: Int
        public var longStalls: Int
        public var hangs: Int
        /// Stalls in a tracking or modal loop (a held menu, a drag, an alert): not freezes.
        public var outsideFreezes: Int
        public var longestMs: Double
        public var recent: [PerfStall]

        public init(passes: LogHistogram = LogHistogram(), stalls: Int = 0, longStalls: Int = 0, hangs: Int = 0,
                    outsideFreezes: Int = 0, longestMs: Double = 0, recent: [PerfStall] = []) {
            self.passes = passes
            self.stalls = stalls
            self.longStalls = longStalls
            self.hangs = hangs
            self.outsideFreezes = outsideFreezes
            self.longestMs = longestMs
            self.recent = recent
        }
    }

    public struct Tabs: Codable, Equatable, Sendable {
        public var latest: PerfTabCounts?
        /// The page long tasks in the visible tab, summed since launch.
        public var longTasks: Int
        public var longTaskMs: Double

        public init(latest: PerfTabCounts? = nil, longTasks: Int = 0, longTaskMs: Double = 0) {
            self.latest = latest
            self.longTasks = longTasks
            self.longTaskMs = longTaskMs
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
                insights: [PerfInsight]) {
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
        return s
    }
}

/// Which launch this is, and how the one before it ended.
public struct PerfSessionInfo: Codable, Equatable, Sendable {
    /// Random per launch: matches a report to its hang files. Not an installation id.
    public var id: String
    /// How many times this data folder has been started, this launch included.
    public var launch: Int
    public var startedAt: Date
    public var uptimeSeconds: Double
    public var craVersion: String
    public var chromiumVersion: String
    /// This launch ran the onboarding (a fresh install, or one that never finished it).
    public var onboarding: Bool
    public var firstLaunchAt: Date?
    public var previous: PerfPreviousSession?
    /// Whether this Cra writes files under Perf/ (it owns the data folder and recording is on).
    public var writesFiles: Bool

    public init(id: String, launch: Int, startedAt: Date, uptimeSeconds: Double, craVersion: String, chromiumVersion: String,
                onboarding: Bool, firstLaunchAt: Date?, previous: PerfPreviousSession?, writesFiles: Bool) {
        self.id = id
        self.launch = launch
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
        self.craVersion = craVersion
        self.chromiumVersion = chromiumVersion
        self.onboarding = onboarding
        self.firstLaunchAt = firstLaunchAt
        self.previous = previous
        self.writesFiles = writesFiles
    }
}

/// What the profiler itself costs, so CI can hold it to its budget (under 0.1 % of a core).
public struct PerfSelfCost: Codable, Equatable, Sendable {
    public var cpuMs: Double
    public var cpuPct: Double
    /// Main run-loop callbacks observed, and their estimated cost (included in `cpuMs`).
    public var observerCallbacks: Int
    public var observerMs: Double
    public var bytesWritten: Int
    public var writes: Int
    /// The recorder's own data in memory, estimated from its counts.
    public var memoryBytes: Int

    public init(cpuMs: Double = 0, cpuPct: Double = 0, observerCallbacks: Int = 0, observerMs: Double = 0, bytesWritten: Int = 0,
                writes: Int = 0, memoryBytes: Int = 0) {
        self.cpuMs = cpuMs
        self.cpuPct = cpuPct
        self.observerCallbacks = observerCallbacks
        self.observerMs = observerMs
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
