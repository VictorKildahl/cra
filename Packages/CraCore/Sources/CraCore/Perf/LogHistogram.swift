import Foundation

/// Durations in power-of-two buckets: under 1 ms, 1–2, 2–4, 4–8 ms and so on, the last one
/// 32.8 s or more. A fixed 17 numbers whatever it counts, so a run loop that turns thousands of times a second costs
/// the same memory as a tab switch, and two histograms add up bucket by bucket.
public struct LogHistogram: Codable, Equatable, Sendable {
    public static let bucketCount = 17
    public private(set) var buckets: [Int]
    public private(set) var count = 0
    public private(set) var totalMs: Double = 0
    public private(set) var maxMs: Double = 0

    public init() { buckets = Array(repeating: 0, count: Self.bucketCount) }

    /// The bucket for a duration: 0 below 1 ms, then n for [2^(n-1), 2^n) ms.
    public static func bucket(ms: Double) -> Int {
        guard ms >= 1, ms.isFinite else { return ms.isFinite ? 0 : bucketCount - 1 }
        let whole = UInt64(min(ms, 1e12))
        return min(64 - whole.leadingZeroBitCount, bucketCount - 1)
    }

    /// The lower edge of a bucket in milliseconds.
    public static func lowerBound(_ bucket: Int) -> Double { bucket <= 0 ? 0 : Double(1 << (bucket - 1)) }

    public mutating func record(_ ms: Double) {
        let ms = max(0, ms)
        buckets[Self.bucket(ms: ms)] += 1
        count += 1
        totalMs += ms.isFinite ? ms : 0
        if ms > maxMs, ms.isFinite { maxMs = ms }
    }

    public mutating func add(_ other: LogHistogram) {
        for i in buckets.indices { buckets[i] += other.buckets[i] }
        count += other.count
        totalMs += other.totalMs
        maxMs = max(maxMs, other.maxMs)
    }

    /// At most this many milliseconds for `fraction` of the samples: the upper edge of the
    /// bucket the percentile falls in (never above the largest sample). 0 when empty.
    public func percentile(_ fraction: Double) -> Double {
        guard count > 0 else { return 0 }
        let rank = max(1, Int((Double(count) * min(max(fraction, 0), 1)).rounded(.up)))
        var seen = 0
        for (i, n) in buckets.enumerated() {
            seen += n
            if seen >= rank { return min(Self.lowerBound(i + 1), maxMs) }
        }
        return maxMs
    }

    public var meanMs: Double { count == 0 ? 0 : totalMs / Double(count) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try c.decode([Int].self, forKey: .buckets)
        buckets = Array((stored + Array(repeating: 0, count: Self.bucketCount)).prefix(Self.bucketCount))
        count = try c.decode(Int.self, forKey: .count)
        totalMs = try c.decode(Double.self, forKey: .totalMs)
        maxMs = try c.decode(Double.self, forKey: .maxMs)
    }
}

/// The newest `capacity` elements, oldest first. Appending past the capacity drops the oldest,
/// so the recorder's memory has a ceiling however long Cra runs.
public struct PerfRing<Element> {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0
    /// Everything ever appended, including what has been dropped.
    public private(set) var appended = 0

    public init(capacity: Int) { self.capacity = max(1, capacity) }

    public mutating func append(_ e: Element) {
        appended += 1
        if storage.count < capacity { storage.append(e); return }
        storage[head] = e
        head = (head + 1) % capacity
    }

    public var elements: [Element] { Array(storage[head...] + storage[..<head]) }
    public var last: Element? { storage.isEmpty ? nil : storage[(head + storage.count - 1) % storage.count] }
    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func removeAll() { storage = []; head = 0 }

    /// The last element, changed in place (a history bucket still filling).
    public mutating func updateLast(_ change: (inout Element) -> Void) {
        guard !storage.isEmpty else { return }
        change(&storage[(head + storage.count - 1) % storage.count])
    }
}

extension PerfRing: Equatable where Element: Equatable {
    public static func == (a: PerfRing, b: PerfRing) -> Bool { a.capacity == b.capacity && a.elements == b.elements }
}

extension PerfRing: Sendable where Element: Sendable {}

extension PerfRing: Codable where Element: Codable {
    private enum CodingKeys: String, CodingKey { case capacity, elements }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(capacity: try c.decode(Int.self, forKey: .capacity))
        for e in try c.decode([Element].self, forKey: .elements) { append(e) }
        appended = count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(capacity, forKey: .capacity)
        try c.encode(elements, forKey: .elements)
    }
}
