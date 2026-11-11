import CoreGraphics
import Foundation

/// Where the pointer brings the hidden sidebar out and where it lets it go. Both the shell's
/// tracking area and the floating panel's pointer poll use the same window-local boundaries.
public enum FloatingSidebarGeometry {
    /// The hidden sidebar comes out over the whole 10 pt margin left of the page and from just
    /// outside the window (2–4 pt, as in Arc). Arc 1.170's own strip is 5 pt (measured 29 Oct:
    /// out at 1–5 pt, not at 6 or 9 pt); the full margin is a deliberate choice, easier to hit.
    public static let revealInside: CGFloat = 10
    /// Edge to edge there is no margin: the strip over the page is Arc's 5 pt.
    public static let revealInsideEdgeToEdge: CGFloat = 5
    public static let revealOutside: CGFloat = 4
    public static let margin: CGFloat = 8
    /// How far past the sidebar the pointer may go before it leaves. Arc 1.172.1 (120 fps, 9 Nov 2026,
    /// GitHub #293) keeps a 264 pt sidebar out until x ≈ 345, 81 pt past its width; Cra let go 32 pt past
    /// it, so a hand drifting off the sidebar's edge sent it away and back.
    public static let leaveSlack: CGFloat = 73
    /// How long the pointer stays in the strip before the sidebar comes out. Arc moves ~150 ms after the
    /// pointer arrives (its own reaction takes ~35 ms of that), and an edge brushed for 86 ms doesn't
    /// reveal at all (GitHub #293). Cra revealed on the first sample, so passing the edge made it flicker.
    public static let revealDwell: TimeInterval = 0.1
    /// How long a pointer thrown past the left edge rests out there before the sidebar comes out, and
    /// the longest one that keeps moving waits. Arc 1.172.2 (120 fps, 11 Nov 2026, GitHub #350) starts
    /// 135–160 ms after the pointer's last move, and 218–227 ms after it crossed the edge when it keeps
    /// moving, at 100 to 1500 pt/s alike. Only the 30 Hz poll sees the pointer out there, so these are
    /// three and five of its looks after the first: at 0.1 s and 0.17 s a look that came a millisecond
    /// early cost one more, and Cra ran 20–30 ms behind Arc (144–195 ms and 252–258 ms).
    public static let offEdgeRest: TimeInterval = 0.085
    public static let offEdgeLongestWait: TimeInterval = 0.15

    /// Whether the pointer may bring the sidebar out at all: the sidebar is hidden, or a page is in full
    /// screen over it. Arc 1.172.1 brings it out over a full-screen element (a video) as well (offline
    /// copy, 10 Nov 2026, GitHub #315); Cra left it in. A sidebar shown beside the page is out of sight
    /// while the page is full screen, so it comes out then too (inferred, not measured).
    public static func mayReveal(sidebarShown: Bool, pageFullscreen: Bool) -> Bool {
        !sidebarShown || pageFullscreen
    }

    /// The strip at the window's left edge.
    public static func shouldReveal(at point: CGPoint, in bounds: CGRect, edgeToEdge: Bool = false) -> Bool {
        point.y >= bounds.minY && point.y <= bounds.maxY
            && point.x >= bounds.minX - revealOutside && point.x <= bounds.minX + (edgeToEdge ? revealInsideEdgeToEdge : revealInside)
    }

    /// Beside the window, left of its edge: where a pointer thrown past the edge lands (GitHub #350).
    /// Arc 1.172.2 (11 Nov 2026, a 264 pt sidebar): out with the pointer 250 pt left of the window, not
    /// at 270, and a sidebar that is out leaves at 252–257, so the zone is as wide as the sidebar less
    /// its 8 pt margin. Arc's zone sits ~24 pt lower than its window (from ~32 pt under the top to
    /// ~17 pt under the bottom); Cra's is the window's own height.
    public static func isOffLeftEdge(_ point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat) -> Bool {
        point.y >= bounds.minY && point.y <= bounds.maxY
            && point.x < bounds.minX - revealOutside && point.x >= bounds.minX - (sidebarWidth - margin)
    }

    public static func shouldHide(at point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat,
                                  pressedMouseButtons: Int, edgeToEdge: Bool = false) -> Bool {
        // Window movement can put the pointer outside the panel briefly. Preserve
        // the active drag/context gesture; the next released-pointer check dismisses.
        guard pressedMouseButtons == 0, !shouldReveal(at: point, in: bounds, edgeToEdge: edgeToEdge) else { return false }
        // A sidebar that is out stays out while the pointer is beside the window, as in Arc (#350).
        guard !isOffLeftEdge(point, in: bounds, sidebarWidth: sidebarWidth) else { return false }
        return !bounds.contains(point) || point.x > bounds.minX + sidebarWidth + margin + leaveSlack
    }
}

/// The wait before a hidden sidebar comes out: the pointer has to stay in the reveal strip for
/// `FloatingSidebarGeometry.revealDwell`; leaving it starts the wait over (GitHub #293).
public struct FloatingSidebarRevealDwell {
    public private(set) var since: TimeInterval?

    public init() {}

    /// One pointer sample: true once the pointer has been in the strip long enough.
    public mutating func sample(inStrip: Bool, at now: TimeInterval) -> Bool {
        guard inStrip else { since = nil; return false }
        let start = since ?? now
        since = start
        return now - start >= FloatingSidebarGeometry.revealDwell
    }

    public mutating func reset() { since = nil }
}

/// A pointer thrown past the window's left edge brings the hidden sidebar out too (GitHub #350):
/// without it, a hand that overshot a window standing clear of the screen's edge got nothing.
///
/// Arc 1.172.2 (11 Nov 2026, pointer driven at 120 fps): the pointer has to come out of the window.
/// One that arrives beside it from above, from below or from further left brings nothing out,
/// however long it stays and moves there. Out there, the sidebar starts ~150 ms after the pointer
/// comes to rest, and ~222 ms after it crossed the edge when it keeps moving; one that is back over
/// the page before that (out 40 pt and in again within 30 ms) shows nothing.
public struct FloatingSidebarOffEdge {
    public enum Step: Equatable, Sendable {
        /// Not beside the window, or it didn't come from the window.
        case away
        /// Out there, waiting to rest.
        case waiting
        case reveal
    }

    /// Whether the last sample was over the window or in its edge strip: only from there does
    /// leaving count.
    private var fromWindow = false
    /// When the pointer went off the edge, and when it last moved out there.
    private var since: TimeInterval?
    private var moved: TimeInterval = 0
    private var last: CGPoint = .zero

    public init() {}

    /// One pointer sample, in the shell's coordinates.
    public mutating func sample(_ point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat, at now: TimeInterval) -> Step {
        let off = FloatingSidebarGeometry.isOffLeftEdge(point, in: bounds, sidebarWidth: sidebarWidth)
        let armed = since != nil || fromWindow
        fromWindow = bounds.contains(point) || FloatingSidebarGeometry.shouldReveal(at: point, in: bounds)
        guard off, armed else { since = nil; return .away }
        if since == nil || point != last { moved = now }
        let start = since ?? now
        since = start
        last = point
        let rested = now - moved >= FloatingSidebarGeometry.offEdgeRest
        return rested || now - start >= FloatingSidebarGeometry.offEdgeLongestWait ? .reveal : .waiting
    }

    public mutating func reset() {
        fromWindow = false
        since = nil
    }
}
