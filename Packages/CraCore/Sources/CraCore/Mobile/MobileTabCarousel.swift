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

    /// Where a drag that catches the row at `position` starts from. Past either end the row is at
    /// a third of the way the finger went (`position(start:translation:)`), so a catch there
    /// starts from the whole way, or the row would jump towards the end under the finger.
    public static func dragStart(caughtAt position: CGFloat, count: Int) -> CGFloat {
        let last = CGFloat(max(0, count - 1))
        if position < 0 { return position * 3 }
        if position > last { return last + (position - last) * 3 }
        return position
    }

    /// How fast the row moves, in cards a second (positive: towards newer tabs), at `position`
    /// under a finger moving `velocity` points a second: a third as fast past either end.
    public static func velocity(_ velocity: CGFloat, at position: CGFloat, count: Int, in screen: CGSize, sideInsets: (left: CGFloat, right: CGFloat) = (0, 0)) -> CGFloat {
        let speed = -velocity / pitch(in: screen, sideInsets: sideInsets)
        return position < 0 || position > CGFloat(max(0, count - 1)) ? speed / 3 : speed
    }

    /// How far ahead a let-go is projected: where the row would coast to, slowing at
    /// UIScrollView's fast rate (10 a second).
    public static let flickProjection: CGFloat = 0.1

    /// The card the row settles on when let go at `position` moving `velocity` points a second
    /// (negative: towards newer tabs), from a drag that began at `start`: the card nearest where
    /// it would coast to, and after a flick at least the next card from where the drag began.
    /// In Pri's Arc Search recording (25 Nov 2026) every flick moved one card, the hardest let go
    /// 61 % of the way there at 1,970 pt a second; rounding a 0.18 s projection up sent it three.
    public static func restingIndex(position: CGFloat, velocity: CGFloat, start: CGFloat? = nil, count: Int, in screen: CGSize, sideInsets: (left: CGFloat, right: CGFloat) = (0, 0)) -> Int {
        guard count > 0 else { return 0 }
        var target = (position - velocity * flickProjection / pitch(in: screen, sideInsets: sideInsets)).rounded()
        if abs(velocity) > 300 {
            let from = (start ?? position).rounded()
            target = velocity < 0 ? max(target, from + 1) : min(target, from - 1)
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

    /// The row coming to rest on a card once let go, as Arc Search's does (Pri's recording, 25 Nov
    /// 2026, 60 fps): it carries on at the finger's speed and slows into the card's place without
    /// passing it, the way a scroll view decelerates onto a snap point. The distance left shrinks
    /// by the same share every frame, at a rate of the speed it was let go at over the distance
    /// it had left: 0.70 a frame after a hard flick, and never slower than 0.85 a frame
    /// (10 a second), Arc's rate for a gentle let-go. Positions are in cards, as `placement`'s.
    public struct Settle: Equatable, Sendable {
        public static let slowestRate: CGFloat = 10

        public var from: CGFloat
        public var target: CGFloat
        /// How fast the distance left shrinks, per second.
        public var rate: CGFloat

        /// Let go at `from` moving `velocity` cards a second (positive: towards newer tabs).
        public init(from: CGFloat, velocity: CGFloat, target: CGFloat) {
            self.from = from
            self.target = target
            let distance = target - from
            rate = max(Self.slowestRate, distance == 0 ? 0 : velocity / distance)
        }

        public func position(after time: Double) -> CGFloat {
            target - (target - from) * CGFloat(exp(-Double(rate) * time))
        }

        /// Cards a second, towards the target.
        public func velocity(after time: Double) -> CGFloat {
            rate * (target - position(after: time))
        }

        /// Within a two-thousandth of a card: under a fifth of a point.
        public func isDone(after time: Double) -> Bool {
            abs(position(after: time) - target) < 0.0005
        }
    }

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
    /// after it, or to the one before when it was the newest. A row on its way to card
    /// `heading` after a flick still goes there, at its new place. Nil for a card not thrown.
    public mutating func finishThrow(_ id: UUID, position: CGFloat, heading: UUID? = nil) -> Gap? {
        guard thrown.remove(id) != nil, let index = cards.firstIndex(of: id) else { return nil }
        cards.remove(at: index)
        var position = position
        var target = position.rounded()
        if CGFloat(index) < target {
            target -= 1
            position -= 1
        }
        if let heading, let place = cards.firstIndex(of: heading) { target = CGFloat(place) }
        return Gap(position: position, settle: Int(min(max(0, target), CGFloat(max(0, cards.count - 1)))))
    }

    /// Where a row that was settling on card `id` goes once a card taken up from it is let go,
    /// the row at `position`: that card's place now, since a card thrown before it may have left
    /// meanwhile and moved it; the card nearest `position` if it has gone itself.
    public func resumeIndex(heading id: UUID, position: CGFloat) -> Int {
        if let index = cards.firstIndex(of: id) { return index }
        return Int(min(CGFloat(max(0, cards.count - 1)), max(0, position.rounded())))
    }
}
