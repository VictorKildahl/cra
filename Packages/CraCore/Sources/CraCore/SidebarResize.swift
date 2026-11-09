import Foundation

/// One drag of the sidebar's edge, as Arc 1.17x runs it (issue #287;
/// `WindowLayoutController.handleSidebarResizePanGestureRecognizer:` and `SidebarResizeState`,
/// measured live on an offline Arc, 9 Nov 2026):
///
/// - The width is the start width plus the drag, rounded, so the edge stays under the pointer;
///   held inside `SidebarWidth` (164–500 pt).
/// - Under 82 pt the sidebar hides, there and then; dragged back over 82 while still held, it
///   comes back at 164.
/// - It snaps to 228 pt, the width where four 47 pt favorites fit (8 + 4 × 47 + 3 × 8 + 8), and
///   stays there until the drag is 14 pt past it either way. A drag that starts wider than 228
///   snaps as soon as it comes within 14 pt; one that starts narrower snaps once it reaches 228.
///   A fast drag (50 pt/s or more) goes by without snapping. Measured: slowly down from 260 it
///   reads 228 from 241 to 215 and 214 at 214; slowly up from 200 it follows to 228, reads 228
///   up to 241 and 242 at 242; a quick drag to 220 stays 220.
public struct SidebarResize: Equatable {
    public static let hideBelow: Double = 82
    public static let snapWidth: Double = 8 + 4 * 47 + 3 * 8 + 8
    public static let snapReach: Double = 14
    public static let snapMaxSpeed: Double = 50

    public enum Outcome: Equatable {
        case width(Double)
        case hidden
    }

    public let startWidth: Double
    private var canSnap: Bool
    private var snapped = false
    private var lastProposed: Double

    public init(startWidth: Double) {
        self.startWidth = startWidth
        canSnap = startWidth >= Self.snapWidth
        lastProposed = startWidth
    }

    /// The sidebar for a drag `translation` points from where it started (+ wider), moving at
    /// `speed` points a second.
    public mutating func update(translation: Double, speed: Double) -> Outcome {
        let proposed = (startWidth + translation).rounded()
        defer { lastProposed = proposed }
        if proposed < Self.hideBelow {
            snapped = false
            return .hidden
        }
        // Reaching the snap width from the narrow side arms the snap.
        if (lastProposed < Self.snapWidth) != (proposed < Self.snapWidth) || proposed == Self.snapWidth { canSnap = true }
        let near = abs(proposed - Self.snapWidth) < Self.snapReach
        if snapped, near { return .width(Self.snapWidth) }
        snapped = false
        if canSnap, near, abs(speed) < Self.snapMaxSpeed {
            snapped = true
            return .width(Self.snapWidth)
        }
        return .width(SidebarWidth.clamped(proposed))
    }

    /// True while the width is held at `snapWidth` (Arc plays a haptic tick when it takes hold).
    public var isSnapped: Bool { snapped }
}
