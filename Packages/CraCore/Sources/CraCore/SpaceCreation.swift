import CoreGraphics
import Foundation

/// The space being made in Arc's "Create a Space" page (Arc 1.173.1, 18 Nov 2026: a 2x still, a
/// 148 s screen recording read frame by frame, and its SwiftUI `SpaceCreationView`). The window
/// holds one while the page is up: the sidebar, the window's tint and the dock read it, and nothing
/// reaches the store until Create Space.
public struct SpaceCreationDraft: Equatable {
    public var title = ""
    /// `.none` until one is picked: the name field then shows its dashed "+".
    public var icon: SpaceIcon = .none
    public var theme: SpaceTheme
    /// Whether the theme was picked in Choose a Theme, not the one the page opened with.
    public var themeChosen = false
    /// nil is the Default profile.
    public var profile: UUID?
    /// The search engine's keyword for the command bar in this space; nil follows Settings. Cra's
    /// own (#306): Arc's page has no such row.
    public var searchEngine: String?

    public init(theme: SpaceTheme, profile: UUID?) {
        self.theme = theme
        self.profile = profile
    }

    /// Arc's Create Space button is on as soon as the name has a character, and off again when it
    /// has none; an icon or a theme isn't needed. Spaces alone don't count.
    public var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The name the space gets.
    public var createdTitle: String {
        Space.limitedTitle(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The dock's item for it, after the last space: a lit dot, and once a theme is chosen the
    /// picked icon (in the recording a picked emoji stayed a dot until the first swatch).
    public var dockMark: SpaceDockMark {
        guard themeChosen else { return .dot(diameter: SpaceDock.dotDiameter) }
        switch icon {
        case .emoji(let e): return .emoji(e)
        case .symbol(let s): return .symbol(s)
        case .image(let d): return .image(d)
        case .none: return .dot(diameter: SpaceDock.dotDiameter)
        }
    }
}

/// Where the page's parts go, measured in a 250 pt sidebar and given here from the page's own
/// top-left (the room between the sidebar's top row and its dock): Arc's page starts 42 pt under
/// the sidebar's top and ends 50 pt above its bottom.
public enum SpaceCreationLayout {
    /// The field, the rows and the button stand this far inside the sidebar's edges (13.6 pt).
    public static let inset: CGFloat = 13.5
    public static let pictureSize = CGSize(width: 64, height: 41)
    public static let pictureTop: CGFloat = 37
    public static let titleTop: CGFloat = 98
    public static let titleFont: CGFloat = 16
    public static let subtitleTop: CGFloat = 128
    public static let subtitleLine: CGFloat = 16.5
    public static let textFont: CGFloat = 13
    public static let fieldTop: CGFloat = 189
    public static let fieldHeight: CGFloat = 35
    public static let rowHeight: CGFloat = 36
    /// The field to the Profile row, and that row to Choose a Theme.
    public static let fieldGap: CGFloat = 6
    public static let rowGap: CGFloat = 7
    public static let cornerRadius: CGFloat = 6
    /// The dashed "+" in the field: 18 pt, 7.5 pt in, and the text after it.
    public static let iconSide: CGFloat = 18
    public static let iconInset: CGFloat = 7.5
    public static let textInset: CGFloat = 32.5
    /// The Profile row's pill is 21.5 pt tall; its (i) is 12.5 pt across, 9.5 pt from the row's end.
    public static let pillHeight: CGFloat = 21.5
    public static let infoSide: CGFloat = 12.5
    public static let infoInset: CGFloat = 9.5
    /// A row's glyph starts 9 pt in and its label 32 pt in.
    public static let rowGlyphInset: CGFloat = 9
    public static let rowLabelInset: CGFloat = 32
    public static let buttonHeight: CGFloat = 35.5
    /// Create Space ends 44 pt above the page's bottom, and Cancel is centred 23 pt above it.
    public static let buttonBottom: CGFloat = 44
    public static let cancelCentre: CGFloat = 23

    /// Arc's page lays itself out by the sidebar's width (its SwiftUI view compares the width with
    /// 227 and 190, 0x102602d4c and 0x102602ce8): over 227 pt the rows carry a glyph; at 227 pt and
    /// under they lose it and their label starts 16 pt in; at 190 pt and under the Profile row
    /// stacks, its label and (i) over a pill as wide as the row, and the subtitle wraps as it
    /// falls, three lines in a 165 pt sidebar, instead of breaking after "life,".
    public enum Density: Equatable, Sendable {
        case wide, medium, narrow

        public init(sidebarWidth: CGFloat) {
            self = sidebarWidth > 227 ? .wide : sidebarWidth > 190 ? .medium : .narrow
        }

        public var showsRowGlyphs: Bool { self == .wide }
        public var rowLabelInset: CGFloat { self == .wide ? SpaceCreationLayout.rowLabelInset : 16 }
        /// A row with a pill puts it under its label.
        public var stacksPills: Bool { self == .narrow }
        /// The subtitle breaks after "life," unless the sidebar is too narrow for that.
        public var subtitle: String {
            self == .narrow ? "Separate your tabs for life, work, projects, and more."
                            : "Separate your tabs for life,\nwork, projects, and more."
        }
    }

    /// A stacked row (a 165 pt sidebar, measured): 60 pt tall, its label centred 16 pt down, its
    /// pill 23 pt tall, 29 pt down and 8 pt inside the row's sides.
    public static let stackedRowHeight: CGFloat = 60
    public static let stackedLabelCentre: CGFloat = 16
    public static let stackedPillTop: CGFloat = 29
    public static let stackedPillHeight: CGFloat = 23
    public static let stackedPillInset: CGFloat = 8
    /// Side by side, the pill starts this far after its label.
    public static let pillGap: CGFloat = 7.5
    /// The field starts 28 pt under the subtitle's last line.
    public static let subtitleGap: CGFloat = 28

    public struct Frames: Equatable, Sendable {
        public let picture, title, subtitle, field, icon, profile, theme, search, create, cancel: CGRect
    }

    /// Every frame for a page of that size, origin top left; `subtitleLines` is how many lines the
    /// subtitle takes at that width, and `searchStacked` whether the Search Engine row's pill is
    /// under its label because it doesn't fit beside it (`pillFits`).
    public static func frames(in size: CGSize, subtitleLines: Int = 2, searchStacked: Bool = false) -> Frames {
        let density = Density(sidebarWidth: size.width)
        let wide = max(0, size.width - 2 * inset)
        let pillRow = density.stacksPills ? stackedRowHeight : rowHeight
        let subtitleHeight = CGFloat(max(1, subtitleLines)) * subtitleLine
        let field = CGRect(x: inset, y: subtitleTop + subtitleHeight + subtitleGap, width: wide, height: fieldHeight)
        let profile = CGRect(x: inset, y: field.maxY + fieldGap, width: wide, height: pillRow)
        let theme = CGRect(x: inset, y: profile.maxY + rowGap, width: wide, height: rowHeight)
        // Cra's Search Engine row follows Arc's two, laid out like the Profile row.
        let search = CGRect(x: inset, y: theme.maxY + rowGap, width: wide, height: searchStacked ? stackedRowHeight : pillRow)
        let create = CGRect(x: inset, y: size.height - buttonBottom - buttonHeight, width: wide, height: buttonHeight)
        return Frames(
            picture: CGRect(x: ((size.width - pictureSize.width) / 2).rounded(), y: pictureTop, width: pictureSize.width, height: pictureSize.height),
            title: CGRect(x: 0, y: titleTop, width: size.width, height: 20),
            subtitle: CGRect(x: inset, y: subtitleTop, width: wide, height: subtitleHeight),
            field: field,
            icon: CGRect(x: field.minX + iconInset, y: field.midY - iconSide / 2, width: iconSide, height: iconSide),
            profile: profile, theme: theme, search: search, create: create,
            cancel: CGRect(x: inset, y: size.height - cancelCentre - 10, width: wide, height: 20))
    }

    /// A pill in its row (the row's own coordinates), `labelEnd` being where the row's label ends
    /// and `fits` the pill's own width: after the label with a gap, no wider than what is left
    /// before `trailing` points kept at the row's end; or stacked, as wide as the row.
    public static func pillFrame(row: CGSize, labelEnd: CGFloat, fits: CGFloat, trailing: CGFloat, stacked: Bool) -> CGRect {
        if stacked {
            return CGRect(x: stackedPillInset, y: stackedPillTop, width: max(0, row.width - 2 * stackedPillInset), height: stackedPillHeight)
        }
        let x = labelEnd + pillGap
        return CGRect(x: x, y: (row.height - pillHeight) / 2, width: max(0, min(fits, row.width - x - trailing)), height: pillHeight)
    }

    /// Whether a pill `fits` wide has room beside a label ending at `labelEnd` in a row that wide.
    /// Cra's Search Engine names are long ("Default (Google)"), so that row stacks when it hasn't.
    public static func pillFits(rowWidth: CGFloat, labelEnd: CGFloat, fits: CGFloat, trailing: CGFloat) -> Bool {
        labelEnd + pillGap + fits + trailing <= rowWidth
    }

    /// The page needs this much height for the button not to reach the last row.
    public static let minimumHeight: CGFloat = fieldTop + fieldHeight + fieldGap + 3 * rowHeight + 2 * rowGap + 12 + buttonHeight + buttonBottom
}

/// Arc's animation from Create Space to the new space, about 2.5 s (the recording at 20 and 60 fps):
/// the controls fade out from the bottom up, the header's three cards tip over and come back as
/// one white card with the space's icon, which drops to the sidebar's middle and grows, a glow of
/// the theme pulses behind it, it fades, and the space appears.
public enum SpaceCreationAnimation {
    public typealias Span = ClosedRange<Double>
    /// The two buttons fade where they stand.
    public static let buttonsFade: Span = 0...0.17
    /// The rest leaves from the bottom up, 0.03 s apart in Arc's code: Choose a Theme (and Cra's
    /// Search Engine under it), Profile, the name, the subtitle, the title. Each slides `partSlide`
    /// points down over `partSlideTime`, slow at both ends (Arc's `easeInOut(duration: 0.4)`), and
    /// has faded by half way.
    public static let partSlide: CGFloat = 80
    public static let partSlideTime: Double = 0.4
    public static let partFade: Double = 0.2
    public static let themeRowStart: Double = 0.03
    public static let profileRowStart: Double = 0.06
    public static let fieldStart: Double = 0.09
    public static let subtitleStart: Double = 0.12
    public static let titleStart: Double = 0.15

    /// The picture and the card are two faces of one thing. Arc's code moves it half the page's
    /// height down and turns it half a turn about its level axis on one spring: response 0.8 s, no
    /// bounce, 0.3 s after the press. Its place and its angle keep step, edge-on half way down.
    public static let dropStart: Double = 0.30
    public static let dropResponse: Double = 0.8
    /// How far the eye is from the turning cards, in points (the far edge of Arc's card is 0.57 of
    /// its near edge at 75°, 0.82 at 17°).
    public static let perspective: CGFloat = 150
    /// The picture's height, and how tall the card stands at its tallest, edge-on: 1.4 of its own
    /// height. Measured in Arc: a 40 pt picture stretches to 109 pt as it turns away, and the 78 pt
    /// card comes round from there to its size. Their width never changes.
    public static let pictureHeight: CGFloat = 40
    public static let cardStretch: CGFloat = 1.4

    /// A spring with no bounce, `t` seconds in: 0 at rest, 1 where it settles.
    public static func settled(_ t: Double, response: Double) -> Double {
        guard t > 0, response > 0 else { return 0 }
        let w = 2 * Double.pi / response
        return 1 - (1 + w * t) * exp(-w * t)
    }

    /// How far along the way from the picture's place to the card's the cards are, 0 to 1.
    public static func drop(at t: Double) -> Double { settled(t - dropStart, response: dropResponse) }

    /// How far the cards have turned, in radians: 0 is the picture facing, π the card facing.
    public static func turn(at t: Double) -> Double { .pi * drop(at: t) }

    /// How tall the cards would stand if they faced you, `progress` of the way through the turn.
    public static func height(at progress: Double) -> CGFloat {
        let p = CGFloat(min(max(progress, 0), 1)), peak = cardStretch * cardSize.height
        return p <= 0.5 ? pictureHeight + (peak - pictureHeight) * p * 2 : peak - (peak - cardSize.height) * (p - 0.5) * 2
    }

    /// The picture is whole until it turns away, two fifths there edge-on, and gone as the card
    /// settles: its cards show behind the card's sides for a while.
    public static func pictureOpacity(at t: Double) -> Double {
        t <= 0.53 ? 1 - 0.6 * progress(0.40...0.53, at: t) : 0.4 * (1 - progress(0.53...1.0, at: t))
    }

    /// The card shows through the picture before it comes round, half there 0.4 s in and whole
    /// soon after it is edge-on; at the end it fades (`cardFade`).
    public static func cardOpacity(at t: Double) -> Double {
        let arriving = t <= 0.40 ? 0.5 * progress(0.31...0.40, at: t) : 0.5 + 0.5 * progress(0.40...0.60, at: t)
        return arriving * (1 - progress(cardFade, at: t))
    }
    public static let glow: Span = 1.31...1.51
    public static let cardFade: Span = 1.76...1.96
    /// The sidebar is empty from the card's fade until the space shows.
    public static let done: Double = 2.46
    public static let cardSize = CGSize(width: 62.5, height: 79)
    public static let cardRadius: CGFloat = 5
    public static let cardIcon: CGFloat = 38

    /// How far through `span` the animation is at `t`, 0 to 1.
    public static func progress(_ span: Span, at t: Double) -> Double {
        min(max((t - span.lowerBound) / (span.upperBound - span.lowerBound), 0), 1)
    }

    /// The card at rest: centred in a page of that size.
    public static func cardFrame(in size: CGSize) -> CGRect {
        CGRect(x: (size.width - cardSize.width) / 2, y: (size.height - cardSize.height) / 2, width: cardSize.width, height: cardSize.height)
    }
}

extension SpaceDock {
    /// While a space is being made the dock loses its Library and "+" buttons, its items stand
    /// 28 pt apart (33 pt before, six items in a 250 pt sidebar) and one more follows the last
    /// space for the new one.
    public static let creationCellWidth: CGFloat = 28

    /// The cells' widths with the new space's item at the end: `count` spaces and one more, each
    /// an even share of `room` and at most `creationCellWidth`.
    public static func widthsWhileCreating(count: Int, room: CGFloat) -> [CGFloat] {
        let n = count + 1
        let each = min(creationCellWidth, floor(max(0, room) / CGFloat(n) * 2) / 2)
        return Array(repeating: max(4, each), count: n)
    }
}

/// A swipe back on the Create a Space page: the page follows the fingers out the way it came in,
/// the space's column coming back beside it, and on the lift it leaves or goes back.
public enum SpaceCreationSwipe {
    /// How far out the page is, 0 (in place) to 1 (gone), with the fingers `travel` points to the
    /// right of where they began. A swipe the other way has nowhere to go.
    public static func pull(travel: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(travel / width, 0), 1)
    }

    /// Whether the page leaves when the fingers lift: past half way, or flicked out. `velocity` is
    /// in sidebar widths a second, rightwards; a flick is what turns a page between spaces (0.8).
    public static func leaves(pull: CGFloat, velocity: CGFloat) -> Bool {
        if abs(velocity) > 0.8 { return velocity > 0 && pull > 0 }
        return pull > 0.5
    }
}
