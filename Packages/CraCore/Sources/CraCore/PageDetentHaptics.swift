import CoreGraphics
import Foundation

/// When a sidebar swipe between pages (the spaces, and the Library before the first one) asks
/// the trackpad for a tick.
///
/// While the fingers move it ticks each time the page nearest the strip changes, as Arc 1.171's
/// `PageSwipeController` does (`performsPageDetentHaptics`, `lastDetentPageID`: the position
/// rounded half away from zero, checked only in its tracking loop, never in the settle or for a
/// wheel). That alone leaves a flick silent: it changes the page from a quarter of the way
/// across, so no detent is crossed (issue #260). So the release also ticks when the page the
/// swipe lands on is not the one that last ticked. Every page change then ends on exactly one
/// tick for the page it lands on, and a swipe that settles back where its last tick was says
/// nothing more.
///
/// Pages are counted from where the swipe began (0), + toward the next space; the Library is −1
/// from the first space.
public struct PageDetentHaptics: Sendable, Equatable {
    /// The page the last tick was for, or the swipe's starting page before any tick.
    public private(set) var page: Int

    public init(page: Int = 0) {
        self.page = page
    }

    /// The strip at `position` pages while the fingers move, `pages` being the ones it can land
    /// on (the rubber band past either end is not a page). Returns whether to tick.
    public mutating func track(position: CGFloat, pages: ClosedRange<Int>) -> Bool {
        guard position.isFinite else { return false }
        let nearest = Int(position.rounded(.toNearestOrAwayFromZero))
        guard pages.contains(nearest), nearest != page else { return false }
        page = nearest
        return true
    }

    /// The fingers lifted and the strip settles on page `target`. Returns whether to tick.
    public mutating func land(on target: Int) -> Bool {
        guard target != page else { return false }
        page = target
        return true
    }
}
