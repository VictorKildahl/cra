import CoreGraphics
import Foundation

/// Which side of the window the sidebar docks on (GitHub #464, not in Arc: Arc's sidebar is
/// always on the left). On the right the window is Arc's left-hand layout seen in a mirror: the
/// sidebar, its resize edge, the strip that brings a hidden sidebar out and the room the pointer
/// may take past the window all swap sides. What is inside the sidebar keeps its own layout,
/// traffic lights first, and the page's bars keep theirs.
///
/// Layout code works out a frame for the left-hand sidebar and then `place`s it; pointer tests
/// `place` the point first and then ask the left-hand question.
public enum SidebarSide: String, Codable, CaseIterable, Sendable {
    case left, right

    /// `rect`, laid out for a left-hand sidebar inside `bounds`, where it goes for this side:
    /// mirrored across the vertical centre line of `bounds` on the right.
    public func place(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard self == .right, !rect.isNull else { return rect }
        return CGRect(x: bounds.minX + bounds.maxX - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// `point` seen from a left-hand layout: mirrored across the vertical centre line of `bounds`
    /// on the right. Its own inverse, so it maps either way.
    public func place(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        guard self == .right else { return point }
        return CGPoint(x: bounds.minX + bounds.maxX - point.x, y: point.y)
    }

    /// A horizontal distance the pointer travelled, seen from a left-hand layout: + is toward the
    /// window's right on the left, toward its left on the right (a resize drag's "wider").
    public func place(dx: CGFloat) -> CGFloat { self == .right ? -dx : dx }

    /// Where a card `width` wide starts beside `anchor` (a sidebar, a row, a favorite), out over the
    /// page: its left edge `gap` past the anchor's right edge, or on the right its right edge `gap`
    /// before the anchor's left one. A negative gap overlaps the anchor (Arc's favorite card, 4 pt).
    public func cardMinX(beside anchor: CGRect, gap: CGFloat, width: CGFloat) -> CGFloat {
        self == .right ? anchor.minX - gap - width : anchor.maxX + gap
    }

    /// The SF Symbol of the button that shows and hides the sidebar.
    public var toggleSymbol: String { self == .right ? "sidebar.right" : "sidebar.left" }
}
