import CoreGraphics
import Foundation

/// The iPhone app's tab switcher: a row of page cards, the newest on the right and on top. The
/// card in focus sits left of centre, the next one overlaps its right edge, and older ones tuck
/// behind its left edge, a little smaller and dimmed. Measured from Arc Search on an iPhone 15 Pro
/// (393 × 852 pt): cards 273 × 555 pt centred 438.5 pt down, left edges at 10, 83 and 304 pt.
/// The first and the last card have no neighbour on one side and rest in the middle of the
/// screen instead (`endCentring`; Arc Search 1.50 on a 390 pt iPhone, 25 and 26 Nov 2026: 58 pt
/// in, where a card between them rests 83 pt in).
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

    /// Top-left like Arc Search and Safari, so a picture of another shape keeps the page's heading.
    public static func pictureFrame(image: CGSize, in area: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return area }
        let scale = max(area.width / image.width, area.height / image.height)
        return CGRect(origin: area.origin, size: CGSize(width: image.width * scale, height: image.height * scale))
    }

    /// Where a card sits when it is `relative` cards right of the one in focus (negative: left of
    /// it; fractions while the row is being dragged). `alone`: the only tab, which Arc Search puts in the
    /// middle of the screen (#816); a card with neighbours sits left of centre. `centring` is the
    /// row's `endCentring`.
    public static func placement(relative: CGFloat, in screen: CGSize, sideInsets: (left: CGFloat, right: CGFloat) = (0, 0),
                                 alone: Bool = false, centring: CGFloat = 0) -> Placement {
        let width = screen.width - sideInsets.left - sideInsets.right
        let size = cardSize(in: CGSize(width: width, height: screen.height))
        let middle = (width - size.width) / 2, leftOfCentre = width * 0.2112
        let focusLeft = sideInsets.left + (alone ? middle : leftOfCentre)
        let step = relative >= 0 ? pitch(in: screen, sideInsets: sideInsets) : width * 0.1858
        // At an end of the row the card in focus moves to the middle and the cards right of it
        // come along; the one behind it keeps its place at the left edge.
        let toMiddle = alone ? 0 : (middle - leftOfCentre) * centring * min(1, max(0, 1 + relative))
        let left = focusLeft + relative * step + toMiddle
        let top = screen.height * 0.5147 - size.height / 2
        let scale = relative >= 0 ? min(1.02, 1 + 0.0096 * relative) : max(0.9, 1 + 0.023 * relative)
        let dim = relative >= 0 ? 0 : min(maximumDim, -relative * maximumDim)
        return Placement(frame: CGRect(x: left, y: top, width: size.width, height: size.height), scale: scale, dim: dim)
    }

    /// How far the row at `position` is towards an end, where the card in focus rests in the
    /// middle of the screen: 1 on the first and the last card (and past them), 0 on every card
    /// between, and part of the way while the row moves from one to the other. With two cards
    /// both are ends, so it is 1 throughout. A lone card is `alone` instead.
    public static func endCentring(position: CGFloat, count: Int) -> CGFloat {
        guard count > 2 else { return count == 2 ? 1 : 0 }
        return min(1, max(0, 1 - position, position - CGFloat(count - 2)))
    }

    /// How far a drag moves the row by one card: the distance to the next card's place.
    public static func pitch(in screen: CGSize, sideInsets: (left: CGFloat, right: CGFloat) = (0, 0)) -> CGFloat {
        (screen.width - sideInsets.left - sideInsets.right) * 0.5626
    }

    /// The row's position while a finger drags it `translation` points from `start`: past either
    /// end it follows at a third of the speed.
    public static func position(start: CGFloat, translation: CGFloat, count: Int, in screen: CGSize, sideInsets: (left: CGFloat, right: CGFloat) = (0, 0)) -> CGFloat {
        let raw = start - translation / pitch(in: screen, sideInsets: sideInsets)
        let last = CGFloat(max(0, count - 1))
        if raw < 0 { return raw / 3 }
        if raw > last { return last + (raw - last) / 3 }
        return raw
    }

    /// The card the row settles on when let go at `position` moving `velocity` points a second
    /// (negative: towards newer tabs). A flick goes one card further than where it was let go.
    public static func restingIndex(position: CGFloat, velocity: CGFloat, count: Int, in screen: CGSize, sideInsets: (left: CGFloat, right: CGFloat) = (0, 0)) -> Int {
        guard count > 0 else { return 0 }
        var target = position.rounded()
        if abs(velocity) > 300 {
            let projected = position - velocity * 0.18 / pitch(in: screen, sideInsets: sideInsets)
            target = velocity < 0 ? max(target, projected.rounded(.up)) : min(target, projected.rounded(.down))
        }
        return Int(min(CGFloat(count - 1), max(0, target)))
    }

    /// How much of a card's title shows when it is `relative` cards right of the one in focus.
    /// Only the card in focus has its title, as in Arc Search (MacStories' v1.0 picture of the
    /// row): the cards behind it and in front of it show their favicon alone, so titles never run
    /// into each other (#816). A drag fades it out within half a card.
    public static func titleAlpha(relative: CGFloat) -> CGFloat {
        max(0, 1 - abs(relative) * 2)
    }

    /// The width of a card's title starting at `titleLeft`: it ends 16 pt before its own card's
    /// right edge, or before the left edge of the card in front of it (`nextCardLeft`), which
    /// would otherwise cover its end and put its favicon over the words (#816).
    public static func titleWidth(titleLeft: CGFloat, cardRight: CGFloat, nextCardLeft: CGFloat?) -> CGFloat {
        max(0, min(cardRight, nextCardLeft ?? cardRight) - titleEndGap - titleLeft)
    }

    /// The room left after a title.
    public static let titleEndGap: CGFloat = 16

    /// Whether a card dragged up by `translation` (negative: up) at `velocity` is thrown away.
    public static func closes(translation: CGFloat, velocity: CGFloat) -> Bool {
        translation < -120 || (translation < -30 && velocity < -700)
    }
}

