import CoreGraphics

/// The room Chrome's docked DevTools frontend leaves for the page it inspects. The frontend fills
/// the page's whole area (a pane's body in the browser window, the page area of a Little Window or
/// a Peek) and reports the hole in its layout that the page shows through
/// (`setInspectedPageBounds`); Cra lays the page's own window over that hole.
public struct DevToolsPlaceholder: Equatable, Sendable {
    /// The hole, in points from the frontend's top left.
    public var bounds: CGRect
    /// The frontend's size when it reported `bounds`.
    public var frontendSize: CGSize

    public init(bounds: CGRect, frontendSize: CGSize) {
        self.bounds = bounds
        self.frontendSize = frontendSize
    }

    /// The page's place in `area`, the rect the frontend fills, with the origin at the bottom left
    /// as AppKit has it. The hole keeps its distances from the area's edges, so while the area is
    /// being resized the page follows at once instead of waiting for the frontend's next layout.
    /// A hole that leaves nothing of the area gives the page all of it.
    public func pageRect(in area: CGRect) -> CGRect {
        let right = max(0, frontendSize.width - bounds.maxX)
        let bottom = max(0, frontendSize.height - bounds.maxY)
        let width = max(1, area.width - bounds.minX - right)
        let height = max(1, area.height - bounds.minY - bottom)
        let page = CGRect(x: area.minX + bounds.minX, y: area.minY + bottom, width: width, height: height).intersection(area)
        return page.isEmpty ? area : page
    }
}

/// Corners of a page's area. The page and its DevTools are windows of their own, which the window
/// around them doesn't clip: each rounds the corners it shares with the area and keeps the ones
/// where the two meet square.
public struct AreaCorners: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bottomLeft = AreaCorners(rawValue: 1 << 0)
    public static let bottomRight = AreaCorners(rawValue: 1 << 1)
    public static let topLeft = AreaCorners(rawValue: 1 << 2)
    public static let topRight = AreaCorners(rawValue: 1 << 3)
    public static let bottom: AreaCorners = [.bottomLeft, .bottomRight]

    /// The corners of `rect` that are corners of `area` as well (within half a point; both with
    /// the origin at the bottom left).
    public static func shared(by rect: CGRect, with area: CGRect) -> AreaCorners {
        func meets(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }
        var corners: AreaCorners = []
        let left = meets(rect.minX, area.minX), right = meets(rect.maxX, area.maxX)
        if meets(rect.minY, area.minY) {
            if left { corners.insert(.bottomLeft) }
            if right { corners.insert(.bottomRight) }
        }
        if meets(rect.maxY, area.maxY) {
            if left { corners.insert(.topLeft) }
            if right { corners.insert(.topRight) }
        }
        return corners
    }
}
