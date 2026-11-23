import UIKit

/// A flick up on the tab button (#537, `BrowserGestures.swift`), from the hand's first move to the
/// arriving tab settling. `startGesture()` clears what belongs to one drag; what spans flicks (which
/// one is on screen, how to finish it, the status bar it set) carries over.
struct FlickState {
    // The page being left: its card, and the picture in it.
    var oldCard: UIView?
    var oldShot: UIView?
    /// How far that card has dropped off the page on its own clock, and how far the hand has
    /// taken it into its corner.
    var lift: CGFloat = 0
    var travel: CGFloat = 0

    // The tab in the hand.
    /// How far the drag has grown it, where the hand has it, and how far its shape has gone from
    /// the button's little card to the screen's own.
    var progress: CGFloat = 0
    var dragPoint = CGPoint.zero
    var aspect: CGFloat = 0
    /// The grip it was picked up by, and its lean: the angle, its speed, the lean the hand's
    /// sideways speed asks for, and when the hand last said so.
    var anchor = CGPoint.zero
    var swing: CGFloat = 0
    var swingRate: CGFloat = 0
    var swingTarget: CGFloat = 0
    var swingAt: CFTimeInterval = 0
    /// The coloured band it shows under the status bar, and that colour as hex.
    var band: UIView?
    var arrivingFill: String?

    /// The display link that drives the clocks above, and the frame update it calls.
    var link: CADisplayLink?
    var frameUpdate: (() -> Void)?

    // Across flicks.
    /// Which flick is on screen, so a settle that was interrupted leaves the next one alone, and
    /// how to finish the one settling at once.
    var generation = 0
    var end: (() -> Void)?
    /// The arriving tab's picture, left over its page while the page draws.
    var handoff: UIImageView?
    /// The fill the status bar follows while a tab flies in, and which tab that is, so the
    /// page's own band can take the bar back once it knows it.
    var statusFill: String?
    var statusPage: UUID?
    /// The arriving tab is flying in as the live page, so layout leaves its place alone.
    var incoming = false

    /// A new drag: everything of the last one's hand and cards goes, and this one is counted.
    mutating func startGesture() {
        oldCard?.removeFromSuperview()
        link?.invalidate()
        let carried = (generation &+ 1, end, handoff, statusFill, statusPage, incoming)
        self = FlickState()
        (generation, end, handoff, statusFill, statusPage, incoming) = carried
    }
}
