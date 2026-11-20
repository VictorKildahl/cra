import Foundation

/// Which hidden pages tab sleeping asks to close. By default it is Arc's (GitHub #136): a page out
/// of sight for 4 hours closes unless it is one of the 10 tabs used last. Settings ▸ Tabs can
/// change the time, turn the clock off, or close pages while macOS reports memory pressure
/// (GitHub #153). The probes in BrowserManager still decide whether a candidate may close.
public struct TabSleepPolicy: Equatable, Sendable {
    public enum Reason: String, Sendable { case timer, memoryPressure, splitCopy, runaway }

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
    /// At most `timerLimit` pages are asked a pass. When hundreds cross the line in one minute each asked page
    /// is three page evaluations at once; the rest are asked on the next minutes' passes (#616, Victor 20 Nov 2026).
    public static func timer(_ after: TabSleepThreshold) -> TabSleepPolicy {
        TabSleepPolicy(hiddenFor: after.seconds, keepsRecentTabs: after.seconds >= TabSleepThreshold.fourHours.seconds, limit: timerLimit)
    }
    public static let timerLimit = 16

    /// "…when the Mac is short of memory": the pages hidden longest, whatever their rank, but
    /// none left in the last 5 minutes, so a tab just left (or just woken) isn't closed again.
    /// 3 at warning; 9 at critical, so a sweep keeps up with tabs opened faster than the clock
    /// closes them (#237: a burst of YouTube tabs held a 16 GB Mac 7 GB over its memory).
    public static func memoryPressure(_ level: PerfSystemSample.Pressure) -> TabSleepPolicy {
        TabSleepPolicy(hiddenFor: 5 * 60, keepsRecentTabs: false, limit: level == .critical ? 9 : 3, reason: .memoryPressure)
    }

    /// A pinned tab that a split pane copied (Arc): its page sleeps at once, the copy shows it.
    public static let splitCopy = TabSleepPolicy(hiddenFor: 0, keepsRecentTabs: false, limit: 1, reason: .splitCopy)
    /// A hidden page whose process ran away (PerfRunawaySleep).
    public static let runaway = TabSleepPolicy(hiddenFor: 0, keepsRecentTabs: false, reason: .runaway)

    /// How often the app's pass runs (AppComposition.tabSleepInterval).
    public static let passInterval: TimeInterval = 60

    /// Whether a pass runs now: the minute's timer, or the Mac waking (#275: the first sweep came
    /// 24 minutes after a wake; nothing listened for it). Within half a pass of the last one it
    /// doesn't, so the timer's overdue fire right after a wake's pass, or a burst of wakes, runs
    /// one pass, while the timer's jitter never skips one.
    public static func passDue(lastPass: Date?, now: Date) -> Bool {
        guard let lastPass else { return true }
        return now.timeIntervalSince(lastPass) >= passInterval / 2
    }

    /// Whether the minute's pass sweeps for memory pressure. macOS reports a level for a while
    /// after pages close, so at warning a sweep skips a pass for the last one to tell (every
    /// 2 minutes); at critical it sweeps every pass (#237). Half a pass of slack absorbs the
    /// timer's jitter.
    public static func sweepsForPressure(_ pressure: PerfSystemSample.Pressure, enabled: Bool, lastSweep: Date?, now: Date) -> Bool {
        guard enabled, pressure.isShort else { return false }
        guard let lastSweep else { return true }
        let passes: TimeInterval = pressure == .critical ? 1 : 2
        return now.timeIntervalSince(lastSweep) >= (passes - 0.5) * passInterval
    }

    /// What one pass closed, as one line per way of closing in cra.log (#237: a sweep of twelve
    /// pages wrote twelve identical lines). Hosts only, as everywhere in the log.
    public struct PassLog: Equatable, Sendable {
        public var reason: Reason
        private var pages: [(host: String, minutes: Int, discarded: Bool, processEnded: Bool)] = []

        public init(reason: Reason) { self.reason = reason }

        public static func == (a: PassLog, b: PassLog) -> Bool { a.reason == b.reason && a.lines == b.lines }

        /// A page the pass closed: discarded in place, or unloaded by a CEF that can't discard.
        public mutating func closed(host: String, hiddenFor: TimeInterval, discarded: Bool, processEnded: Bool) {
            pages.append((host, Int(max(hiddenFor, 0) / 60), discarded, processEnded))
        }

