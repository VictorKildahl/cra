import Foundation

/// One process at one sample: its CPU over the interval before and its memory now.
public struct PerfProcessUsage: Equatable, Sendable {
    public var pid: Int32
    public var kind: PerfProcessKind
    /// Percent of one core over the last sample interval.
    public var cpuPct: Double
    public var footprintBytes: Int64

    public init(pid: Int32, kind: PerfProcessKind, cpuPct: Double, footprintBytes: Int64) {
        self.pid = pid
        self.kind = kind
        self.cpuPct = cpuPct
        self.footprintBytes = footprintBytes
    }
}

/// The process a history bucket remembers: the one with the most memory, and the one with the
/// most CPU. A 0.1.44 report had 14–17 GB and 440–500 % CPU with four tabs, and the buckets held
/// only Cra's totals, so nothing said which process it was.
public struct PerfHistoryProcess: Codable, Equatable, Sendable {
    public var kind: PerfProcessKind
    public var footprintMB: Int
    public var cpuPct: Double
    /// The sites with a frame in that process, when the engine says (renderers only).
    public var sites: [String]

    public init(kind: PerfProcessKind, footprintMB: Int, cpuPct: Double, sites: [String] = []) {
        self.kind = kind
        self.footprintMB = footprintMB
        self.cpuPct = cpuPct
        self.sites = sites
    }

    public init(_ u: PerfProcessUsage, sites: [String] = []) {
        self.init(kind: u.kind, footprintMB: Int(u.footprintBytes >> 20), cpuPct: (u.cpuPct * 10).rounded() / 10, sites: sites)
    }
}

/// One process worth a line in cra.log.
public struct PerfRunaway: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// Its memory passed this many GB for the first time.
        case memory(gb: Int)
        /// It stayed over `PerfRunawayWatch.busyPct` for `busySamples` samples in a row.
        case cpu
    }

    public var usage: PerfProcessUsage
    public var reason: Reason

    public init(usage: PerfProcessUsage, reason: Reason) {
        self.usage = usage
        self.reason = reason
    }
}

/// When a single process runs away: its memory first passing 2 GB, then 4, 8, 16…, or its CPU
/// over two cores for 30 s (six 5-second samples). Each level once per process; the CPU line
/// again only after the process has calmed down below one core.
public struct PerfRunawayWatch: Sendable {
    public static let firstMemoryGB = 2
    public static let busyPct = 200.0
    public static let busySamples = 6
    public static let calmPct = 100.0

    private var memoryGB: [Int32: Int] = [:]
    private var busy: [Int32: Int] = [:]
    private var reported: Set<Int32> = []

    public init() {}

    public mutating func update(_ usage: [PerfProcessUsage]) -> [PerfRunaway] {
        let pids = Set(usage.map(\.pid))
        memoryGB = memoryGB.filter { pids.contains($0.key) }
        busy = busy.filter { pids.contains($0.key) }
        reported.formIntersection(pids)
        var out: [PerfRunaway] = []
        for u in usage {
            let gb = u.footprintBytes >> 30
            var level = memoryGB[u.pid] ?? Self.firstMemoryGB / 2
            while gb >= level * 2 { level *= 2 }
            if level > (memoryGB[u.pid] ?? Self.firstMemoryGB / 2) {
                memoryGB[u.pid] = level
                out.append(PerfRunaway(usage: u, reason: .memory(gb: level)))
            }
            if u.cpuPct >= Self.busyPct {
                busy[u.pid, default: 0] += 1
                if busy[u.pid] == Self.busySamples, !reported.contains(u.pid) {
                    reported.insert(u.pid)
                    out.append(PerfRunaway(usage: u, reason: .cpu))
                }
            } else {
                busy[u.pid] = 0
                if u.cpuPct < Self.calmPct { reported.remove(u.pid) }
            }
        }
        return out
    }
}

/// A process past `bytes` frees its memory only when the pages with a frame in it go: they sleep
/// at once, as Chrome's urgent discarding does, but only when none of them is on screen (a shown
/// page would load again straight away). A 0.1.44 report had one process at 14-17 GB and 4-5
/// cores for 15 minutes with four tabs, while the Mac sat idle.
public enum PerfRunawaySleep {
    public static let bytes: Int64 = 8 << 30

    /// The pages to put to sleep for `pid`, in the order given; none when one of them is shown.
    public static func pages<ID: Equatable>(for pid: Int32, among pages: [(id: ID, pids: Set<Int32>, shown: Bool)]) -> [ID] {
        let hosting = pages.filter { $0.pids.contains(pid) }
        guard !hosting.contains(where: \.shown) else { return [] }
        return hosting.map(\.id)
    }

    /// Whether a watch line calls for it: memory past `bytes`, not CPU alone (a video or a game
    /// keeps cores busy on purpose), and only a page's process.
    public static func applies(_ r: PerfRunaway, bytes: Int64 = bytes) -> Bool {
        guard r.usage.kind == .renderer, case .memory(let gb) = r.reason else { return false }
        return Int64(gb) << 30 >= bytes
    }
}
