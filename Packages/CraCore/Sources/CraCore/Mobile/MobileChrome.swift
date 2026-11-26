import CoreGraphics
import Foundation

public enum MobileSideInsets {
    /// Only portrait-shaped windows with side insets use them: the closed Duo's status column, leaving ordinary iPhones unchanged.
    public static func applied(size: CGSize, safeLeft: CGFloat, safeRight: CGFloat) -> (left: CGFloat, right: CGFloat) {
        guard size.height > size.width, safeLeft > 0 || safeRight > 0 else { return (0, 0) }
        return (safeLeft, safeRight)
    }
}

/// The iPhone app's chrome, in points, measured from Arc Search on an iPhone 15 Pro
/// (393 × 852 pt, 2.2545 px per point in the 886 × 1920 recording; docs/ios.md says how).
public enum MobileSearchSheet {
    /// Sheet top to the search field.
    public static let topInset: CGFloat = 16
    public static let fieldHeight: CGFloat = 48
    /// The field's distance from each side of the sheet.
    public static let fieldSideInset: CGFloat = 16
    /// Field bottom to the first suggestion row.
    public static let rowsTopGap: CGFloat = 6
    public static let rowHeight: CGFloat = 56
    /// Arc Search shows four suggestions, and keeps room for them while the field is empty.
    public static let visibleRows = 4
    /// More suggestions wait below the four: scrolling brings them up into the field one by one
    /// (60fps.design's "Arc Search Scroll Morph" clip lists ten).
    public static let listedRows = 10
    /// Last row to the keyboard.
    public static let bottomInset: CGFloat = 8
    /// The sheet's top corners.
    public static let cornerRadius: CGFloat = 38
    /// The incognito toggle's glyph ends this far inside the field's right end (#654).
    public static let incognitoTrailingInset: CGFloat = 16.5
    /// The toggle's width with its word beside it: room for "Incognito" and the mask.
    public static let incognitoLabelledWidth: CGFloat = 130
    /// The gap between the incognito word and the mask.
    public static let incognitoLabelGap: CGFloat = 8.7

    public static func openFieldFrame(width: CGFloat, sideInsets: (left: CGFloat, right: CGFloat)) -> CGRect {
        CGRect(x: sideInsets.left + fieldSideInset, y: topInset,
               width: width - sideInsets.left - sideInsets.right - 2 * fieldSideInset, height: fieldHeight)
    }

    /// The sheet's height above the keyboard: 302 pt, whatever is typed.
    public static var height: CGFloat {
        topInset + fieldHeight + rowsTopGap + CGFloat(visibleRows) * rowHeight + bottomInset
    }

    /// Where the sheet's top edge sits in a screen `screenHeight` tall with the keyboard up.
    public static func top(screenHeight: CGFloat, keyboardHeight: CGFloat) -> CGFloat {
        screenHeight - keyboardHeight - height
    }

    /// Whether the keyboard going away closes the new tab drawer: only while the drawer grown from
    /// the bar is up and the keyboard had been up. The page menu's address editor stays.
    public static func closesOnKeyboardHide(isSearching: Bool, growsFromBar: Bool,
                                            keyboardWasUp: Bool, height: CGFloat) -> Bool {
        isSearching && growsFromBar && keyboardWasUp && height <= 0
    }

    /// The sheet with `rows` suggestion rows in view.
    public static func height(rows: Int) -> CGFloat {
        topInset + fieldHeight + rowsTopGap + CGFloat(rows) * rowHeight + bottomInset
    }

    /// How many suggestion rows fit between the keyboard and the top of the screen: four in
    /// portrait, fewer in landscape, where the keyboard leaves little room; the field always stays.
    public static func rowsInView(screenHeight: CGFloat, keyboardHeight: CGFloat, safeTop: CGFloat) -> Int {
        let room = screenHeight - keyboardHeight - safeTop - height(rows: 0)
        guard room > 0 else { return 0 }
        return min(visibleRows, Int(room / rowHeight))
    }

    /// The sheet's top edge with as many rows as fit.
    public static func top(screenHeight: CGFloat, keyboardHeight: CGFloat, safeTop: CGFloat) -> CGFloat {
        screenHeight - keyboardHeight - height(rows: rowsInView(screenHeight: screenHeight, keyboardHeight: keyboardHeight, safeTop: safeTop))
    }

