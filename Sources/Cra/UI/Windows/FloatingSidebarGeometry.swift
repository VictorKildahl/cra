import Foundation

/// Both the shell's tracking area and the floating panel's pointer poll use the
/// same window-local boundaries.
enum FloatingSidebarGeometry {
    /// The hidden sidebar comes out over the whole 10 pt margin left of the page and from just
    /// outside the window (2–4 pt, as in Arc). Arc 1.170's own strip is 5 pt (measured 29 Oct:
    /// out at 1–5 pt, not at 6 or 9 pt); the full margin is a deliberate choice, easier to hit.
    static let revealInside: CGFloat = 10
    /// Edge to edge there is no margin: the strip over the page is Arc's 5 pt.
    static let revealInsideEdgeToEdge: CGFloat = 5
    static let revealOutside: CGFloat = 4
    static let margin: CGFloat = 8
    /// How far past the sidebar the pointer may go before it leaves. Arc 1.172.1 (120 fps, 9 Nov 2026,
    /// GitHub #293) keeps a 264 pt sidebar out until x ≈ 345, 81 pt past its width; Cra let go 32 pt past
    /// it, so a hand drifting off the sidebar's edge sent it away and back.
    static let leaveSlack: CGFloat = 73
    /// How long the pointer stays in the strip before the sidebar comes out. Arc moves ~150 ms after the
    /// pointer arrives (its own reaction takes ~35 ms of that), and an edge brushed for 86 ms doesn't
    /// reveal at all (GitHub #293). Cra revealed on the first sample, so passing the edge made it flicker.
    static let revealDwell: TimeInterval = 0.1

    /// Whether the pointer may bring the sidebar out at all: the sidebar is hidden, or a page is in full
    /// screen over it. Arc 1.172.1 brings it out over a full-screen element (a video) as well (offline
    /// copy, 10 Nov 2026, GitHub #315); Cra left it in. A sidebar shown beside the page is out of sight
    /// while the page is full screen, so it comes out then too (inferred, not measured).
    static func mayReveal(sidebarShown: Bool, pageFullscreen: Bool) -> Bool {
        !sidebarShown || pageFullscreen
    }

    static func shouldReveal(at point: CGPoint, in bounds: CGRect, edgeToEdge: Bool = false) -> Bool {
        point.y >= bounds.minY && point.y <= bounds.maxY
            && point.x >= bounds.minX - revealOutside && point.x <= bounds.minX + (edgeToEdge ? revealInsideEdgeToEdge : revealInside)
    }

    static func shouldHide(at point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat,
                           pressedMouseButtons: Int, edgeToEdge: Bool = false) -> Bool {
        // Window movement can put the pointer outside the panel briefly. Preserve
        // the active drag/context gesture; the next released-pointer check dismisses.
        guard pressedMouseButtons == 0, !shouldReveal(at: point, in: bounds, edgeToEdge: edgeToEdge) else { return false }
        return !bounds.contains(point) || point.x > bounds.minX + sidebarWidth + margin + leaveSlack
    }
}

/// The wait before a hidden sidebar comes out: the pointer has to stay in the reveal strip for
/// `FloatingSidebarGeometry.revealDwell`; leaving it starts the wait over (GitHub #293).
struct FloatingSidebarRevealDwell {
    private(set) var since: TimeInterval?

    /// One pointer sample: true once the pointer has been in the strip long enough.
    mutating func sample(inStrip: Bool, at now: TimeInterval) -> Bool {
        guard inStrip else { since = nil; return false }
        let start = since ?? now
        since = start
        return now - start >= FloatingSidebarGeometry.revealDwell
    }

    mutating func reset() { since = nil }
}
