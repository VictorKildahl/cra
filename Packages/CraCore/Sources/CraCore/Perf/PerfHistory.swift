import Foundation

/// `Perf/history.json`: the last 24 hours in 5-minute buckets, across launches, written every
/// 15 minutes and when Cra quits. One-minute buckets would be about 1.1 MB, and rewriting that
/// every 15 minutes would break the write budget (GitHub #91).
public struct PerfHistory: Codable, Equatable, Sendable {
    public static let bucketSeconds: Double = 300
    public static let capacity = 288

    /// Launches of this data folder while recording was on.
    public var launches = 0
    public var firstLaunchAt: Date?
    /// The last session that quitting closed normally (an abnormal one leaves its marker instead).
    public var lastSession: PerfPreviousSession?
    public var buckets = PerfRing<PerfHistoryBucket>(capacity: PerfHistory.capacity)

    public init() {}

    /// Adds a sample to its 5-minute bucket, starting a new bucket when the clock moved past the
    /// last one. A clock that went back (the user changed it) starts a new bucket too.
    public mutating func record(_ sample: PerfHistorySample, at date: Date) {
        let start = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / Self.bucketSeconds).rounded(.down) * Self.bucketSeconds)
        if buckets.last?.start == start {
            buckets.updateLast { $0.add(sample) }
        } else {
            var b = PerfHistoryBucket(start: start)
            b.add(sample)
            buckets.append(b)
        }
    }

    /// Buckets that started within `seconds` before `now`.
    public func recent(_ seconds: Double, now: Date) -> [PerfHistoryBucket] {
        buckets.elements.filter { $0.start > now.addingTimeInterval(-seconds - Self.bucketSeconds) && $0.start <= now }
    }

    private enum CodingKeys: String, CodingKey { case launches, firstLaunchAt, lastSession, buckets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launches = try c.decodeIfPresent(Int.self, forKey: .launches) ?? 0
        firstLaunchAt = try c.decodeIfPresent(Date.self, forKey: .firstLaunchAt)
        lastSession = try c.decodeIfPresent(PerfPreviousSession.self, forKey: .lastSession)
        // A file from a build with another capacity keeps its newest buckets.
        var ring = PerfRing<PerfHistoryBucket>(capacity: Self.capacity)
        for b in (try c.decodeIfPresent(PerfRing<PerfHistoryBucket>.self, forKey: .buckets))?.elements ?? [] { ring.append(b) }
        buckets = ring
    }
}

/// What one 5-second sample adds to the history: levels, and counts since the sample before.
public struct PerfHistorySample: Equatable, Sendable {
    public var cpuPct: Double
    public var footprintBytes: Int64
    public var stalls: Int
    public var longStalls: Int
    public var longTasks: Int
    public var rendererCrashes: Int
    public var liveTabs: Int

    public init(cpuPct: Double, footprintBytes: Int64, stalls: Int = 0, longStalls: Int = 0, longTasks: Int = 0,
                rendererCrashes: Int = 0, liveTabs: Int = 0) {
        self.cpuPct = cpuPct
        self.footprintBytes = footprintBytes
        self.stalls = stalls
        self.longStalls = longStalls
        self.longTasks = longTasks
        self.rendererCrashes = rendererCrashes
        self.liveTabs = liveTabs
    }
}

public struct PerfHistoryBucket: Codable, Equatable, Sendable {
    public var start: Date
    public var samples = 0
    /// Cra and its helpers, percent of one core, averaged over the bucket.
    public var cpuPct: Double = 0
    /// The largest memory footprint of Cra and its helpers in the bucket.
    public var footprintMB: Int = 0
    public var stalls = 0
    public var longStalls = 0
    public var longTasks = 0
    public var rendererCrashes = 0
    public var liveTabs = 0

    public init(start: Date) { self.start = start }

    public mutating func add(_ s: PerfHistorySample) {
        cpuPct = (cpuPct * Double(samples) + s.cpuPct) / Double(samples + 1)
        samples += 1
        footprintMB = max(footprintMB, Int(s.footprintBytes >> 20))
        stalls += s.stalls
        longStalls += s.longStalls
        longTasks += s.longTasks
        rendererCrashes += s.rendererCrashes
        liveTabs = max(liveTabs, s.liveTabs)
    }
}