    /// Where the sheet's top is while it opens. Pulled out of the pill and let go (#623), it stays
    /// where the finger left it, `heldAt`, until the keyboard's own animation takes it up, as in
    /// Arc Search (the reporter's 60 fps recording: straight up with the keyboard, settled in
    /// about 0.28 s). Laid out for no keyboard in the meantime, it sank towards the bar first.
    public static func openingTop(screenHeight: CGFloat, keyboardHeight: CGFloat, safeTop: CGFloat, heldAt: CGFloat?) -> CGFloat {
        heldAt ?? top(screenHeight: screenHeight, keyboardHeight: keyboardHeight, safeTop: safeTop)
    }

    /// The field's button at its right end (clear, incognito): 44 pt square, its centre 29.5 pt
    /// from the field's right end.
    public static func accessoryFrame(field: CGRect) -> CGRect {
        CGRect(x: field.maxX - 29.5 - 22, y: field.midY - 22, width: 44, height: 44)
    }

    /// The incognito toggle, whose glyph sits at its right edge: 16.5 pt from the field's right
    /// end whether it is off (the glyph alone) or on (the glyph with "Incognito" to its left,
    /// `labelledWidth` wide). Off, it used to end at the accessory's edge, 7.5 pt from the end,
    /// so the glyph sat hard against the field's rim (#654).
    public static func incognitoToggleFrame(field: CGRect, labelledWidth: CGFloat? = nil) -> CGRect {
        let accessory = accessoryFrame(field: field)
        let width = labelledWidth ?? accessory.width
        return CGRect(x: field.maxX - incognitoTrailingInset - width, y: accessory.minY, width: width, height: accessory.height)
    }

    /// The chrome's moves under way (the sheet, the bar, the page behind). The sheet is put away into the pill only
    /// once the last of them has ended. Closing, the keyboard sends two notices and each starts a move; the second
    /// moves nothing, so it ended at once and put the sheet away on the close's first frame, leaving the keyboard to
    /// go down on its own. Arc Search's field rides down on the keyboard into the + pill.
    public struct Settling: Equatable, Sendable {
        public private(set) var running = 0

        public init() {}

        public mutating func began() { running += 1 }

        /// One has ended: whether it was the last.
        public mutating func ended() -> Bool {
            running = max(0, running - 1)
            return running == 0
        }
    }
}

/// The bar at the bottom of a page: tabs, the pill that opens search, and the menu.
public enum MobileBottomBar {
    /// The bar above the home indicator's safe area.
    public static let height: CGFloat = 42
    /// The controls' centre below the bar's top edge. They sit low: with a 34 pt safe area the
    /// centre is 44.5 pt above the screen's bottom edge.
    public static let controlsCenterY: CGFloat = 31.5
    public static let pillSize = CGSize(width: 76, height: 39)
    /// The round buttons either side of the pill.
    public static let sideButtonDiameter: CGFloat = 35
    /// A side button's centre from its edge of the screen.
    public static let sideButtonCenterInset: CGFloat = 41
    /// How much white the bar lays over its material on a light page: a white page gives a nearly
    /// white bar rather than the material's fixed grey.
    public static let pageTint: CGFloat = 0.75
    /// The black the bar lays over its material in incognito, under the controls: a dark page has
    /// no white lift, so this is what makes the bar read black.
    public static let incognitoTint: CGFloat = 0.75
    /// The crossfade as a tab's light or dark page changes the bar's white overlay.
    public static let pageTintFade: TimeInterval = 0.2
    /// How much white the address field lays over the drawer on a light page, so the field reads
    /// slightly lighter than the surface behind it.
    public static let fieldLightPageWhite: CGFloat = 0.2
    /// How much white the address field lays over a dark page's drawer: a softer lift, still
    /// see-through and just lighter than the drawer.
    public static let fieldDarkPageWhite: CGFloat = 0.12

    public struct Frames: Equatable {
        public var bar: CGRect
        public var tabs: CGRect
        public var pill: CGRect
        public var menu: CGRect
    }

