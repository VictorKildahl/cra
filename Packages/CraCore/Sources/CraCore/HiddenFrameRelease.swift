import Foundation

/// Which hidden tabs' page windows draw once more so their last frame lets go of the page (#195).
///
/// Every Cra tab is its own Chromium window. A tab's window that is ordered out has its compositor
/// suspended with its last frame, and that frame keeps the page's surface, and the page's ~15 MB of
/// tiles, alive after Chromium evicts it. Chromium (HideDelegatedFrameHostMac) evicts a hidden page's
/// frame past its saved-frame cap (10, the most recently hidden first kept) and once it has been
/// hidden 5 minutes, on a 5-minute timer, so by 10 minutes. Chrome detaches a background tab from its
/// window instead, so nothing keeps it. A window that draws once after the eviction releases it.
public enum HiddenFrameRelease {
    /// Chromium's saved-frame cap with plenty of memory (FrameEvictionManager: 2 × 5).
    public static let savedFrames = 10
    /// Chromium's culling delay (5 min) plus one timer period: evicted by then whenever it was hidden.
    public static let evictedAfter: TimeInterval = 10 * 60 + 30

    public struct Tab: Equatable {
        public var id: UUID
        public var hiddenAt: Date
        /// The `hiddenAt` this tab's window last drew for, if it has since being hidden.
        public var releasedFor: Date?
        public init(id: UUID, hiddenAt: Date, releasedFor: Date?) {
            self.id = id
            self.hiddenAt = hiddenAt
            self.releasedFor = releasedFor
        }
    }

    /// The hidden tabs whose window should draw now: those Chromium has evicted, by count (beyond
    /// the `savedFrames - visible` most recently hidden) or by time, and that haven't drawn since.
    public static func due(_ hidden: [Tab], visible: Int, now: Date, evictedAfter: TimeInterval = evictedAfter) -> [UUID] {
        let kept = max(0, savedFrames - visible)
        let byRecency = hidden.sorted { $0.hiddenAt > $1.hiddenAt }
        return byRecency.enumerated().compactMap { i, t in
            guard t.releasedFor != t.hiddenAt else { return nil }
            return i >= kept || now.timeIntervalSince(t.hiddenAt) >= evictedAfter ? t.id : nil
        }
    }
}
