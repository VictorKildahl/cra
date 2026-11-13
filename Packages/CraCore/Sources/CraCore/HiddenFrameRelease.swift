import Foundation

/// Which hidden tabs' page windows draw once more so their last frame lets go of the page (#195).
///
/// Every Cra tab is its own Chromium window. A tab's window that is ordered out has its compositor
/// suspended with its last frame, and that frame keeps the page's surface, and the page's ~15 MB of
/// tiles, alive after Chromium evicts it. Chromium (HideDelegatedFrameHostMac) evicts a hidden page's
/// frame past its saved-frame cap (5, the most recently hidden first kept) and once it has been
/// hidden 5 minutes, on a 5-minute timer, so by 10 minutes. Chrome detaches a background tab from its
/// window instead, so nothing keeps it. A window that draws once after the eviction releases it.
public enum HiddenFrameRelease {
    /// Chromium's baseline saved-frame cap (FrameEvictionManager: 5). Cra turns off its doubling with
    /// plenty of memory (ScalableFrameEviction, CraCEF.mm): the five tabs used last are the ones tab
    /// freezing keeps running, and each saved frame held ~15 MB of GPU memory. A tab further back
    /// draws its page again when shown.
    public static let savedFrames = 5
    /// How long after the page windows change (a switch, a new tab) the release runs, besides the
    /// once-a-minute pass: a tab past the saved-frame cap is evicted as it is hidden, so its ~15 MB
    /// can go at once, and opening twenty tabs no longer held ~240 MB more in the GPU process for up
    /// to a minute. Long enough that a burst of switches draws nothing until it ends.
    public static let afterPageChange: TimeInterval = 2
    /// Page windows drawing at once. Each goes in as a child of the browser window, and AppKit
    /// sorts all of that window's children on every order in and out: 45 at once (fifty tabs
    /// opened quickly) held the main thread 2.3-3.2 s. In passes of a few it stays a few ms each.
    public static let perPass = 4
    /// Between passes, after a pass's draws are done (0.25 s).
    public static let passGap: TimeInterval = 0.4

    /// The windows to draw in this pass, and whether another pass is needed after it.
    public static func pass(_ due: [UUID]) -> (now: [UUID], more: Bool) {
        (Array(due.prefix(perPass)), due.count > perPass)
    }
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

extension HiddenFrameRelease {
    /// One thing done to a hidden tab's page window while it draws for a release (#261).
    public enum WindowStep: Equatable, Sendable {
        /// alphaValue 0.
        case transparent
        /// alphaValue 1.
        case opaque
        /// ignoresMouseEvents.
        case clickThrough(Bool)
        /// A child window of the browser window, ordered below it. On its own, a window ordered in
        /// isn't kept below a full-screen window: macOS put it over it, or Stage Manager listed it.
        case attachBelow
        /// No longer a child of the browser window.
        case detach
        case orderOut
    }

    /// What puts a hidden tab's page window on screen to draw once, unseen.
    public static let drawSteps: [WindowStep] = [.transparent, .clickThrough(true), .attachBelow]

    /// What ends the draw. Off screen before it is opaque again: a frame committed between the two
    /// showed the window's empty grey background (#261). `shown` when the tab came on screen
    /// meanwhile: the window stays, on its own, to be attached above like any page window.
    public static func doneSteps(shown: Bool) -> [WindowStep] {
        (shown ? [.detach] : [.orderOut, .detach]) + [.opaque, .clickThrough(false)]
    }
}
