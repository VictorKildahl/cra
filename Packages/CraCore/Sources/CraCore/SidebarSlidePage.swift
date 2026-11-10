import CoreGraphics

/// An embedded page's frames in the window during a ⌘S slide; it should not move while its card does.
public struct SidebarSlidePage: Equatable, Sendable {
    private var minX: ClosedRange<CGFloat>?
    private var maxX: ClosedRange<CGFloat>?
    public private(set) var samples = 0

    public init() {}

    public mutating func record(_ frameInWindow: CGRect) {
        samples += 1
        minX = Self.widen(minX, frameInWindow.minX)
        maxX = Self.widen(maxX, frameInWindow.maxX)
    }

    public var drift: CGFloat {
        guard let minX, let maxX else { return 0 }
        return max(minX.upperBound - minX.lowerBound, maxX.upperBound - maxX.lowerBound)
    }

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