    /// The bar and its three controls in a view of `size` whose bottom safe area is `safeBottom`.
    public static func frames(in size: CGSize, safeBottom: CGFloat) -> Frames {
        let barHeight = height + safeBottom
        let bar = CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight)
        let centerY = bar.minY + controlsCenterY
        func circle(_ centerX: CGFloat) -> CGRect {
            CGRect(x: centerX - sideButtonDiameter / 2, y: centerY - sideButtonDiameter / 2,
                   width: sideButtonDiameter, height: sideButtonDiameter)
        }
        let pill = CGRect(x: (size.width - pillSize.width) / 2, y: centerY - pillSize.height / 2,
                          width: pillSize.width, height: pillSize.height)
        return Frames(bar: bar, tabs: circle(sideButtonCenterInset), pill: pill,
                      menu: circle(size.width - sideButtonCenterInset))
    }

    /// The bar's top edge with the bar `progress` of the way down its travel: at its open place,
    /// a bar above the safe area, at 0, and on the safe area's own line at 1, where only the
    /// strip along the home indicator is left on screen. Dragged, this is the page's bottom edge.
    /// With the display's `scale` it keeps to the pixel grid, so a step too small to show moves
    /// neither the bar nor the page's viewport under it.
    public static func top(in size: CGSize, safeBottom: CGFloat, progress: CGFloat, scale: CGFloat = 0) -> CGFloat {
        let open = frames(in: size, safeBottom: safeBottom).bar.minY
        let top = open + min(1, max(0, progress)) * height
        return scale > 0 ? (top * scale).rounded() / scale : top
    }

    /// How much of a page that runs on to the safe area's edge the bar covers with the bar
    /// `progress` of the way down: from the bar's top to that edge, its whole height open and
    /// nothing closed. The page is laid out clear of it frame by frame, so its visible bottom,
    /// and a sticky or fixed `bottom: 0` on it, is always the bar's top.
    public static func covered(in size: CGSize, safeBottom: CGFloat, progress: CGFloat, scale: CGFloat = 0) -> CGFloat {
        max(0, size.height - safeBottom - top(in: size, safeBottom: safeBottom, progress: progress, scale: scale))
    }

    /// Where a drag up brings back the previous tab rather than opening the tab row (#537): the
    /// tab button and the bar round it, from the screen's edge to halfway to the pill, the bar's
    /// whole height. The button's own 47 pt circle let a thumb that came down beside it open
    /// the tab row instead.
    public static func previousTabZone(in size: CGSize, safeBottom: CGFloat) -> CGRect {
        let frames = frames(in: size, safeBottom: safeBottom)
        return CGRect(x: 0, y: frames.bar.minY, width: (frames.tabs.maxX + frames.pill.minX) / 2, height: frames.bar.height)
    }

    /// Where a drag up pulls the search sheet out of the pill (#623), as in Arc Search: the pill
    /// with a thumb's slop either side, the bar's whole height. The rest of the bar's right half
    /// still drags the tab row up.
    public static func searchPullZone(in size: CGSize, safeBottom: CGFloat) -> CGRect {
        let frames = frames(in: size, safeBottom: safeBottom)
        let slop: CGFloat = 14
        return CGRect(x: frames.pill.minX - slop, y: frames.bar.minY, width: frames.pill.width + 2 * slop, height: frames.bar.height)
    }

    /// Where a tap brings the bar back after scrolling put it away: the home indicator's strip
    /// along the bottom edge, which pages leave empty. A swipe up from there is the system's
    /// and can open the app switcher, so a tap is the sure way back (#509). A phone without a
    /// home indicator has no such strip; its page runs to the edge and scrolling up is enough.
    public static func revealStrip(in size: CGSize, safeBottom: CGFloat) -> CGRect {
        CGRect(x: 0, y: size.height - safeBottom, width: size.width, height: safeBottom)
    }
}

/// The bottom bar's place between open and closed while a page is dragged. The bar moves with
/// the finger that scrolls the page, exactly as far as the finger, so the page's own offset never
/// moves it: a bounce at either end and the deceleration after the finger lifts move nothing.
/// Scrolling down hides it from the first point; scrolling up, or turning either way mid-drag,
/// first crosses a dead zone (`deadZone`), so a wobble of the finger leaves the bar alone. Let go,
/// the way the bar was last going picks the end.
/// Site Settings ▸ Collapse Bottom Bar decides per site whether the bar may move at all: with it
/// off the bar stays, however far the page scrolls. A page with nothing to scroll keeps its bar
/// too: hiding the bar would reveal nothing the page could scroll to.
public struct MobileBarCollapse: Equatable {
    /// The bar's travel from open to closed: its own height above the safe area. The finger
    /// travels as far to take it the whole way, so the bar moves exactly as far as the finger
    /// and the page above it, both ways.
    public static let travel = MobileBottomBar.height

