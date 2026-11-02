import Foundation

/// One process as libproc read it at one sample. Nil numbers: macOS refused them (the process
/// ended between listing and reading, or isn't Cra's to read).
public struct PerfProcessReading: Equatable, Sendable {
    public var pid: Int32
    public var kind: PerfProcessKind
    /// User plus system CPU time since the process started, in nanoseconds.
    public var cpuNs: UInt64?
    public var footprintBytes: Int64?
    public var diskReadBytes: Int64?
    public var diskWriteBytes: Int64?
    public var wakeups: Int64?

    public init(pid: Int32, kind: PerfProcessKind, cpuNs: UInt64?, footprintBytes: Int64?, diskReadBytes: Int64?,
                diskWriteBytes: Int64?, wakeups: Int64?) {
        self.pid = pid
        self.kind = kind
        self.cpuNs = cpuNs
        self.footprintBytes = footprintBytes
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.wakeups = wakeups
    }
}

/// Turns readings taken every few seconds into per-kind groups: CPU over the interval since the
/// last reading, and how many processes of each kind came and went (renderer churn).
public struct PerfProcessTable: Sendable {
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousKinds: [Int32: PerfProcessKind]?
    private var previousAtNs: UInt64 = 0
    private var started: [PerfProcessKind: Int] = [:]
    private var ended: [PerfProcessKind: Int] = [:]

    public init() {}

    /// `atNs` is a monotonic clock (nanoseconds since boot). The first update has no interval
    /// yet: CPU reads 0, and the processes already running don't count as started.
    public mutating func update(_ readings: [PerfProcessReading], atNs: UInt64) -> [PerfProcessGroup] {
        let interval = previousAtNs > 0 && atNs > previousAtNs ? Double(atNs - previousAtNs) : 0
        var groups = Dictionary(uniqueKeysWithValues: PerfProcessKind.allCases.map { ($0, PerfProcessGroup(kind: $0, available: false)) })
        var cpu: [Int32: UInt64] = [:]
        for r in readings {
            var g = groups[r.kind]!
            g.count += 1
            if let now = r.cpuNs {
                g.available = true
                cpu[r.pid] = now
                if interval > 0, let before = previousCPU[r.pid], now >= before {
                    g.cpuPct += Double(now - before) / interval * 100
                }
            }
            g.footprintBytes += r.footprintBytes ?? 0
            g.diskReadBytes += r.diskReadBytes ?? 0
            g.diskWriteBytes += r.diskWriteBytes ?? 0
            g.wakeups += r.wakeups ?? 0
            groups[r.kind] = g
        }
        let kinds = Dictionary(readings.map { ($0.pid, $0.kind) }, uniquingKeysWith: { a, _ in a })
        if let before = previousKinds {
            for (pid, kind) in kinds where before[pid] == nil { started[kind, default: 0] += 1 }
            for (pid, kind) in before where kinds[pid] == nil { ended[kind, default: 0] += 1 }
        }
        previousKinds = kinds
        previousCPU = cpu
        previousAtNs = atNs
        return PerfProcessKind.allCases.compactMap { kind in
            guard var g = groups[kind] else { return nil }
            g.started = started[kind] ?? 0
            g.ended = ended[kind] ?? 0
            // A kind with no process now and none ever seen is left out; one that had some keeps its churn.
            if g.count == 0 { g.available = true }
            return g.count > 0 || g.started > 0 || g.ended > 0 ? g : nil
        }
    }
}
