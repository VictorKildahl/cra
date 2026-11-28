import CoreGraphics
import CraCore
import Testing

struct DownloadsTrayHoverTests {
    /// Three downloads (136 pt of rows) at the bottom of a 300 pt wide column, a now-playing card
    /// and the What's New banner under them, and the Library button 120 pt lower.
    let list = CGRect(x: 0, y: 500, width: 300, height: 136)
    let buttonTop: CGFloat = 756

    /// GitHub #575: on the way up from the Library button to a download, the pointer crosses the
    /// player (or the banner) and the list closed before it got there. While the list is open, the
    /// column between them keeps it open.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/575"))
    func theWayUpFromTheButtonKeepsTheListOpen() {
        // Over the player, just below the last download, and just above the button.
        for y: CGFloat in [700, list.maxY, buttonTop - 1] {
            #expect(DownloadsTrayHover.holds(CGPoint(x: 40, y: y), list: list, buttonTop: buttonTop, open: true))
        }
        #expect(DownloadsTrayHover.area(list: list, buttonTop: buttonTop, open: true) == CGRect(x: 0, y: 500, width: 300, height: 256))
    }

    /// Closed, the player is only the player: hovering it doesn't open the list.
    @Test func aClosedListIsOnlyItsRows() {
        #expect(!DownloadsTrayHover.holds(CGPoint(x: 40, y: 700), list: list, buttonTop: buttonTop, open: false))
        #expect(DownloadsTrayHover.holds(CGPoint(x: 40, y: 520), list: list, buttonTop: buttonTop, open: false))
        #expect(DownloadsTrayHover.area(list: list, buttonTop: buttonTop, open: false) == list)
    }

    /// The button itself, the dock beside it and the column's sides are not the list.
    @Test func theAreaEndsAtTheButtonAndTheColumn() {
        #expect(!DownloadsTrayHover.holds(CGPoint(x: 40, y: buttonTop), list: list, buttonTop: buttonTop, open: true))
        #expect(!DownloadsTrayHover.holds(CGPoint(x: 40, y: 499), list: list, buttonTop: buttonTop, open: true))
        #expect(!DownloadsTrayHover.holds(CGPoint(x: 300, y: 700), list: list, buttonTop: buttonTop, open: true))
        #expect(!DownloadsTrayHover.holds(CGPoint(x: -1, y: 700), list: list, buttonTop: buttonTop, open: true))
    }

    /// A button reaching into the rows (nothing between them) leaves the area as the rows.
    @Test func aButtonUnderTheRowsAddsNothing() {
        #expect(DownloadsTrayHover.area(list: list, buttonTop: 600, open: true) == list)
        #expect(DownloadsTrayHover.area(list: list, buttonTop: list.maxY, open: true) == list)
    }
}

struct NowPlayingHoverTests {
    /// GitHub #575: with the downloads list open, the player's cards grew over its rows as the pointer
    /// crossed them, title on title. They stay at rest until the list closes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/575"))
    func cardsStayRestingUnderAnOpenDownloadsList() {
        #expect(!NowPlayingHover.opens(overCards: true, cards: 1, downloadsListOpen: true))
        #expect(NowPlayingHover.opens(overCards: true, cards: 1, downloadsListOpen: false))
    }

    @Test func onlyAPointerOverCardsOpensThem() {
        #expect(!NowPlayingHover.opens(overCards: false, cards: 2, downloadsListOpen: false))
        #expect(!NowPlayingHover.opens(overCards: true, cards: 0, downloadsListOpen: false))
    }
}

/// GitHub #896: a download in the list that hovering the Library button opens looked the same under
/// the pointer and pressed as at rest, so it didn't look like something to pick.
struct DownloadsTrayRowTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/896"))
    func aRowLightsUpUnderThePointerAndLooksPickedWhilePressed() {
        #expect(DownloadsTrayRow.fill(open: true, hovered: false, pressed: false, canOpen: true) == .none)
        #expect(DownloadsTrayRow.fill(open: true, hovered: true, pressed: false, canOpen: true) == .hover)
        #expect(DownloadsTrayRow.fill(open: true, hovered: true, pressed: true, canOpen: true) == .pressed)
        // Dragged out past the row, it stays picked until the drag ends.
        #expect(DownloadsTrayRow.fill(open: true, hovered: false, pressed: true, canOpen: true) == .pressed)
    }

    /// A running, failed or cancelled download has nothing to open or drag: it only gets the hover.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/896"))
    func aRowWithNoFileOnlyHovers() {
        #expect(DownloadsTrayRow.fill(open: true, hovered: true, pressed: true, canOpen: false) == .hover)
    }

    /// Closing, the list fades with no row lit.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/896"))
    func aClosedListLightsNothing() {
        #expect(DownloadsTrayRow.fill(open: false, hovered: true, pressed: true, canOpen: true) == .none)
    }

    /// The lit card is what takes the click: the 40 pt thumbnail plus 4 pt above and below, on the
    /// 56 pt pitch, so two lit cards keep 8 pt apart.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/896"))
    func theCardIsTheRowsClickArea() {
        #expect(DownloadsTrayRow.height(thumbnail: 40) == 48)
        #expect(56 - DownloadsTrayRow.height(thumbnail: 40) == 8)
    }
}