    /// The least a page must run past its screen before hiding the bar is worth it: a page with
    /// only a little to scroll keeps its bar.
    public static let minimumScrollable: CGFloat = 100

    /// Whether a page `contentHeight` tall has more to scroll than the `pageHeight` its screen
    /// allows, by more than `minimumScrollable`. A page that fits, or has only a little to
    /// scroll, has nothing behind the bar worth hiding, so the bar stays.
    public static func scrolls(contentHeight: CGFloat, pageHeight: CGFloat) -> Bool {
        contentHeight > pageHeight + minimumScrollable
    }

    /// 0 with the bar open, 1 with it closed away; between the two while the finger drags it.
    public private(set) var progress: CGFloat = 0
    /// The direction the bar last moved in: true when it was closing. That is the end a release
    /// picks.
    private var lastTravelledClosed = false

    /// How far the finger goes before the bar starts back the way it came, or starts opening on
    /// a new touch, so a wobble or the start of a scroll up leaves the bar where it is.
    public static let deadZone: CGFloat = 32
    /// This bar's dead zone (`MobileBarCollapse.deadZone` unless set).
    public let deadZone: CGFloat
    /// The way the bar is going under this touch (true: closing), or nil before it has gone
    /// either way.
    private var direction: Bool?
    /// How far the finger has gone against `direction` (or, before it has one, towards opening)
    /// inside the dead zone.
    private var turn: CGFloat = 0
    /// Whether the touch now on the page has moved the bar at all.
    public private(set) var movedThisTouch = false

    /// How fast the finger must be going as it lets go, in points a second, for the flick to
    /// pick the bar's end by itself: a quick flick that never left the dead zone still sends the
    /// page scrolling, and the bar goes the same way.
    public static let flickSpeed: CGFloat = 300
    /// This bar's flick speed (`MobileBarCollapse.flickSpeed` unless set).
    public let flickSpeed: CGFloat

    public init(deadZone: CGFloat = MobileBarCollapse.deadZone, flickSpeed: CGFloat = MobileBarCollapse.flickSpeed) {
        self.deadZone = deadZone
        self.flickSpeed = flickSpeed
    }

    /// The bar is all there.
    public var isOpen: Bool { progress <= 0 }
    /// The bar is away, with only its strip along the safe area showing.
    public var isClosed: Bool { progress >= 1 }

    /// The least and the most the bar ever covers (`MobileBottomBar.covered`), given to WebKit up front (its minimum and
    /// maximum viewport insets): the page's `lvh` and `svh` hold still across the bar's travel,
    /// and only its visible viewport follows the bar.
    public static let viewportInsets: (least: CGFloat, most: CGFloat) = (0, travel)

    /// A finger came down on the page: its drag starts afresh, so closing moves the bar at once
    /// and opening waits the dead zone, whichever way the last touch went.
    public mutating func touchBegan() {
        direction = nil
        turn = 0
        movedThisTouch = false
    }

    /// The finger moved `drag` points, positive with the page moving down: closing the bar. The
    /// bar moves with the finger point for point, going the whole way over `travel` points of
    /// drag. Closing starts at once on a new touch; opening, and a turn either way mid-drag,
    /// waits until the finger has gone `deadZone` points that way, and only the travel beyond it
    /// moves the bar. `collapses` is the site's Collapse Bottom Bar switch; `scrolls` says the
    /// page has more to scroll than its screen shows, so a page that fits keeps its bar. Says
    /// whether the bar moved.
    @discardableResult
    public mutating func dragged(by drag: CGFloat, collapses: Bool, scrolls: Bool) -> Bool {
        // A site with the switch off never moves its bar; nor does a page with nothing to scroll.
        guard collapses, scrolls else {
            let moved = reveal()
            if moved { movedThisTouch = true }
            return moved
        }
        guard drag != 0 else { return false }
        let closing = drag > 0
        var moved = drag
        if direction == closing {
            // On the way it was going: a turn that didn't cross the dead zone is forgotten.
            turn = 0
        } else if direction == nil, closing {
            // Scrolling down hides the bar from the first point.
            direction = true
            turn = 0
        } else {
            // Opening on a new touch, or a turn: the dead zone first, then what lies beyond it.
            turn += drag
            guard abs(turn) > deadZone else { return false }
            moved = turn - (closing ? deadZone : -deadZone)
            direction = closing
            turn = 0
        }
        lastTravelledClosed = closing
        let place = min(1, max(0, progress + moved / Self.travel))
        guard place != progress else { return false }
        progress = place
        movedThisTouch = true
        return true
    }