        /// A page the pass asked that refused (BrowserManager's probes: typed, beforeunload, call…).
        public mutating func refused(_ refusal: String) {
            if refusals[refusal] == nil { refusalOrder.append(refusal) }
            refusals[refusal, default: 0] += 1
        }

        private var refusals: [String: Int] = [:]
        private var refusalOrder: [String] = []

        /// A pressure sweep that closed nothing although it asked says why (#275: twelve sweeps
        /// after a wake asked 3 pages each, all refused, and the log had only their headers).
        /// The minute's timer pass stays quiet: its pages are asked again after the back-off.
        public var lines: [String] {
            let closed = closedLines
            guard closed.isEmpty, reason == .memoryPressure, !refusals.isEmpty else { return closed }
            let total = refusals.values.reduce(0, +)
            let reasons = refusalOrder.enumerated()
                .sorted { (refusals[$0.element]!, -$0.offset) > (refusals[$1.element]!, -$1.offset) }
                .map { "\($0.element) \(refusals[$0.element]!)" }
            return ["tab sleep for memory pressure closes nothing: \(total) page\(total == 1 ? "" : "s") refused (\(reasons.joined(separator: ", ")))"]
        }

        private var closedLines: [String] {
            let why = reason == .memoryPressure ? ", the Mac is short of memory" : reason == .splitCopy ? ", a split shows its copy"
                : reason == .runaway ? ", its process ran away" : ""
            return [(true, "discards"), (false, "unloads")].compactMap { discarded, verb in
                let ps = pages.filter { $0.discarded == discarded }
                guard !ps.isEmpty else { return nil }
                var counts: [String: Int] = [:], order: [String] = []
                for p in ps {
                    if counts[p.host] == nil { order.append(p.host) }
                    counts[p.host, default: 0] += 1
                }
                let hosts = order.enumerated().sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
                    .map { counts[$0.element]! > 1 ? "\($0.element) ×\(counts[$0.element]!)" : $0.element }
                let lo = ps.map(\.minutes).min()!, hi = ps.map(\.minutes).max()!
                let ended = ps.filter(\.processEnded).count
                let detail: String
                if ps.count == 1 {
                    detail = "hidden \(lo) min" + (ended == 1 ? ", its renderer ended" : "")
                } else {
                    detail = "\(ps.count) pages hidden " + (lo == hi ? "\(lo)" : "\(lo)–\(hi)") + " min"
                        + (ended == 0 ? "" : ", \(ended) renderer\(ended == 1 ? "" : "s") ended")
                }
                return "tab sleep \(verb) \(hosts.joined(separator: ", ")) (\(detail)\(why))"
            }
        }
    }

