import CoreGraphics

/// An embedded page's frames in the window during a ⌘S slide; it should not move while its card does.
public struct SidebarSlidePage: Equatable, Sendable {
    private var minX: ClosedRange<CGFloat>?
    private var maxX: ClosedRange<CGFloat>?
    public private(set) var samples = 0

    public init() {}

    /// `drawn` is false while the page's own layer still shows its frame from before the slide
    /// (the slide's first layout not yet committed). Until the first drawn sample, that is the
    /// picture from before ⌘S, not the page moving, so it is skipped; after it every sample counts.
    public mutating func record(_ frameInWindow: CGRect, drawn: Bool = true) {
        guard drawn || minX != nil else { return }
        samples += 1
        minX = Self.widen(minX, frameInWindow.minX)
        maxX = Self.widen(maxX, frameInWindow.maxX)
    }

    public var drift: CGFloat { max(leftEdgeDrift, rightEdgeDrift) }
    /// How far the page's left edge travelled during the slide.
    public var leftEdgeDrift: CGFloat { minX.map { $0.upperBound - $0.lowerBound } ?? 0 }
    /// How far the page's right edge travelled during the slide.
    public var rightEdgeDrift: CGFloat { maxX.map { $0.upperBound - $0.lowerBound } ?? 0 }
    /// The edge away from the sidebar, which stays put in both ways of sliding (#317, #613).
    public func farEdgeDrift(sidebarOnLeft: Bool) -> CGFloat { sidebarOnLeft ? rightEdgeDrift : leftEdgeDrift }
    /// The edge beside the sidebar, which follows the card in a live slide.
    public func nearEdgeDrift(sidebarOnLeft: Bool) -> CGFloat { sidebarOnLeft ? leftEdgeDrift : rightEdgeDrift }

    public static func frame(from: CGRect, to: CGRect, progress p: Double) -> CGRect {
        let p = CGFloat(p)
        return CGRect(x: from.minX + (to.minX - from.minX) * p, y: from.minY + (to.minY - from.minY) * p,
                      width: from.width + (to.width - from.width) * p, height: from.height + (to.height - from.height) * p)
    }

    public var isEmpty: Bool { minX == nil }

    private static func widen(_ r: ClosedRange<CGFloat>?, _ x: CGFloat) -> ClosedRange<CGFloat> {
        guard let r else { return x...x }
        return min(r.lowerBound, x)...max(r.upperBound, x)
    }
}

/// What a page does while ⌘S slides the sidebar in or out.
public enum SidebarSlidePages: String, Sendable, CaseIterable {
    /// Arc's (#613, measured in the reporter's 120 fps side-by-side): the page is sized to its card every frame and
    /// reflows as the card's edge moves, so nothing pops when the slide ends; the edge away from the sidebar stays put.
    case live
    /// Cra's since #317: the page is sized once for where it ends up and the card slides over it.
    case frozen

    /// Arc's.
    public static let arcs: SidebarSlidePages = .live
    /// Whether the page is held at its destination size during the slide.
    public var freezesPages: Bool { self == .frozen }
}
