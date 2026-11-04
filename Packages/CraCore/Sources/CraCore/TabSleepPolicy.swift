import Foundation

/// Which hidden pages tab sleeping asks to close. By default it is Arc's (GitHub #136): a page out
/// of sight for 4 hours closes unless it is one of the 10 tabs used last. Settings ▸ Tabs can
/// change the time, turn the clock off, or close pages while macOS reports memory pressure
/// (GitHub #153). The probes in BrowserManager still decide whether a candidate may close.
public struct TabSleepPolicy: Equatable, Sendable {
    public enum Reason: String, Sendable { case timer, memoryPressure, splitCopy }

    /// A page this long out of sight, and silent as long, is a candidate.
    public var hiddenFor: TimeInterval
    /// The tabs on screen and the ones hidden most recently, `protectedRecentTabs` in all, stay.
    public var keepsRecentTabs: Bool
    /// At most this many pages are asked in one pass (nil: all of them).
    public var limit: Int?
    public var reason: Reason

    public init(hiddenFor: TimeInterval, keepsRecentTabs: Bool = true, limit: Int? = nil, reason: Reason = .timer) {
        self.hiddenFor = hiddenFor
        self.keepsRecentTabs = keepsRecentTabs
        self.limit = limit
        self.reason = reason
    }

    /// Arc never discards the pages of the 10 tabs used last (WebContentLifecycleOptimization's
    /// protectedLRUTabCount).
    public static let protectedRecentTabs = 10

    /// "Force tabs out of memory after:". Arc's 4 hours, or longer, keep the 10 tabs used last;
    /// a shorter time is asked for to close those too, since they hold most of the memory.
    public static func timer(_ after: TabSleepThreshold) -> TabSleepPolicy {
        TabSleepPolicy(hiddenFor: after.seconds, keepsRecentTabs: after.seconds >= TabSleepThreshold.fourHours.seconds)
    }

    /// "…when the Mac is short of memory": the 3 pages hidden longest, whatever their rank, but
    /// none left in the last 5 minutes, so a tab just left (or just woken) isn't closed again.
    public static let memoryPressure = TabSleepPolicy(hiddenFor: 5 * 60, keepsRecentTabs: false, limit: 3, reason: .memoryPressure)

    /// A pinned tab that a split pane copied (Arc): its page sleeps at once, the copy shows it.
    public static let splitCopy = TabSleepPolicy(hiddenFor: 0, keepsRecentTabs: false, limit: 1, reason: .splitCopy)

    /// macOS reports a level for a while after pages close, so a sweep waits this long for the
    /// last one to tell before taking more.
    public static let pressureSweepInterval: TimeInterval = 90

    /// Whether the minute's pass sweeps for memory pressure.
    public static func sweepsForPressure(_ pressure: PerfSystemSample.Pressure, enabled: Bool, lastSweep: Date?, now: Date) -> Bool {
        enabled && pressure.isShort && lastSweep.map { now.timeIntervalSince($0) >= pressureSweepInterval } ?? true
    }

    /// A page as tab sleeping sees it: when it went off screen (nil while shown) and when it last
    /// played or stopped playing sound.
    public struct Page: Equatable, Sendable {
        public var id: UUID
        public var hiddenAt: Date?
        public var audibleAt: Date?

        public init(id: UUID, hiddenAt: Date?, audibleAt: Date? = nil) {
            self.id = id
            self.hiddenAt = hiddenAt
            self.audibleAt = audibleAt
        }
    }

    /// The tabs on screen, then the ones hidden most recently, `count` in all.
    public static func recentlyShown(_ pages: [Page], visible: [UUID], count: Int) -> Set<UUID> {
        let hidden = pages.compactMap { p in p.hiddenAt.map { (p.id, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return Set((visible + hidden).prefix(count))
    }

    /// Chromium's freezing policy sees what Cra's page probes can't: a call with the camera and
    /// microphone off (an open RTCPeerConnection), a USB, Bluetooth, HID or serial device, a
    /// mirrored or captured tab. `reasons` are its CannotFreezeReasonToString names for the page
    /// and the pages connected to it (Cra.getFreezingState); "" when none of them keeps it awake.
    public static func refusal(freezingReasons reasons: [String]) -> String {
        if reasons.contains("has an active WebRTC connection") { return "call" }
        if reasons.contains(where: { $0.hasPrefix("connected to ") }) { return "device" }
        if reasons.contains(where: { $0.hasPrefix("capturing ") || $0 == "being mirrored" }) { return "capturing" }
        return ""
    }

    /// The pages to ask, hidden longest first. The caller skips the ones its probes refuse
    /// before it counts toward `limit`.
    public func candidates(_ pages: [Page], visible: [UUID], protectedRecent: Int = protectedRecentTabs, now: Date) -> [UUID] {
        let cutoff = now.addingTimeInterval(-hiddenFor)
        let kept = keepsRecentTabs ? Self.recentlyShown(pages, visible: visible, count: protectedRecent) : []
        return pages
            .filter { p in
                guard let hidden = p.hiddenAt, hidden < cutoff, !visible.contains(p.id), !kept.contains(p.id) else { return false }
                return p.audibleAt.map { $0 < cutoff } ?? true
            }
            .sorted { ($0.hiddenAt!, $0.id.uuidString) < ($1.hiddenAt!, $1.id.uuidString) }
            .map(\.id)
    }
}

extension PerfSystemSample.Pressure {
    /// macOS warns while the compressor works hard; critical is the same state further along.
    public var isShort: Bool { self == .warning || self == .critical }
}

/// Settings ▸ Tabs ▸ "Force tabs out of memory after:" (GitHub #153). Arc's 4 hours by default;
/// the checkbox, not a case, turns the clock off.
public enum TabSleepThreshold: String, Codable, CaseIterable, Identifiable {
    case fifteenMinutes, thirtyMinutes, oneHour, twoHours, fourHours, eightHours
    public var id: String { rawValue }
    public var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 3600
        case .twoHours: return 2 * 3600
        case .fourHours: return 4 * 3600
        case .eightHours: return 8 * 3600
        }
    }
    public var label: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours"
        }
    }
}