    /// The finger let go after taking the bar somewhere: the direction it travelled in picks the
    /// end. Says which end it wants (true: closed), or nil when the bar is already there. The
    /// caller animates the bar, and the page's bottom edge with it, all the way to that end.
    public func released() -> Bool? {
        let closed = lastTravelledClosed
        guard progress != (closed ? 1 : 0) else { return nil }
        return closed
    }

    /// The finger let go at `velocity` points a second, positive with the page moving down. Quick
    /// enough (`flickSpeed`), the flick picks the end it points at, dead zone or not, and wins
    /// over the way the bar was going. Says which end (true: closed), or nil for a slow release,
    /// a bar already at that end, or one that stays: `collapses` and `scrolls` as for `dragged`.
    public func flicked(velocity: CGFloat, collapses: Bool, scrolls: Bool) -> Bool? {
        guard collapses, scrolls, abs(velocity) >= flickSpeed else { return nil }
        let closed = velocity > 0
        guard progress != (closed ? 1 : 0) else { return nil }
        return closed
    }

    /// The end the bar was last going towards (true: closed): where it settles when nothing
    /// else picks one, such as a touch the system takes away mid-drag.
    public var heading: Bool { lastTravelledClosed }

    /// The finger let go at `velocity` points a second (positive closing), `following` saying
    /// whether the bar was riding this touch. Says the end to walk the bar to, or nil to leave it
    /// (and any settle already playing) alone: a quick flick picks its own end; a touch that
    /// moved the bar settles the way it was going; one that rode the bar without moving it
    /// settles by its heading rather than leave it between its ends.
    public func ended(velocity: CGFloat, collapses: Bool, scrolls: Bool, following: Bool) -> Bool? {
        if let end = flicked(velocity: velocity, collapses: collapses, scrolls: scrolls) { return end }
        if movedThisTouch, let end = released() { return end }
        return following ? heading : nil
    }

    /// The bar's place while a snap plays: the caller drives it frame by frame.
    public mutating func setProgress(_ place: CGFloat) {
        progress = min(1, max(0, place))
    }

    /// A snap arrived: the bar sits at the end, and a release from there would pick it.
    public mutating func settle(atClosed closed: Bool) {
        progress = closed ? 1 : 0
        lastTravelledClosed = closed
    }

    /// The bar comes back at once: another tab, the tab row, the search sheet. Says whether it
    /// moved.
    @discardableResult
    public mutating func reveal() -> Bool {
        lastTravelledClosed = false
        touchBegan()
        guard progress != 0 else { return false }
        progress = 0
        return true
    }

    /// The page went to another address, on a site whose Collapse Bottom Bar is `collapses`.
    /// Says whether the bar comes back: with the switch off a bar that was away comes back; on a
    /// site that collapses it stays as it was.
    public func pageChanged(collapses: Bool) -> Bool {
        !collapses && !isOpen
    }

    /// The page's content settled: `scrolls` says it has more to scroll than its screen shows.
    /// A page that fits has nothing behind the bar to hide, so a bar that was away comes back.
    /// Says whether it comes back; the caller animates it.
    public func contentChanged(scrolls: Bool) -> Bool {
        !scrolls && !isOpen
    }

    /// Whether the page's view runs on under the bar (iOS 26) or ends at the bar's top. Under the
    /// bar, WebKit keeps the bar out of the page's containing block, `innerHeight`, `svh` and a
    /// fixed `bottom: 0`, but `100vh` and `100lvh` are the view's own height, so an app sized to
    /// the screen with them has its bottom under the bar, as Excel for the web's sheet tabs had. A
    /// page the bar never leaves gains nothing by running under it, so it ends at the bar's top,
    /// as every page did before iOS 26:
    /// a site whose Collapse Bottom Bar is off (`collapses`), and a page that has `loaded` with
    /// nothing to scroll (`scrolls`). A page still loading hasn't shown its height yet, and a
    /// bar that isn't all there keeps the page under it, so the view only shortens under an open
    /// bar, where the bar hides the change.
    public func pageRunsUnder(collapses: Bool, scrolls: Bool, loaded: Bool) -> Bool {
        guard isOpen else { return true }
        guard collapses else { return false }
        return !loaded || scrolls
    }
}
