import CoreGraphics
import Foundation

/// The iPhone app's tab switcher: a row of page cards, the newest on the right and on top. The
/// card in focus sits left of centre, the next one overlaps its right edge, and older ones tuck
/// behind its left edge, a little smaller and dimmed. Measured from Arc Search on an iPhone 15 Pro
/// (393 × 852 pt): cards 273 × 555 pt centred 438.5 pt down, left edges at 10, 83 and 304 pt.
public enum MobileTabCarousel {
    /// A card is the page at this scale.
    public static let cardScale: CGFloat = 0.694
    public static let cornerRadius: CGFloat = 17
    /// The favicon and title sit this far above a card.
    public static let headerGap: CGFloat = 8.5
    public static let headerIconSide: CGFloat = 18
    /// The header starts this far in from the card's left edge.
    public static let headerInset: CGFloat = 18
    /// How dark a card behind the one in focus gets.
    public static let maximumDim: CGFloat = 0.16

    public struct Placement: Equatable {
        /// The card's frame before `scale`, which is applied about its centre.
        public var frame: CGRect
        public var scale: CGFloat
        public var dim: CGFloat
    }

    public static func cardSize(in screen: CGSize) -> CGSize {
        CGSize(width: (screen.width * cardScale).rounded(), height: (screen.height * 0.6517).rounded())
    }

    /// Where a card sits when it is `relative` cards right of the one in focus (negative: left of
    /// it; fractions while the row is being dragged).
    public static func placement(relative: CGFloat, in screen: CGSize) -> Placement {
        let size = cardSize(in: screen)
        let focusLeft = screen.width * 0.2112
        let step = relative >= 0 ? pitch(in: screen) : screen.width * 0.1858
        let left = focusLeft + relative * step
        let top = screen.height * 0.5147 - size.height / 2
        let scale = relative >= 0 ? min(1.02, 1 + 0.0096 * relative) : max(0.9, 1 + 0.023 * relative)
        let dim = relative >= 0 ? 0 : min(maximumDim, -relative * maximumDim)
        return Placement(frame: CGRect(x: left, y: top, width: size.width, height: size.height), scale: scale, dim: dim)
    }

    /// How far a drag moves the row by one card: the distance to the next card's place.
    public static func pitch(in screen: CGSize) -> CGFloat {
        screen.width * 0.5626
    }

    /// The row's position while a finger drags it `translation` points from `start`: past either
    /// end it follows at a third of the speed.
    public static func position(start: CGFloat, translation: CGFloat, count: Int, in screen: CGSize) -> CGFloat {
        let raw = start - translation / pitch(in: screen)
        let last = CGFloat(max(0, count - 1))
        if raw < 0 { return raw / 3 }
        if raw > last { return last + (raw - last) / 3 }
        return raw
    }

    /// The card the row settles on when let go at `position` moving `velocity` points a second
    /// (negative: towards newer tabs). A flick goes one card further than where it was let go.
    public static func restingIndex(position: CGFloat, velocity: CGFloat, count: Int, in screen: CGSize) -> Int {
        guard count > 0 else { return 0 }
        var target = position.rounded()
        if abs(velocity) > 300 {
            let projected = position - velocity * 0.18 / pitch(in: screen)
            target = velocity < 0 ? max(target, projected.rounded(.up)) : min(target, projected.rounded(.down))
        }
        return Int(min(CGFloat(count - 1), max(0, target)))
    }

    /// Whether a card dragged up by `translation` (negative: up) at `velocity` is thrown away.
    public static func closes(translation: CGFloat, velocity: CGFloat) -> Bool {
        translation < -120 || (translation < -30 && velocity < -700)
    }
}