/// The tab row's cards, oldest first, as cards are thrown out of it. A thrown card flies off
/// for a moment before the row closes its gap, and the next flick can come before it has gone.
/// So a flying card keeps its place in the row but no finger can take it again, and it leaves
/// by its id: a card thrown before it may land first and move it.
public struct MobileTabRow: Equatable, Sendable {
    /// Where the row goes once a card has left it.
    public struct Gap: Equatable, Sendable {
        /// The row's position straight away: a card gone from before it moves every later card
        /// one place, so it moves with them.
        public var position: CGFloat
        /// The card the row then settles on.
        public var settle: Int

        public init(position: CGFloat, settle: Int) {
            self.position = position
            self.settle = settle
        }
    }

    public private(set) var cards: [UUID]
    private var thrown: Set<UUID> = []

    public init(cards: [UUID]) { self.cards = cards }

    public func isThrown(_ id: UUID) -> Bool { thrown.contains(id) }

    /// Whether a finger can take the card: one in the row that isn't flying off.
    public func canTake(_ id: UUID) -> Bool { cards.contains(id) && !thrown.contains(id) }

    /// Throws the card out. False when a finger can't take it, so no card is thrown twice.
    @discardableResult
    public mutating func startThrow(_ id: UUID) -> Bool {
        guard canTake(id) else { return false }
        thrown.insert(id)
        return true
    }

    /// The thrown card has flown off and leaves the row, which is at `position`. A card gone
    /// from behind the focus leaves the focus on its card; the focused card hands it to the one
    /// after it, or to the one before when it was the newest. Nil for a card not thrown.
    public mutating func finishThrow(_ id: UUID, position: CGFloat) -> Gap? {
        guard thrown.remove(id) != nil, let index = cards.firstIndex(of: id) else { return nil }
        cards.remove(at: index)
        var position = position
        var target = position.rounded()
        if CGFloat(index) < target {
            target -= 1
            position -= 1
        }
        return Gap(position: position, settle: Int(min(max(0, target), CGFloat(max(0, cards.count - 1)))))
    }
}