    /// Why a pass asks no page (#237: two pressure sweeps logged their cap and then nothing).
    /// `held` counts the candidates passed over by reason, `waiting` the ones inside their
    /// back-off after a refusal.
    public func nothingToClose(_ pages: [Page], visible: [UUID], held: [Hold: Int], waiting: Int, now: Date) -> String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var why: [String] = []
        if !held.isEmpty {
            let total = held.values.reduce(0, +)
            let reasons = held.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" }
            why.append("\(plural(total, "page")) passed over (\(reasons.joined(separator: ", ")))")
        }
        if waiting > 0 { why.append("\(plural(waiting, "page")) refused lately, asked again later") }
        if !why.isEmpty { return why.joined(separator: "; ") }
        let hidden = pages.compactMap { p in visible.contains(p.id) ? nil : p.hiddenAt }
        guard let earliest = hidden.min() else { return "no page is out of sight" }
        let longest = Int(now.timeIntervalSince(earliest) / 60)
        return "none of \(plural(hidden.count, "hidden page")) has been out of sight \(Int(hiddenFor / 60)) min (longest \(longest) min)"
    }

    /// A page as tab sleeping sees it: when it went off screen (nil while shown), when it last
    /// played or stopped playing sound, and whether its site is one the user keeps active (#458).
    public struct Page: Equatable, Sendable {
        public var id: UUID
        public var hiddenAt: Date?
        public var audibleAt: Date?
        public var keptActive: Bool

        public init(id: UUID, hiddenAt: Date?, audibleAt: Date? = nil, keptActive: Bool = false) {
            self.id = id
            self.hiddenAt = hiddenAt
            self.audibleAt = audibleAt
            self.keptActive = keptActive
        }
    }

    /// The tabs on screen, then the ones hidden most recently, `count` in all. Pages the user keeps
    /// active stay anyway, so they take none of the places: listing a site never makes another
    /// tab sleep sooner (#458).
    public static func recentlyShown(_ pages: [Page], visible: [UUID], count: Int) -> Set<UUID> {
        let kept = Set(pages.filter(\.keptActive).map(\.id))
        let hidden = pages.compactMap { p in p.keptActive ? nil : p.hiddenAt.map { (p.id, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return Set((visible.filter { !kept.contains($0) } + hidden).prefix(count))
    }

    /// Whether a page the user keeps active (#458) is left alone by this pass. Chrome's list at
    /// arc://settings/performance: Memory Saver and freezing never take one; urgent discarding,
    /// when the Mac is short of memory, takes them after every other page (`candidates`). A split's
    /// copy and a page whose process ran away go whatever their site.
    public var leavesKeptActivePages: Bool { reason == .timer }

    /// A candidate's page as BrowserManager sees it before asking it anything.
    public struct PageState: Equatable, Sendable {
        public var discarded = false
        public var hiddenAt: Date?
        public var audibleAt: Date?
        public var visible = false
        public var created = true
        public var closed = false
        public var loading = false
        public var pictureInPicture = false
        public var capturing = false
        public var audible = false
        public var devTools = false

        public init(discarded: Bool = false, hiddenAt: Date?, audibleAt: Date? = nil, visible: Bool = false, created: Bool = true,
                    closed: Bool = false, loading: Bool = false, pictureInPicture: Bool = false, capturing: Bool = false,
                    audible: Bool = false, devTools: Bool = false) {
            self.discarded = discarded
            self.hiddenAt = hiddenAt
            self.audibleAt = audibleAt
            self.visible = visible
            self.created = created
            self.closed = closed
            self.loading = loading
            self.pictureInPicture = pictureInPicture
            self.capturing = capturing
            self.audible = audible
            self.devTools = devTools
        }
    }

    /// Why a page stays awake without being asked, the first that holds (GitHub #214: a sweep
    /// that came 27 passes late could not say which). The raw values are `sleepSkip`'s keys in
    /// perf.json and the words in cra.log.
    public enum Hold: String, CaseIterable, Sendable {
        case discarded, shown, sound, notCreated, closing, loading, pictureInPicture, capturing, audible, devTools
    }

    /// nil when the page may be asked to sleep: out of sight and silent since before `cutoff`, made,
    /// not loading, and in no Picture in Picture, capture or DevTools.
    public static func hold(_ p: PageState, before cutoff: Date) -> Hold? {
        if p.discarded { return .discarded }
        if p.visible || p.hiddenAt.map({ $0 < cutoff }) != true { return .shown }
        if p.audibleAt.map({ $0 < cutoff }) == false { return .sound }
        if !p.created { return .notCreated }
        if p.closed { return .closing }
        if p.loading { return .loading }
        if p.pictureInPicture { return .pictureInPicture }
        if p.capturing { return .capturing }
        if p.audible { return .audible }
        if p.devTools { return .devTools }
        return nil
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
    /// before it counts toward `limit`. Pages the user keeps active (#458) are never asked by the
    /// clock, and under memory pressure only after every other page.
    public func candidates(_ pages: [Page], visible: [UUID], protectedRecent: Int = protectedRecentTabs, now: Date) -> [UUID] {
        let cutoff = now.addingTimeInterval(-hiddenFor)
        let kept = keepsRecentTabs ? Self.recentlyShown(pages, visible: visible, count: protectedRecent) : []
        let lastResort = reason == .memoryPressure
        return pages
            .filter { p in
                guard let hidden = p.hiddenAt, hidden < cutoff, !visible.contains(p.id), !kept.contains(p.id) else { return false }
                if p.keptActive, leavesKeptActivePages { return false }
                return p.audibleAt.map { $0 < cutoff } ?? true
            }
            .sorted {
                let a = lastResort && $0.keptActive, b = lastResort && $1.keptActive
                if a != b { return b }
                return ($0.hiddenAt!, $0.id.uuidString) < ($1.hiddenAt!, $1.id.uuidString)
            }
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
