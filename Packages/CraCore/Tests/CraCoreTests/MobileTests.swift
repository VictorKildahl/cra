import CoreGraphics
import CraCore
import Foundation
import Testing

/// The iPhone app's decisions: the chrome's measurements from Arc Search, the rows under the
/// search field, and the tabs with their archive.
struct MobileChromeTests {
    /// Arc Search on an iPhone 15 Pro: the sheet's top edge is 258.6 pt down with the 291 pt
    /// keyboard up, and the field starts 16 pt below it.
    @Test func searchSheetSitsWhereArcSearchPutsIt() {
        #expect(MobileSearchSheet.height == 302)
        #expect(MobileSearchSheet.top(screenHeight: 852, keyboardHeight: 291) == 259)
    }

    /// The sheet is put away only when the last of the chrome's moves has ended. Closing, the keyboard's second
    /// notice moves nothing and its move ends first, at once; it used to put the sheet away on the close's first frame.
    @Test func theSheetIsPutAwayWhenTheLastMoveEnds() {
        var settling = MobileSearchSheet.Settling()
        settling.began() // the keyboard's frame change: the sheet goes down into the pill
        settling.began() // its will-hide, which moves nothing
        let willHideEnded = settling.ended()
        #expect(!willHideEnded)
        #expect(settling.running == 1)
        let closeEnded = settling.ended()
        #expect(closeEnded)
        // An end with nothing running leaves it settled.
        let extraEnded = settling.ended()
        #expect(extraEnded)
        #expect(settling.running == 0)
    }

    /// In landscape the keyboard leaves little room: fewer rows, the field still on screen.
    @Test func theSheetKeepsItsFieldOnScreenInLandscape() {
        #expect(MobileSearchSheet.rowsInView(screenHeight: 852, keyboardHeight: 291, safeTop: 59) == 4)
        #expect(MobileSearchSheet.top(screenHeight: 852, keyboardHeight: 291, safeTop: 59) == 259)
        let rows = MobileSearchSheet.rowsInView(screenHeight: 402, keyboardHeight: 199, safeTop: 0)
        #expect(rows == 2)
        #expect(MobileSearchSheet.top(screenHeight: 402, keyboardHeight: 199, safeTop: 0) >= 0)
        #expect(MobileSearchSheet.rowsInView(screenHeight: 300, keyboardHeight: 290, safeTop: 0) == 0)
    }

    /// The incognito glyph keeps the same room to the field's right end off and on: before, off,
    /// it sat 7.5 pt from the end and on (with its label) 16.5 pt (#654).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/654")) func theIncognitoGlyphKeepsItsPlaceOffAndOn() {
        let field = CGRect(x: 16, y: 16, width: 361, height: 48)
        let off = MobileSearchSheet.incognitoToggleFrame(field: field)
        let on = MobileSearchSheet.incognitoToggleFrame(field: field, labelledWidth: MobileSearchSheet.incognitoLabelledWidth)
        #expect(off.maxX == on.maxX)
        #expect(field.maxX - off.maxX == MobileSearchSheet.incognitoTrailingInset)
        #expect(off.width == 44 && on.width == MobileSearchSheet.incognitoLabelledWidth)
        #expect(off.midY == field.midY && on.midY == field.midY)
        let accessory = MobileSearchSheet.accessoryFrame(field: field)
        #expect(field.maxX - accessory.midX == 26.5, "3 pt nearer the end than Arc Search's 29.5")
        #expect(MobileSearchSheet.incognitoLabelledWidth == 130)
        #expect(MobileSearchSheet.incognitoLabelGap == 6.7, "2 pt closer to the mask than the 8.7 measured")
        // The 28 pt mask, right-aligned, sits a little left of the accessory's centre.
        #expect(abs((off.maxX - 14) - accessory.midX) <= 3.5)
    }

    /// A sheet let go halfway up stays there until the keyboard comes, then goes where the
    /// keyboard puts it; without the hold it aimed at the keyboard-less spot, lower down (#623).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/623")) func aLetGoSheetWaitsForTheKeyboardWhereItWasLeft() {
        let held = MobileSearchSheet.openingTop(screenHeight: 852, keyboardHeight: 34, safeTop: 59, heldAt: 420)
        #expect(held == 420)
        let keyboardless = MobileSearchSheet.openingTop(screenHeight: 852, keyboardHeight: 34, safeTop: 59, heldAt: nil)
        #expect(keyboardless > 420, "what it used to aim at while the keyboard was on its way: lower")
        #expect(MobileSearchSheet.openingTop(screenHeight: 852, keyboardHeight: 291, safeTop: 59, heldAt: nil) == 259, "with the keyboard up, Arc's place")
    }

    /// The empty field shows the mic and the incognito toggle, a field with text the clear button;
    /// in incognito only the toggle goes for it, as there is no mic.
    @Test func theFieldsEndSwapsItsButtonsForTheClearButtonOnceThereIsText() {
        #expect(MobileSearchSheet.accessories(hasText: false, incognito: false) == [.mic, .incognito])
        #expect(MobileSearchSheet.accessories(hasText: true, incognito: false) == .clear)
        #expect(MobileSearchSheet.accessories(hasText: false, incognito: true) == .incognito)
        #expect(MobileSearchSheet.accessories(hasText: true, incognito: true) == .clear)
    }

    /// The Browse for Me chip is as wide as its title plus its padding either side, more than Arc
    /// Search's fixed 100.5 pt gave it.
    @Test func theBrowseChipFitsItsTitleWithRoomEitherSide() {
        let size = MobileSearchSheet.browseChipSize(titleWidth: 89.2)
        #expect(size.width == 114 && size.height == MobileSearchSheet.browseChipHeight)
        #expect(MobileSearchSheet.browseChipPadding > (100.5 - 89.2) / 2)
    }

    /// A second keystroke leaves the same buttons showing, so whatever is moving carries on. It
    /// used to snap every button to its end, cutting the swap short after two quick characters.
    @Test func aSecondKeystrokeLeavesTheSwapRunning() {
        let typed = MobileSearchSheet.accessories(hasText: true, incognito: false)
        let empty = MobileSearchSheet.accessories(hasText: false, incognito: false)
        #expect(MobileSearchSheet.accessoryChange(from: typed, to: typed, canAnimate: true) == .keep)
        #expect(MobileSearchSheet.accessoryChange(from: empty, to: typed, canAnimate: true) == .swap)
        #expect(MobileSearchSheet.accessoryChange(from: typed, to: empty, canAnimate: true) == .swap)
        #expect(MobileSearchSheet.accessoryChange(from: empty, to: .incognito, canAnimate: true) == .mic)
        #expect(MobileSearchSheet.accessoryChange(from: nil, to: empty, canAnimate: true) == .snap)
        #expect(MobileSearchSheet.accessoryChange(from: empty, to: typed, canAnimate: false) == .snap)
    }

    /// In incognito the word stays beside the clear button, so typed text stops short of it.
    @Test func typedTextStopsShortOfTheIncognitoWord() {
        let plain = MobileSearchSheet.textTrailingReserve(incognitoWordWidth: nil, maskWidth: 28)
        let incognito = MobileSearchSheet.textTrailingReserve(incognitoWordWidth: 52, maskWidth: 28)
        #expect(plain == 49)
        #expect(incognito >= MobileSearchSheet.incognitoTrailingInset + 28 + MobileSearchSheet.incognitoLabelGap + 52)
    }

    /// A drawer pulled up and let go heads for its open place at once instead of waiting where the
    /// finger left it for the keyboard, which froze it for a moment after a flick.
    @Test func aDrawerLetGoHeadsForItsPlaceBeforeTheKeyboardComes() {
        let open = MobileSearchSheet.openingTop(screenHeight: 852, keyboardHeight: 291, safeTop: 59, heldAt: nil)
        #expect(MobileSearchSheet.releasedTop(screenHeight: 852, expectedKeyboard: 291, keyboardSeen: true,
                                              safeTop: 59, releasedAt: 600) == open, "up from low down")
        #expect(MobileSearchSheet.releasedTop(screenHeight: 852, expectedKeyboard: 291, keyboardSeen: true,
                                              safeTop: 59, releasedAt: 150) == open, "down from a long pull")
        // No keyboard seen yet: up to the place without one, never down.
        let bare = MobileSearchSheet.openingTop(screenHeight: 852, keyboardHeight: 34, safeTop: 59, heldAt: nil)
        #expect(MobileSearchSheet.releasedTop(screenHeight: 852, expectedKeyboard: 34, keyboardSeen: false,
                                              safeTop: 59, releasedAt: 700) == min(bare, 700))
        #expect(MobileSearchSheet.releasedTop(screenHeight: 852, expectedKeyboard: 34, keyboardSeen: false,
                                              safeTop: 59, releasedAt: 300) == 300)
    }

    /// The same phone's bar: 76 pt tall, pill 76 × 39 centred 44.5 pt above the bottom edge,
    /// round buttons 35 pt wide centred 41 pt from each side.
    @Test func bottomBarOnAnIPhone15Pro() {
        let frames = MobileBottomBar.frames(in: CGSize(width: 393, height: 852), safeBottom: 34)
        #expect(frames.bar == CGRect(x: 0, y: 776, width: 393, height: 76))
        #expect(frames.pill == CGRect(x: 158.5, y: 788, width: 76, height: 39))
        #expect(frames.pill.midY == 807.5)
        #expect(frames.tabs == CGRect(x: 23.5, y: 790, width: 35, height: 35))
        #expect(frames.menu == CGRect(x: 334.5, y: 790, width: 35, height: 35))
        // The right side button and the new tab pill share one vertical centre.
        #expect(frames.pill.midY == frames.tabs.midY)
        #expect(frames.pill.midY == frames.menu.midY)
    }

    /// The bar's controls take the light bar's dark grey ink over a light app or a light page, and
    /// never over incognito's black bar, the floating home or tab-row buttons, or a dark app's
    /// drawer.
    @Test func theBarsControlsTakeTheLightChromeOnlyOverALightBar() {
        func light(dark: Bool = false, page: Bool = false, incognito: Bool = false,
                   floats: Bool = false, overDrawer: Bool = false) -> Bool {
            MobileBottomBar.lightChrome(darkMode: dark, pageIsLight: page, incognito: incognito,
                                        floats: floats, overDrawer: overDrawer)
        }
        #expect(light(), "a light app")
        #expect(light(page: true), "a light page")
        #expect(light(dark: true, page: true), "a light page in a dark app")
        #expect(!light(dark: true), "a dark page in a dark app")
        #expect(light(overDrawer: true), "the light app's drawer")
        #expect(!light(dark: true, page: true, overDrawer: true), "a dark app's drawer over a light page")
        #expect(!light(incognito: true), "incognito's black bar in a light app")
        #expect(!light(page: true, incognito: true, overDrawer: true), "incognito's drawer over a light page")
        #expect(!light(floats: true), "the buttons floating over the home or the tab row")
    }

    /// The page is light when the status bar's text over it is dark; with no band, the app's own
    /// appearance decides.
    @Test func thePageIsLightWhenTheStatusBarTextIsDark() {
        #expect(MobileBottomBar.pageIsLight(statusBarFill: "#ffffff", darkMode: true))
        #expect(!MobileBottomBar.pageIsLight(statusBarFill: "#000000", darkMode: false))
        #expect(MobileBottomBar.pageIsLight(statusBarFill: nil, darkMode: false))
        #expect(!MobileBottomBar.pageIsLight(statusBarFill: nil, darkMode: true))
    }

    /// The bar's material: the drawer's while it is out, a thick light one over a light page (not
    /// in incognito, whose black covers it), the thinnest otherwise.
    @Test func theBarsMaterialFollowsThePageAndTheDrawer() {
        #expect(MobileBottomBar.material(drawerShowing: false, pageIsLight: false, incognito: false) == .page)
        #expect(MobileBottomBar.material(drawerShowing: false, pageIsLight: true, incognito: false) == .lightPage)
        #expect(MobileBottomBar.material(drawerShowing: false, pageIsLight: true, incognito: true) == .page)
        #expect(MobileBottomBar.material(drawerShowing: true, pageIsLight: true, incognito: false) == .drawer)
        #expect(MobileBottomBar.material(drawerShowing: true, pageIsLight: false, incognito: true) == .drawer)
    }

    /// The drawer's address field is frosted and lays a little white over its material, over a
    /// light page or a dark one but not in incognito, and over the tab switcher one lift
    /// in either appearance; the page menu's address editor keeps the
    /// sheet's own field.
    @Test func theDrawersFieldIsLiftedOverEitherPageAndTheTabRowButNotInIncognito() {
        typealias Style = MobileSearchSheet.FieldStyle
        #expect(Style(growsFromBar: false, pageIsLight: true) == .standard)
        #expect(Style(growsFromBar: true, pageIsLight: true) == .lightPage)
        #expect(Style(growsFromBar: true, pageIsLight: false) == .darkPage)
        #expect(Style.standard.whiteLift(incognito: false) == nil && !Style.standard.isFrosted)
        let light = Style.lightPage.whiteLift(incognito: false) ?? 0, dark = Style.darkPage.whiteLift(incognito: false) ?? 0
        #expect(light > 0 && light < 0.5 && dark > 0 && dark < 0.5, "a lift, still see-through")
        #expect(Style.lightPage.whiteLift(incognito: true) == 0 && Style.darkPage.whiteLift(incognito: true) == 0,
                "incognito's field is the material alone")
        #expect(Style.standard.whiteLift(incognito: true) == nil, "the page menu's field keeps its own")
        let row = Style.darkPage.whiteLift(incognito: false, overTabRow: true) ?? 0
        #expect(row == Style.lightPage.whiteLift(incognito: false, overTabRow: true), "the same in either appearance")
        #expect(row > dark && row < light, "over the tab switcher, between a dark page's and a light page's")
        #expect(Style.darkPage.whiteLift(incognito: true, overTabRow: true) == 0, "incognito still has none")
    }

    /// The mic sits left of the incognito mask, clear of it.
    @Test func theMicSitsLeftOfTheIncognitoMask() {
        let field = CGRect(x: 16, y: 16, width: 361, height: 48)
        let mic = MobileSearchSheet.micFrame(field: field)
        #expect(mic.midY == field.midY)
        // The 28 pt mask is drawn at the toggle's right edge; the mic's 44 pt box ends before it.
        #expect(mic.maxX < MobileSearchSheet.incognitoToggleFrame(field: field).maxX - 28)
    }

    @Test func bottomBarWithoutAHomeIndicator() {
        let frames = MobileBottomBar.frames(in: CGSize(width: 375, height: 667), safeBottom: 0)
        #expect(frames.bar.height == 42)
        #expect(frames.pill.midX == 187.5)
    }

    /// Dragged down, the bar's top edge runs from its open place to the safe area's line: 776 to
    /// 818 on this phone, its own 42 pt of travel, and no further.
    @Test func theBarsTopEdgeRidesItsTravel() {
        let size = CGSize(width: 393, height: 852)
        #expect(MobileBottomBar.top(in: size, safeBottom: 34, progress: 0) == 776)
        #expect(MobileBottomBar.top(in: size, safeBottom: 34, progress: 0.5) == 797)
        #expect(MobileBottomBar.top(in: size, safeBottom: 34, progress: 1) == 818)
        #expect(MobileBottomBar.top(in: size, safeBottom: 34, progress: 2) == 818, "clamped")
        #expect(MobileBottomBar.top(in: size, safeBottom: 34, progress: -1) == 776, "clamped")
    }

    /// With the bar scrolled away, a tap on the home indicator's strip brings it back (#509).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/509"))
    func aTapUnderThePageBringsTheBarBack() {
        let strip = MobileBottomBar.revealStrip(in: CGSize(width: 393, height: 852), safeBottom: 34)
        #expect(strip == CGRect(x: 0, y: 818, width: 393, height: 34))
        #expect(MobileBottomBar.revealStrip(in: CGSize(width: 375, height: 667), safeBottom: 0).isEmpty)
    }
}

/// The search sheet coming up from the pill, matched to Arc Search at 60 fps.
struct MobileSearchMotionTests {
    /// The sheet sets off on the tap, eased out, and the keyboard takes it over; it no longer waits for the keyboard.
    @Test func theSheetSetsOffBeforeTheKeyboardComes() {
        #expect(MobileSearchMotion.leadDuration == 0.25)
        #expect(MobileSearchMotion.settleDuration == 0.35)
    }

    /// The pill's plus keeps to the field's leading end as it grows, the placeholder to its right; it no longer
    /// sits in the field's middle over the placeholder.
    @Test func thePlusKeepsToTheLeadingEndAsThePillGrows() {
        let pill: CGFloat = 76
        #expect(MobileSearchMotion.plusCenter(closedWidth: pill, openness: 0) == 38)
        #expect(MobileSearchMotion.plusCenter(closedWidth: pill, openness: 1) == 2)
        #expect(MobileSearchMotion.plusCenter(closedWidth: pill, openness: 0.5) == 20)
        // Open, the text starts where the field's always has; on the way, right of the plus.
        #expect(MobileSearchMotion.textInset(closedWidth: pill, openness: 1) == 24.5)
        for step in 0...10 {
            let open = CGFloat(step) / 10
            let gap = MobileSearchMotion.textInset(closedWidth: pill, openness: open)
                - MobileSearchMotion.plusCenter(closedWidth: pill, openness: open)
            #expect(abs(gap - 22.5) < 0.001)
        }
        #expect(MobileSearchMotion.plusCenter(closedWidth: pill, openness: 2) == 2)
    }

    /// The sheet is solid early, its field's buttons come late, under a finger and in an animated move.
    @Test func theSurfaceIsSolidEarlyAndTheButtonsComeLate() {
        let surface = MobileSearchMotion.surfaceSpan, buttons = MobileSearchMotion.accessorySpan
        #expect(MobileSearchMotion.opacity(openness: 0, over: surface) == 0)
        #expect(MobileSearchMotion.opacity(openness: 0.25, over: surface) == 1)
        #expect(MobileSearchMotion.opacity(openness: 0.6, over: surface) == 1)
        #expect(MobileSearchMotion.opacity(openness: 0.5, over: buttons) == 0)
        #expect(MobileSearchMotion.opacity(openness: 0.75, over: buttons) == 0.5)
        #expect(MobileSearchMotion.opacity(openness: 1, over: buttons) == 1)
        // Opening: the surface in the first quarter of the move, the buttons in the second half.
        #expect(MobileSearchMotion.fadeWindow(from: 0, to: 1, over: surface) == 0...0.25)
        #expect(MobileSearchMotion.fadeWindow(from: 0, to: 1, over: buttons) == 0.5...1)
        // Closing: the buttons go first, the surface stays solid until the last quarter.
        #expect(MobileSearchMotion.fadeWindow(from: 1, to: 0, over: buttons) == 0...0.5)
        #expect(MobileSearchMotion.fadeWindow(from: 1, to: 0, over: surface) == 0.75...1)
        // The new tab drawer's buttons come in with its field, from the start of its opening.
        let drawer = MobileSearchMotion.accessorySpan(growsFromBar: true)
        #expect(MobileSearchMotion.fadeWindow(from: 0, to: 1, over: drawer) == 0...1)
        #expect(MobileSearchMotion.opacity(openness: 0.5, over: drawer) == 0.5)
        #expect(MobileSearchMotion.accessorySpan(growsFromBar: false) == buttons, "the page menu's sheet keeps Arc Search's")
        // From halfway open, the surface is already solid: nothing left to fade.
        #expect(MobileSearchMotion.fadeWindow(from: 0.5, to: 1, over: surface) == 0...0)
        #expect(MobileSearchMotion.fadeWindow(from: 1, to: 1, over: surface) == 0...0)
    }

    /// The new tab drawer's tabs and menu buttons leave slowly over its pull, and its top corners
    /// stay square until the drawer is fully open.
    @Test func theDrawerLetsItsSideButtonsGoAndRoundsItsTop() {
        #expect(MobileNewTabDrawer.controlsFadeDistance == 120)
        #expect(MobileNewTabDrawer.controlsOpacity(reach: 0) == 1)
        #expect(MobileNewTabDrawer.controlsOpacity(reach: 60) == 0.5)
        #expect(MobileNewTabDrawer.controlsOpacity(reach: 120) == 0)
        #expect(MobileNewTabDrawer.controlsOpacity(reach: 240) == 0)
        #expect(MobileNewTabDrawer.controlsOpacity(reach: -10) == 1, "above the bar is still in place")
        #expect(MobileNewTabDrawer.cornerRadius(openness: 0) == 0)
        #expect(MobileNewTabDrawer.cornerRadius(openness: 0.5) == MobileSearchSheet.cornerRadius / 2)
        #expect(MobileNewTabDrawer.cornerRadius(openness: 1) == MobileSearchSheet.cornerRadius)
        #expect(MobileNewTabDrawer.cornerRadius(openness: 2) == MobileSearchSheet.cornerRadius, "no more than the sheet's")
        #expect(MobileNewTabDrawer.cornerRadius(openness: -0.5) == 0)
        #expect(MobileSearchMotion.incognitoBlink < MobileSearchMotion.settleDuration, "a blink, not a close")
        #expect(MobileSearchMotion.incognitoBlinkStagger < MobileSearchMotion.incognitoBlink, "a roll, not a second blink")
        #expect(MobileSearchMotion.incognitoLabelSlide > MobileSearchMotion.incognitoBlink)
    }

    /// The open field's hairline is there only once it is all but open, so the field shrinking
    /// into the pill carries no rim.
    @Test func theFieldsEdgeGoesAsSoonAsItStartsToClose() {
        #expect(MobileSearchMotion.fieldEdgeOpacity(openness: 1) == 1)
        #expect(abs(MobileSearchMotion.fieldEdgeOpacity(openness: 0.99) - 0.5) < 0.001)
        #expect(MobileSearchMotion.fieldEdgeOpacity(openness: 0.98) == 0)
        #expect(MobileSearchMotion.fieldEdgeOpacity(openness: 0.5) == 0)
    }
}

/// The new tab drawer's field and list while a finger holds it, and when it moves on its own.
struct MobileNewTabDrawerTests {
    @Test func aPullUpKeepsThePlusAndADragDownKeepsTheFieldUntilTheFingerLetsGo() {
        var drawer = MobileNewTabDrawer()
        drawer.growsFromBar = true
        #expect(drawer.fieldOpenness(isSearching: false, pulled: 0.4) == 0.4, "no hold: the field follows the pull")
        drawer.fieldHold = .closed
        #expect(drawer.fieldOpenness(isSearching: false, pulled: 0.4) == 0, "pulled up: still a plus")
        drawer.fieldHold = .open
        #expect(drawer.fieldOpenness(isSearching: false, pulled: 0.4) == 1, "dragged down: still the field")
        #expect(drawer.fieldOpenness(isSearching: true, pulled: nil) == 1, "searching: open, whatever the hold")
        drawer.fieldHold = .closed
        #expect(drawer.fieldOpenness(isSearching: true, pulled: nil) == 1)
        drawer.fieldHold = .none
        #expect(drawer.fieldOpenness(isSearching: false, pulled: nil) == 0, "closed into the bar")
    }

    /// Over the page the bar's material stays the drawer's background all the way down; over the
    /// home or the tab row, a drawer let go takes it down with it instead of leaving it behind
    /// until the drawer has settled.
    @Test func aDrawerLetGoOverTheTabRowTakesTheMaterialDownWithIt() {
        #expect(MobileNewTabDrawer.materialOpacity(floats: false, letGo: true, openness: 0.3) == 1, "over a page")
        #expect(MobileNewTabDrawer.materialOpacity(floats: true, letGo: false, openness: 0.3) == 1, "still held")
        #expect(MobileNewTabDrawer.materialOpacity(floats: true, letGo: true, openness: 0.3) == 0.3)
        #expect(MobileNewTabDrawer.materialOpacity(floats: true, letGo: true, openness: 0) == 0, "back in the bar")
        #expect(MobileNewTabDrawer.materialOpacity(floats: true, letGo: true, openness: 1.2) == 1)
    }

    /// In dark mode the drawer's material takes a faint grey haze so it reads frosted; light mode
    /// and incognito take none.
    @Test func theDrawerIsHazedInDarkModeOnly() {
        let haze = MobileNewTabDrawer.haze(darkMode: true, incognito: false)
        #expect(haze > 0 && haze < 0.8, "a haze, the blur still showing")
        #expect(MobileNewTabDrawer.haze(darkMode: false, incognito: false) == 0)
        #expect(MobileNewTabDrawer.haze(darkMode: true, incognito: true) == 0)
        let row = MobileNewTabDrawer.haze(darkMode: true, incognito: false, overTabRow: true)
        #expect(row > 0 && row < haze, "less over the tab switcher")
    }

    @Test func theDrawersListFollowsItsOpenPositionAndTheMenusFollowsItsField() {
        var drawer = MobileNewTabDrawer()
        #expect(drawer.listOpenness(fieldOpenness: 1, drawerProgress: 0.3) == 1, "the page menu's address editor")
        #expect(drawer.fieldStyle(pageIsLight: true) == .standard)
        drawer.growsFromBar = true
        #expect(drawer.listOpenness(fieldOpenness: 1, drawerProgress: 0.3) == 0.3, "the new tab drawer")
        #expect(drawer.fieldStyle(pageIsLight: true) == .lightPage)
        #expect(drawer.fieldStyle(pageIsLight: false) == .darkPage)
        #expect(MobileNewTabDrawer() == MobileNewTabDrawer(), "a settled drawer is the fresh one")
    }
}

struct MobileSuggestionsTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/650")) func syncedSpaceSitesKeepTheirPlaceAndPhoneWins() {
        var a = SidebarDocument.fresh()
        var b = SidebarDocument.fresh()
        a.spaces[0].title = "A"
        b.spaces[0].title = "B"
        let pinned = MobileRecentTabsTests.mac("https://x.example/p", "Manga pinned", 3)
        let nested = MobileRecentTabsTests.mac("https://nested.example", "Manga folder", 2)
        let today = MobileRecentTabsTests.mac("https://today.example", "Manga today", 4)
        let undated = MobileRecentTabsTests.mac("https://undated.example", "Manga undated", nil)
        let favorite = MobileRecentTabsTests.mac("https://favorite.example", "Manga favorite", 9)
        var folder = SidebarItem.folder("Folder", parent: a.spaces[0].pinnedContainerID)
        folder.children = [nested.id]
        a.items += [pinned, nested, folder, favorite]
        a.items[a.items.firstIndex { $0.id == a.spaces[0].pinnedContainerID }!].children = [pinned.id, folder.id]
        a.items[a.items.firstIndex { $0.id == a.spaces[0].favoritesContainerID }!].children = [favorite.id]
        b.items += [today, undated]
        b.items[b.items.firstIndex { $0.id == b.spaces[0].todayContainerID }!].children = [today.id]
        b.items[b.items.firstIndex { $0.id == b.spaces[0].pinnedContainerID }!].children = [undated.id]
        a.spaces += b.spaces
        a.items += b.items
        var blank = SidebarDocument.fresh()
        blank.spaces[0].standaloneWindowID = UUID()
        let hidden = MobileRecentTabsTests.mac("https://hidden.example", "Manga hidden", 10)
        blank.items.append(hidden)
        blank.items[blank.items.firstIndex { $0.id == blank.spaces[0].pinnedContainerID }!].children = [hidden.id]
        a.spaces += blank.spaces
        a.items += blank.items
        let sites = MobileSuggestions.macSites(in: a)
        // Today tabs come too (Victor, 20 Nov), newest first with the pinned ones.
        #expect(sites.map(\.title) == ["Manga today", "Manga pinned", "Manga folder", "Manga undated"])
        #expect(sites.map { $0.place?.prefix } == ["Today in ", "Pinned in ", "Pinned in ", "Pinned in "])
        #expect(sites.map { $0.place?.space } == ["B", "A", "A", "B"])
        let phone = MobileSuggestions.Site(title: "Manga phone", url: "https://www.x.example/p/")
        let rows = MobileSuggestions.rows(typed: "manga", completions: [], sites: [phone] + sites, limit: 10)
        #expect(rows.map(\.text) == ["manga", "Manga phone", "Manga today"])
        #expect(rows[1].place == nil)
        #expect(rows[2].place?.prefix == "Today in " && rows[2].place?.space == "B")
        let duplicate = MobileSuggestions.rows(typed: "x.example", completions: [], sites: [phone] + sites)
        #expect(duplicate.filter { if case .site = $0.kind { return true }; return false }.count == 1)
        #expect(duplicate[0].place == nil)
        let extras = (1...2).map { MobileRecentTabsTests.mac("https://extra\($0).example", "Manga extra", 1) }
        a.items += extras
        a.items[a.items.firstIndex { $0.id == a.spaces[0].pinnedContainerID }!].children += extras.map(\.id)
        let many = MobileSuggestions.macSites(in: a)
        #expect(many.count == 6)
        #expect(MobileSuggestions.rows(typed: "manga", completions: [], sites: many, limit: 10).count == 3)
    }

    @Test func emptyFieldHasNoRows() {
        #expect(MobileSuggestions.rows(typed: "  ", completions: ["a"]).isEmpty)
    }

    /// Arc Search's list for "what to do": the typed text, then three completions with the typed
    /// part marked.
    @Test func typedTextComesFirstThenCompletions() {
        let rows = MobileSuggestions.rows(typed: "what to do", completions: [
            "what to do", "what to do nyc", "what to do new jersey", "what to do in nyc today", "what to do in paris",
        ])
        #expect(rows.map(\.text) == ["what to do", "what to do nyc", "what to do new jersey", "what to do in nyc today"])
        #expect(rows.map(\.typedPrefixLength) == [0, 10, 10, 10])
        #expect(rows.allSatisfy { $0.kind == .search })
    }

    @Test func completionThatDoesNotStartWithTheTypedTextIsAllNew() {
        let rows = MobileSuggestions.rows(typed: "nyc", completions: ["weather nyc", "NYC subway"])
        #expect(rows.map(\.typedPrefixLength) == [0, 0, 3])
    }

    @Test func anAddressOpensAndASearchSearches() {
        let rows = MobileSuggestions.rows(typed: "crabrowser.app", completions: ["crabrowser.app download"])
        #expect(rows[0].kind == .address)
        #expect(MobileSuggestions.destination(for: rows[0], engine: .google) == "https://crabrowser.app")
        #expect(MobileSuggestions.destination(for: rows[1], engine: .duckduckgo) == "https://duckduckgo.com/?q=crabrowser.app%20download")
        #expect(MobileSuggestions.destination(forTyped: " a b ", engine: .google) == "https://www.google.com/search?q=a%20b")
    }

    /// Pages the phone knows join the list: a site whose address starts with what was typed
    /// leads, the typed text follows, a title match comes after it, and completions fill the rest.
    @Test func knownSitesJoinTheList() {
        let sites = [
            MobileSuggestions.Site(title: "Weather Forecast Aarhus", url: "https://yr.no/aarhus"),
            MobileSuggestions.Site(title: "Weather.com", url: "https://www.weather.com/"),
            MobileSuggestions.Site(title: "Weather.com again", url: "http://weather.com#today"),
            MobileSuggestions.Site(title: "Local weather", url: "cra://weather"),
        ]
        let rows = MobileSuggestions.rows(typed: "weat", completions: ["weather", "weather today", "weather aarhus"], sites: sites)
        #expect(rows.map(\.text) == ["Weather.com", "weat", "Weather Forecast Aarhus", "weather"])
        #expect(rows[0].kind == .site(url: "https://www.weather.com/"))
        #expect(rows[2].kind == .site(url: "https://yr.no/aarhus"))
        #expect(MobileSuggestions.destination(for: rows[0], engine: .google) == "https://www.weather.com/")
        #expect(MobileSuggestions.destination(for: rows[3], engine: .google) == "https://www.google.com/search?q=weather")
    }

    /// Without an address match the typed text stays on top; every typed word has to begin a
    /// word of the title, and no more than two sites crowd out the engine.
    @Test func titleMatchesFollowTheTypedText() {
        let sites = [
            MobileSuggestions.Site(title: "Risotto vs paella", url: "https://a.example/1"),
            MobileSuggestions.Site(title: "Paella recipe", url: "https://b.example/2"),
            MobileSuggestions.Site(title: "Best paella in Valencia", url: "https://c.example/3"),
            MobileSuggestions.Site(title: "Spanish rice", url: "https://d.example/4"),
        ]
        let rows = MobileSuggestions.rows(typed: "pae", completions: ["paella"], sites: sites)
        #expect(rows.map(\.text) == ["pae", "Risotto vs paella", "Paella recipe", "paella"])
        #expect(MobileSuggestions.rows(typed: "paella rec", completions: [], sites: sites).map(\.text) == ["paella rec", "Paella recipe"])
        #expect(MobileSuggestions.rows(typed: "ella", completions: [], sites: sites).map(\.text) == ["ella"])
        // A site with no title shows its address.
        let untitled = MobileSuggestions.rows(typed: "news", completions: [], sites: [.init(title: " ", url: "https://www.news.example/")])
        #expect(untitled.map(\.text) == ["news.example", "news"])
    }

    /// The clip: "Bangalore" typed, ten suggestions; each row scrolled under the field puts its
    /// text there, the last can reach it, and a flick rests on a whole row.
    @Test func scrollingBringsEachSuggestionIntoTheField() {
        let texts = ["Bangalore", "bangalore weather", "bangalore metro map", "bangalore news", "bangalore temperature",
                     "bangalore palace", "bangalore auto driver news", "bangalore university", "bangalore weather today", "bangalore to delhi flight"]
        let rows = MobileSuggestions.rows(typed: "Bangalore", completions: Array(texts.dropFirst()), limit: MobileSearchSheet.listedRows)
        #expect(rows.count == 10)
        typealias S = MobileSuggestions.Scroll
        #expect(S.fieldText(typed: "Bangalore", rows: rows, offset: 0, rowHeight: 56) == "Bangalore")
        #expect(S.fieldText(typed: "Bangalore", rows: rows, offset: 20, rowHeight: 56) == "Bangalore")
        #expect(S.fieldText(typed: "Bangalore", rows: rows, offset: 56 * 3, rowHeight: 56) == "bangalore metro map")
        #expect(S.fieldText(typed: "Bangalore", rows: rows, offset: 56 * 30, rowHeight: 56) == "bangalore to delhi flight")
        #expect(S.restingOffset(145.6, rowHeight: 56, count: 10) == CGFloat(168))
        #expect(S.restingOffset(-40, rowHeight: 56, count: 10) == CGFloat(0))
        #expect(S.contentHeight(count: 10, rowHeight: 56, visibleHeight: 224) == CGFloat(784))
        #expect(S.contentHeight(count: 1, rowHeight: 56, visibleHeight: 224) == CGFloat(56))
    }

    /// Arc Search's engines, in its menu's order; the two the Mac app lacks have their own addresses.
    @Test func searchEnginesAreArcSearchs() {
        #expect(MobileSearchEngine.allCases.map(\.label) == ["Google", "Bing", "DuckDuckGo", "Ecosia", "Perplexity", "Kagi"])
        #expect(MobileSearchEngine.ecosia.searchURL("a b&c") == "https://www.ecosia.org/search?q=a%20b%26c")
        #expect(MobileSearchEngine.perplexity.searchURL("a b") == "https://www.perplexity.ai/search?q=a%20b")
        #expect(MobileSearchEngine.perplexity.suggestURL("a") == nil)
        #expect(MobileSearchEngine.kagi.searchURL("a") == SearchEngine.kagi.searchURL("a"))
        #expect(MobileSearchEngine.ecosia.suggestURL("a b")?.absoluteString == "https://ac.ecosia.org/autocomplete?q=a%20b&type=list")
    }

    @Test func readsOpenSearchAnswers() {
        let google = Data(#")]}'["wh",["whatsapp","weather","whatsapp.com"],["","",""],[],{"google:suggesttype":["QUERY","QUERY","NAVIGATION"]}]"#.utf8)
        #expect(MobileSuggestions.completions(fromOpenSearch: google) == ["whatsapp", "weather"])
        let duck = Data(#"["wh",["what","who"]]"#.utf8)
        #expect(MobileSuggestions.completions(fromOpenSearch: duck) == ["what", "who"])
        #expect(MobileSuggestions.completions(fromOpenSearch: Data("<html>".utf8)).isEmpty)
    }
}

struct MobileTabsTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func tab(_ name: String, hoursAgo: Double, incognito: Bool = false) -> MobileTab {
        MobileTab(url: "https://\(name).example", title: name, lastActive: start.addingTimeInterval(-hoursAgo * 3600),
                  isIncognito: incognito)
    }

    @Test func closingTheTabOnScreenShowsItsNeighbour() {
        var document = MobileTabsDocument()
        let tabs = ["a", "b", "c"].map { Self.tab($0, hoursAgo: 1) }
        tabs.forEach { document.open($0) }
        document.select(tabs[1].id, now: Self.start)
        document.close(tabs[1].id)
        #expect(document.selected == tabs[2].id)
        document.close(tabs[2].id)
        #expect(document.selected == tabs[0].id)
        document.close(tabs[0].id)
        #expect(document.selected == nil)
    }

    /// A tab picked from the row moves to its newest end, as in Arc Search: the row runs from
    /// the least to the most recently picked. A plain select (a swipe along the bar) keeps the order.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/647")) func aPickedTabMovesToTheNewestEnd() {
        var document = MobileTabsDocument()
        let tabs = ["a", "b", "c", "d"].map { Self.tab($0, hoursAgo: 1) }
        tabs.forEach { document.open($0) }
        document.bringToFront(tabs[0].id, now: Self.start)
        #expect(document.tabs.map(\.title) == ["b", "c", "d", "a"])
        #expect(document.selected == tabs[0].id)
        #expect(document.selectedTab?.lastActive == Self.start)
        document.bringToFront(tabs[0].id, now: Self.start)
        #expect(document.tabs.map(\.title) == ["b", "c", "d", "a"], "the newest stays where it is")
        document.select(tabs[2].id, now: Self.start)
        #expect(document.tabs.map(\.title) == ["b", "c", "d", "a"], "walking the row doesn't reorder it")
        document.bringToFront(UUID(), now: Self.start)
        #expect(document.selected == tabs[2].id, "a tab that is gone changes nothing")
    }

    /// The reporter's follow-up: a popup from a tab further back, once put away, hands the screen
    /// back to that tab, not to its neighbour at the end of the row.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/647")) func archivingAPopupReturnsToItsOpener() {
        var document = MobileTabsDocument()
        let tabs = ["a", "b", "c"].map { Self.tab($0, hoursAgo: 1) }
        tabs.forEach { document.open($0) }
        let popup = Self.tab("popup", hoursAgo: 0)
        document.open(popup)
        document.archive(popup.id, returningTo: tabs[0].id)
        #expect(document.selected == tabs[0].id)
        #expect(document.archived.map(\.title) == ["popup"])

        let other = Self.tab("other", hoursAgo: 0)
        document.open(other)
        document.archive(tabs[1].id, returningTo: tabs[0].id)
        #expect(document.selected == other.id, "a tab off screen leaves the screen alone")

        document.archive(tabs[0].id)
        let orphan = Self.tab("orphan", hoursAgo: 0)
        document.open(orphan)
        document.archive(orphan.id, returningTo: tabs[0].id)
        #expect(document.selected == other.id, "an opener that is gone falls back to the neighbour")
    }

    @Test func staleTabsGoToTheArchiveNewestFirst() {
        var document = MobileTabsDocument()
        let old = Self.tab("old", hoursAgo: 50), older = Self.tab("older", hoursAgo: 80), fresh = Self.tab("fresh", hoursAgo: 2)
        let secret = Self.tab("secret", hoursAgo: 60, incognito: true), onScreen = Self.tab("on-screen", hoursAgo: 90)
        [older, old, fresh, secret, onScreen].forEach { document.open($0) }
        #expect(document.archiveStale(after: .oneDay, now: Self.start) == 3)
        #expect(document.tabs.map(\.title) == ["fresh", "on-screen"])
        #expect(document.archived.map(\.title) == ["old", "older"])
        #expect(document.archiveStale(after: .thirtyDays, now: Self.start) == 0)
        #expect(MobileArchiveAfter.allCases.map(\.label) == ["12 hours", "1 day", "3 days", "7 days", "30 days"])
        #expect(MobileArchiveAfter.oneDay.settingValue == "After 1 day")
    }

    /// A flick up on the tab button goes to the tab looked at last, whatever its place in the
    /// row, and the next flick comes back: Arc Search's toggle between the two newest tabs.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/537")) func theFlickGoesToTheTabLookedAtLast() {
        var document = MobileTabsDocument()
        let a = Self.tab("a", hoursAgo: 3), b = Self.tab("b", hoursAgo: 2), c = Self.tab("c", hoursAgo: 1)
        [a, b, c].forEach { document.open($0) }
        #expect(document.previousTab?.title == "b")
        document.select(a.id, now: Self.start)
        #expect(document.previousTab?.title == "c", "the row's neighbour is b, but c was on screen last")
        document.select(c.id, now: Self.start.addingTimeInterval(1))
        #expect(document.previousTab?.title == "a")
        // Incognito tabs are not in the row, so a flick never lands on one.
        document.add(Self.tab("secret", hoursAgo: 0, incognito: true))
        #expect(document.previousTab?.title == "a")
        var alone = MobileTabsDocument()
        alone.open(a)
        #expect(alone.previousTab == nil)
    }

    @Test func restoringAnArchivedTabShowsIt() {
        var document = MobileTabsDocument()
        let old = Self.tab("old", hoursAgo: 50), current = Self.tab("current", hoursAgo: 0)
        [old, current].forEach { document.open($0) }
        document.archiveStale(after: .twelveHours, now: Self.start)
        document.restore(old.id, now: Self.start)
        #expect(document.archived.isEmpty)
        #expect(document.selectedTab?.title == "old")
        #expect(document.selectedTab?.lastActive == Self.start)
    }

    @Test func aClosedTabGoesToTheArchiveAndAnIncognitoOneDoesNot() {
        var document = MobileTabsDocument()
        let plain = Self.tab("plain", hoursAgo: 1), secret = Self.tab("secret", hoursAgo: 1, incognito: true)
        [plain, secret].forEach { document.open($0) }
        #expect(document.exportText == "plain\nhttps://plain.example")
        document.archive(secret.id)
        document.archive(plain.id)
        #expect(document.tabs.isEmpty && document.archived.map(\.title) == ["plain"])
        document.removeArchived([plain.id])
        #expect(document.archived.isEmpty)
    }

    @Test func anIncognitoTabClosesOnceItIsLeftAndNeverShowsInTheRow() {
        var document = MobileTabsDocument()
        let plain = Self.tab("plain", hoursAgo: 1), secret = Self.tab("secret", hoursAgo: 0, incognito: true)
        [plain, secret].forEach { document.open($0) }
        #expect(document.rowTabs.map(\.title) == ["plain"])
        #expect(document.closeIncognitoTabsLeftBehind().isEmpty, "the tab on screen stays")
        document.select(plain.id, now: Self.start)
        #expect(document.closeIncognitoTabsLeftBehind() == [secret.id])
        #expect(document.tabs.map(\.title) == ["plain"] && document.archived.isEmpty)
    }

    @Test func aSavedDocumentLoadsBack() throws {
        var document = MobileTabsDocument()
        document.open(Self.tab("a", hoursAgo: 1))
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(MobileTabsDocument.self, from: data) == document)
        // A file from before a field existed, and one whose selected tab is gone.
        let bare = Data(#"{"tabs":[{"id":"7B0D4A1E-3C5F-4E7A-9B1D-2F6A8C0E4D21","url":"https://a.example","lastActive":0}],"selected":"00000000-0000-0000-0000-000000000000"}"#.utf8)
        let loaded = try JSONDecoder().decode(MobileTabsDocument.self, from: bare)
        #expect(loaded.tabs.first?.displayTitle == "a.example")
        #expect(loaded.selected == nil)
    }

    /// The tab row opens focused on the card behind the page, to its left; the first or only
    /// card focuses itself, and with no page the newest card does.
    @Test func theRowFocusesTheCardBehindThePage() {
        var document = MobileTabsDocument()
        let tabs = ["a", "b", "c"].map { Self.tab($0, hoursAgo: 1) }
        tabs.forEach { document.open($0) }
        document.select(tabs[1].id, now: Self.start)
        #expect(document.switcherFocus?.id == tabs[0].id)
        document.select(tabs[0].id, now: Self.start)
        #expect(document.switcherFocus?.id == tabs[0].id, "the first card focuses itself")
        document.select(tabs[2].id, now: Self.start)
        #expect(document.switcherFocus?.id == tabs[1].id)
        document.selected = nil
        #expect(document.switcherFocus?.id == tabs[2].id, "no page: the newest card")
        document.tabs = [tabs[0]]
        document.selected = tabs[0].id
        #expect(document.switcherFocus?.id == tabs[0].id, "one tab focuses itself")
    }

    /// The tab button previews the two tabs behind the page, never the page itself: the previous
    /// tab on top and the tab behind it underneath.
    @Test func theButtonPreviewsTheTwoTabsBehindThePage() {
        let tabs = (1...4).map { Self.tab("\($0)", hoursAgo: Double($0)) }
        let document = MobileTabsDocument(tabs: tabs, selected: tabs[1].id)
        #expect(document.tabsBehindCurrent.map(\.title) == ["1", "3", "4"])
        #expect(document.previousTab?.title == "1")
        #expect(!document.tabsBehindCurrent.contains { $0.id == tabs[1].id }, "the page itself is left out")
        let tied = ["a", "b", "c"].map { Self.tab($0, hoursAgo: 1) }
        let even = MobileTabsDocument(tabs: tied, selected: tied[0].id)
        #expect(even.tabsBehindCurrent.map(\.title) == ["c", "b"], "ties go to the newer tab in the row")
        #expect(even.previousTab?.title == "c")
    }
}

struct MobileSettingsTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/674")) func appSettingsUsesFullHeightOnIPadAndKeepsMediumOnIPhone() {
        #expect(MobileSettingsSheet.appSettingsHeights(onPad: true) == [.large])
        #expect(MobileSettingsSheet.appSettingsHeights(onPad: false) == [.medium, .large])
    }

    @Test func aMissingOrOlderFileIsTheDefaults() throws {
        let loaded = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"searchEngine":"duckduckgo","archiveAfter":"someday"}"#.utf8))
        #expect(loaded.searchEngine == .duckduckgo)
        #expect(loaded.archiveAfter == .oneDay)
        #expect(loaded.opensKeyboardOnLaunch && loaded.siteDefaults == MobileSiteOptions())
        #expect(loaded.siteDefaults.blockAds && loaded.siteDefaults.blockTrackers && loaded.siteDefaults.blockCookieBanners)
        #expect(loaded.siteDefaults.swipeToNavigate == .fromAnywhere && loaded.openAppLinksIn == .nativeApp)
        let saved = try JSONEncoder().encode(loaded)
        #expect(try JSONDecoder().decode(MobileSettings.self, from: saved) == loaded)
    }

    /// "Browse for Me" as the search engine: older files load without it, the engine stays for
    /// suggestions, and a search (not an address) becomes a Browse for Me tab.
    @Test func browseForMeCanBeTheSearchEngine() throws {
        var settings = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"searchEngine":"bing"}"#.utf8))
        #expect(settings.searchChoice == .engine(.bing) && !settings.searchesWithBrowseForMe)
        settings.searchChoice = .browseForMe
        #expect(settings.searchEngine == .bing && settings.searchesWithBrowseForMe)
        let saved = try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.searchChoice == .browseForMe)
        settings.searchChoice = .engine(.kagi)
        #expect(settings.searchEngine == .kagi && !settings.searchesWithBrowseForMe)
        #expect(MobileSearchChoice.all(browseForMeAvailable: true).map(\.label) == ["Browse for Me", "Google", "Bing", "DuckDuckGo", "Ecosia", "Perplexity", "Kagi", "Custom"])
        #expect(MobileSearchChoice.all(browseForMeAvailable: false).first == .engine(.google))
        #expect(MobileSuggestions.destination(forTyped: "pizza ovens", engine: .bing, browsesForMe: true) == MobileBrowseForMe.tabAddress(query: "pizza ovens"))
        #expect(MobileSuggestions.destination(forTyped: "crabrowser.app", engine: .bing, browsesForMe: true) == "https://crabrowser.app")
    }

    @Test func aSiteKeepsItsOwnChoicesUntilTheyMatchTheGlobalOnesAgain() {
        var settings = MobileSettings()
        var site = settings.options(for: "www.Example.com")
        site.blockAds = false
        site.swipeToNavigate = .fromEdges
        settings.setOptions(site, for: "www.Example.com")
        #expect(settings.options(for: "example.com").blockAds == false)
        #expect(settings.options(for: "example.com").swipeToNavigate == .fromEdges)
        #expect(settings.options(for: "example.com").blockTrackers == true)
        #expect(settings.options(for: "other.example").blockAds == true)
        // A global change reaches the site where it made no choice of its own.
        settings.siteDefaults.collapseBottomBar = false
        #expect(settings.options(for: "example.com").collapseBottomBar == false)
        settings.setOptions(settings.siteDefaults, for: "example.com")
        #expect(settings.siteOverrides.isEmpty)
    }
}

struct MobileArchiveTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }()
    /// Wednesday 11 November 2026, 21:00 in Copenhagen.
    static let now = Date(timeIntervalSince1970: 1_794_427_200)

    static func tab(_ title: String, hoursAgo: Double) -> MobileTab {
        MobileTab(url: "https://\(title.lowercased()).example/page", title: title, lastActive: now.addingTimeInterval(-hoursAgo * 3600))
    }

    /// Arc Search's Archive: "TODAY", "YESTERDAY", then each older day by its date.
    @Test func archiveIsGroupedByDayNewestFirst() {
        let tabs = [Self.tab("Morning", hoursAgo: 10), Self.tab("Evening", hoursAgo: 1), Self.tab("Tuesday", hoursAgo: 30),
                    Self.tab("LastWeek", hoursAgo: 24 * 6)]
        let sections = MobileArchive.sections(tabs, matching: "", now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(sections.map(\.title) == ["TODAY", "YESTERDAY", "THURSDAY, NOVEMBER 5"])
        #expect(sections[0].tabs.map(\.title) == ["Evening", "Morning"])
    }

    @Test func searchMatchesTitleAndAddress() {
        let tabs = [Self.tab("Pizza", hoursAgo: 1), Self.tab("Pasta", hoursAgo: 2)]
        let byTitle = MobileArchive.sections(tabs, matching: "piz", now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(byTitle.flatMap(\.tabs).map(\.title) == ["Pizza"])
        let byAddress = MobileArchive.sections(tabs, matching: "PASTA.example", now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(byAddress.flatMap(\.tabs).map(\.title) == ["Pasta"])
    }

    @Test func aRowShowsTheAddressWithoutItsScheme() {
        #expect(MobileArchive.subtitle(for: Self.tab("Pizza", hoursAgo: 1)) == "pizza.example/page")
    }
}

struct MobileTabCarouselTests {
    static let phone = CGSize(width: 393, height: 852)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/878")) func picturesKeepTheTopLeftWhenTheScreenShapeChanges() {
        let narrow = CGRect(x: 0, y: 10, width: 300, height: 450)
        let widePicture = MobileTabCarousel.pictureFrame(image: CGSize(width: 951, height: 669), in: narrow)
        #expect(abs(widePicture.minX) < 0.01 && abs(widePicture.minY - 10) < 0.01)
        #expect(abs(widePicture.height - 450) < 0.01 && widePicture.width > 300)

        let wide = CGRect(x: 0, y: 0, width: 600, height: 400)
        let narrowPicture = MobileTabCarousel.pictureFrame(image: CGSize(width: 466, height: 678), in: wide)
        #expect(abs(narrowPicture.minX) < 0.01 && abs(narrowPicture.minY) < 0.01)
        #expect(abs(narrowPicture.width - 600) < 0.01 && narrowPicture.height > 400)

        let portrait = CGRect(x: 0, y: 0, width: 273, height: 591.8)
        let matching = MobileTabCarousel.pictureFrame(image: Self.phone, in: portrait)
        #expect(abs(matching.minX - portrait.minX) < 1 && abs(matching.minY - portrait.minY) < 1)
        #expect(abs(matching.maxX - portrait.maxX) < 1 && abs(matching.maxY - portrait.maxY) < 1)
        #expect(MobileTabCarousel.pictureFrame(image: .zero, in: narrow) == narrow)
    }

    /// Arc Search's row at rest on an iPhone 15 Pro.
    @Test func cardsSitWhereArcSearchPutsThem() {
        let focus = MobileTabCarousel.placement(relative: 0, in: Self.phone)
        #expect(focus.frame == CGRect(x: 393 * 0.2112, y: 852 * 0.5147 - 277.5, width: 273, height: 555))
        #expect(abs(focus.frame.minX - 83) < 0.1 && abs(focus.frame.minY - 161) < 0.1)
        #expect(focus.scale == 1 && focus.dim == 0)
        let next = MobileTabCarousel.placement(relative: 1, in: Self.phone)
        #expect(abs(next.frame.minX - 304.1) < 0.1 && next.scale > 1 && next.dim == 0)
        let previous = MobileTabCarousel.placement(relative: -1, in: Self.phone)
        #expect(abs(previous.frame.minX - 10) < 0.1 && abs(previous.scale - 0.977) < 0.001)
        #expect(previous.dim == MobileTabCarousel.maximumDim)
        #expect(MobileTabCarousel.placement(relative: -0.5, in: Self.phone).dim == 0.08)
    }

    /// With only one tab, Arc Search puts its card in the middle of the screen (Brady Sewall's picture on #816, an
    /// iPhone 440 pt wide: the card 66 to 374 pt); Cra kept it left of centre, where a card with a neighbour sits.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/816")) func aLoneCardSitsInTheMiddle() {
        for screen in [Self.phone, CGSize(width: 440, height: 956)] {
            let alone = MobileTabCarousel.placement(relative: 0, in: screen, alone: true).frame
            #expect(abs(alone.midX - screen.width / 2) < 0.5, "centred on \(screen.width): \(alone)")
            #expect(alone.size == MobileTabCarousel.placement(relative: 0, in: screen).frame.size)
        }
        let big = MobileTabCarousel.placement(relative: 0, in: CGSize(width: 440, height: 956), alone: true).frame
        #expect(abs(big.minX - 66) < 2 && abs(big.maxX - 374) < 2, "where Arc Search has it: \(big)")
        // With a neighbour the card in focus stays where Arc Search puts it, left of centre.
        #expect(abs(MobileTabCarousel.placement(relative: 0, in: Self.phone).frame.minX - 83) < 0.1)
    }

    /// With several tabs, the first and the last card have no neighbour on one side and Arc
    /// Search 1.50 rests them in the middle of the screen (recordings of a 390 pt iPhone, 25 and
    /// 26 Nov 2026: 58 pt in, where a card between two others rests 83 pt in). Cra kept them
    /// left of centre.
    @Test func theFirstAndLastCardsRestInTheMiddle() {
        #expect(MobileTabCarousel.endCentring(position: 0, count: 4) == 1)
        #expect(MobileTabCarousel.endCentring(position: 3, count: 4) == 1)
        #expect(MobileTabCarousel.endCentring(position: 1, count: 4) == 0)
        #expect(MobileTabCarousel.endCentring(position: 2, count: 4) == 0)
        // Part of the way while the row moves between an end and its neighbour, and whole past an end.
        #expect(MobileTabCarousel.endCentring(position: 0.5, count: 4) == 0.5)
        #expect(MobileTabCarousel.endCentring(position: 2.5, count: 4) == 0.5)
        #expect(MobileTabCarousel.endCentring(position: -0.2, count: 4) == 1)
        #expect(MobileTabCarousel.endCentring(position: 3.3, count: 4) == 1)
        // Two tabs: each is an end, so the row stays centred on the way between them.
        #expect(MobileTabCarousel.endCentring(position: 0, count: 2) == 1)
        #expect(MobileTabCarousel.endCentring(position: 0.5, count: 2) == 1)
        #expect(MobileTabCarousel.endCentring(position: 1, count: 2) == 1)
        // A lone card is `alone`.
        #expect(MobileTabCarousel.endCentring(position: 0, count: 1) == 0)

        let focus = MobileTabCarousel.placement(relative: 0, in: Self.phone, centring: 1)
        #expect(abs(focus.frame.midX - 196.5) < 0.001)
        // The next card comes along, a pitch away; the one behind keeps its place at the left edge.
        let next = MobileTabCarousel.placement(relative: 1, in: Self.phone, centring: 1)
        #expect(abs(next.frame.minX - focus.frame.minX - MobileTabCarousel.pitch(in: Self.phone)) < 0.001)
        #expect(MobileTabCarousel.placement(relative: -1, in: Self.phone, centring: 1) == MobileTabCarousel.placement(relative: -1, in: Self.phone))
        // Beside a side column the middle is the middle of what is left.
        let wide = CGSize(width: 477, height: 852)
        #expect(abs(MobileTabCarousel.placement(relative: 0, in: wide, sideInsets: (84, 0), centring: 1).frame.midX - (84 + 196.5)) < 0.001)
    }

    @Test func draggingFollowsTheFingerAndResistsPastTheEnds() {
        let pitch = MobileTabCarousel.pitch(in: Self.phone)
        #expect(MobileTabCarousel.position(start: 1, translation: -pitch, count: 3, in: Self.phone) == 2)
        #expect(MobileTabCarousel.position(start: 0, translation: pitch * 3, count: 3, in: Self.phone) == -1)
        #expect(MobileTabCarousel.position(start: 2, translation: -pitch * 3, count: 3, in: Self.phone) == 3)
        // Let go, the row moves on at the speed it was following the finger.
        #expect(MobileTabCarousel.velocity(-pitch, at: 1, count: 3, in: Self.phone) == 1)
        #expect(MobileTabCarousel.velocity(pitch * 3, at: -0.5, count: 3, in: Self.phone) == -1)
        #expect(MobileTabCarousel.velocity(-pitch * 3, at: 2.2, count: 3, in: Self.phone) == 1)
    }

    /// A finger that catches the row while it settles back from past an end holds it where it
    /// is. The catch started from the position on screen, which the drag resisted again: caught
    /// at -0.3 and moved a hundredth of a card outwards, the row jumped to -0.1 (Greptile on
    /// PR #882).
    @Test func catchingTheRowPastAnEndHoldsItWhereItIs() {
        let pitch = MobileTabCarousel.pitch(in: Self.phone)
        for caught: CGFloat in [-0.3, 2.3] {
            let start = MobileTabCarousel.dragStart(caughtAt: caught, count: 3)
            let held = MobileTabCarousel.position(start: start, translation: 0, count: 3, in: Self.phone)
            #expect(abs(held - caught) < 0.0001)
            let outwards: CGFloat = caught < 0 ? 1 : -1
            let moved = MobileTabCarousel.position(start: start, translation: outwards * pitch * 0.01, count: 3, in: Self.phone)
            #expect(abs(abs(moved - caught) - 0.01 / 3) < 0.0001, "it follows a third of the finger, from where it was")
        }
        #expect(MobileTabCarousel.dragStart(caughtAt: 1.4, count: 3) == 1.4)
    }

    @Test func aFlickGoesToTheNextCardAndStopsAtTheEnds() {
        #expect(MobileTabCarousel.restingIndex(position: 1.2, velocity: 0, count: 4, in: Self.phone) == 1)
        #expect(MobileTabCarousel.restingIndex(position: 1.2, velocity: -900, count: 4, in: Self.phone) == 2)
        #expect(MobileTabCarousel.restingIndex(position: 1.8, velocity: 900, count: 4, in: Self.phone) == 1)
        #expect(MobileTabCarousel.restingIndex(position: 3.3, velocity: -2000, count: 4, in: Self.phone) == 3)
        #expect(MobileTabCarousel.restingIndex(position: -0.2, velocity: 2000, count: 4, in: Self.phone) == 0)
    }

    /// Titles above the cards ran into each other (#816): every card showed its title across its
    /// whole width, under the card in front of it. Arc Search (MacStories' v1.0 picture) titles
    /// only the card in focus; the cards behind and in front show their favicon alone.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/816")) func onlyTheCardInFocusShowsItsTitle() {
        #expect(MobileTabCarousel.titleAlpha(relative: 0) == 1)
        #expect(MobileTabCarousel.titleAlpha(relative: -1) == 0, "the card behind: favicon alone")
        #expect(MobileTabCarousel.titleAlpha(relative: 1) == 0, "the card in front: favicon alone")
        #expect(MobileTabCarousel.titleAlpha(relative: 2.4) == 0 && MobileTabCarousel.titleAlpha(relative: -3) == 0)
        #expect(MobileTabCarousel.titleAlpha(relative: 0.25) == 0.5, "it fades out over half a card of drag")
        #expect(MobileTabCarousel.titleAlpha(relative: -0.5) == 0)
    }

    /// The focused card's title ran under the next card's favicon (#816's screenshot: the
    /// Paramount title over the Shopify icon). It stops before the card in front of it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/816")) func theFocusedTitleStopsBeforeTheCardInFront() {
        let focus = MobileTabCarousel.placement(relative: 0, in: Self.phone).frame
        let next = MobileTabCarousel.placement(relative: 1, in: Self.phone)
        let nextLeft = next.frame.minX + next.frame.width * (1 - next.scale) / 2
        let titleLeft = focus.minX + MobileTabCarousel.headerInset + MobileTabCarousel.headerIconSide + 7.5
        let width = MobileTabCarousel.titleWidth(titleLeft: titleLeft, cardRight: focus.maxX, nextCardLeft: nextLeft)
        #expect(titleLeft + width <= nextLeft - 8, "clear of the card in front, and of its favicon")
        #expect(width > 120, "room for a title still")
        let alone = MobileTabCarousel.titleWidth(titleLeft: titleLeft, cardRight: focus.maxX, nextCardLeft: nil)
        #expect(titleLeft + alone == focus.maxX - 16, "the newest card's title runs to its own edge")
        #expect(MobileTabCarousel.titleWidth(titleLeft: 300, cardRight: 310, nextCardLeft: 200) == 0)
    }

    /// Every flick in Pri's Arc Search recording (25 Nov 2026, 430 pt screen) moved one card. The
    /// hardest was let go 61 % of the way to the next card at 1,970 pt a second; one back was let
    /// go 31 % of the way at 1,260 pt a second. Cra sent them three cards and two.
    @Test func aFlickMovesOneCardAsInArcSearch() {
        let screen = CGSize(width: 430, height: 932)
        #expect(MobileTabCarousel.restingIndex(position: 0.611, velocity: -1970, start: 0, count: 5, in: screen) == 1)
        #expect(MobileTabCarousel.restingIndex(position: 1.69, velocity: 1260, start: 2, count: 5, in: screen) == 1)
        // A short flick from a card still reaches the next one.
        #expect(MobileTabCarousel.restingIndex(position: 2.05, velocity: -400, start: 2, count: 5, in: screen) == 3)
    }

    /// Let go, Arc Search's row keeps the finger's speed and slows into the card's place by the
    /// same share every frame, never passing it (Pri's recording, 25 Nov 2026, 60 fps). Cra's
    /// stopped dead and started again on a spring from standstill.
    @Test func theRowSettlesAsArcSearchsDoes() {
        let frame = 1.0 / 60
        func ratios(_ settle: MobileTabCarousel.Settle) -> [CGFloat] {
            (1...10).map { n in
                (settle.target - settle.position(after: Double(n) * frame))
                    / (settle.target - settle.position(after: Double(n - 1) * frame))
            }
        }
        // The hardest flick: 0.389 cards short of its card at 8.27 cards a second. Arc's
        // distance left shrank to 0.70–0.73 of itself every frame.
        let hard = MobileTabCarousel.Settle(from: 0.611, velocity: 8.27, target: 1)
        #expect(ratios(hard).allSatisfy { abs($0 - 0.71) < 0.02 })
        let dt = 0.0001
        #expect(abs((hard.position(after: dt) - 0.611) / dt - 8.27) < 0.01, "it starts at the finger's speed")
        // Gentle let-goes, and ones with no speed or moving away, settle at 0.84–0.86 a frame.
        for velocity: CGFloat in [2.07, 0, -1] {
            let gentle = MobileTabCarousel.Settle(from: -0.211, velocity: velocity, target: 0)
            #expect(ratios(gentle).allSatisfy { abs($0 - 0.85) < 0.01 })
            #expect(stride(from: 0.0, to: 2, by: frame).allSatisfy { gentle.position(after: $0) <= 0 })
            #expect(gentle.isDone(after: 0.7))
        }
    }

    @Test func aCardIsThrownAwayByDistanceOrByAFlick() {
        #expect(MobileTabCarousel.closes(translation: -130, velocity: 0))
        #expect(MobileTabCarousel.closes(translation: -40, velocity: -900))
        #expect(!MobileTabCarousel.closes(translation: -40, velocity: -100))
        #expect(!MobileTabCarousel.closes(translation: 200, velocity: 900))
    }
}

/// The row's cards as they are thrown out of it, faster than each one flies off.
struct MobileTabRowTests {
    static let ids = (0..<4).map { _ in UUID() }

    /// Closing tabs quickly crashed the iPhone app (Pri's screen recording, 25 Nov 2026). A card
    /// flies off for 0.28 s before it leaves the row, and the next flick can come before that.
    /// Each throw removed the card by the place it had when its flight began, so the second one
    /// to land took its neighbour or a place past the end of the row.
    @Test(.bug(id: "crash-tab-row-quick-throws"))
    func aCardLeavesTheRowByItsIDWhateverLandedBeforeIt() {
        let a = Self.ids[0], b = Self.ids[1], c = Self.ids[2]
        // The focused card, then the newer one on its right while the first still flies.
        var row = MobileTabRow(cards: [a, b, c])
        let threwB = row.startThrow(b), threwC = row.startThrow(c)
        #expect(threwB && threwC)
        let afterB = row.finishThrow(b, position: 1)
        #expect(afterB == .init(position: 1, settle: 1))
        let afterC = row.finishThrow(c, position: 1)
        #expect(afterC == .init(position: 1, settle: 0))
        #expect(row.cards == [a])
        // Oldest first: the second card's old place now holds its right-hand neighbour.
        row = MobileTabRow(cards: [a, b, c])
        row.startThrow(a)
        row.startThrow(b)
        let afterA = row.finishThrow(a, position: 2)
        #expect(afterA == .init(position: 1, settle: 1))
        let thenB = row.finishThrow(b, position: 1)
        #expect(thenB == .init(position: 0, settle: 0))
        #expect(row.cards == [c])
    }

    /// A flying card is out of reach: a finger can't take it again, and it leaves only once.
    @Test(.bug(id: "crash-tab-row-quick-throws"))
    func aFlyingCardCantBeThrownTwice() {
        let a = Self.ids[0], b = Self.ids[1]
        var row = MobileTabRow(cards: [a, b])
        #expect(row.canTake(b))
        let first = row.startThrow(b)
        #expect(first)
        #expect(!row.canTake(b))
        let second = row.startThrow(b)
        #expect(!second)
        #expect(row.canTake(a))
        let landed = row.finishThrow(b, position: 1)
        #expect(landed != nil)
        let again = row.finishThrow(b, position: 0)
        #expect(again == nil)
        #expect(row.cards == [a])
        #expect(!row.canTake(b))
    }

    /// The row closes the gap. A card gone from behind the focus leaves the focus on its card
    /// (the row shifts one place at once); the focused card hands it to the one after it, or to
    /// the one before when it was the newest.
    @Test func theRowClosesTheGapAroundTheFocus() {
        let ids = Self.ids
        func close(_ index: Int, at position: CGFloat) -> MobileTabRow.Gap? {
            var row = MobileTabRow(cards: ids)
            row.startThrow(ids[index])
            return row.finishThrow(ids[index], position: position)
        }
        #expect(close(0, at: 2) == .init(position: 1, settle: 1))
        #expect(close(1, at: 1) == .init(position: 1, settle: 1))
        #expect(close(3, at: 3) == .init(position: 3, settle: 2))
        #expect(close(3, at: 1) == .init(position: 1, settle: 1))
        #expect(!MobileTabRow(cards: []).canTake(ids[0]))
    }

    /// A card taken up while the row settles holds the row, which settles on where it was going
    /// once the card is let go. It kept that card's place, so a card thrown earlier that left
    /// meanwhile sent it to the next card, or past the end (Greptile on PR #882). It follows the
    /// card instead.
    @Test func aHeldRowResumesOnItsCardAfterAnEarlierThrowLands() {
        let ids = Self.ids
        var row = MobileTabRow(cards: ids)
        // Throw the first card, flick the row towards the third, then take the second up.
        row.startThrow(ids[0])
        _ = row.finishThrow(ids[0], position: 1.6)
        #expect(row.resumeIndex(heading: ids[2], position: 0.6) == 1, "the third card is second now")
        #expect(row.resumeIndex(heading: ids[3], position: 1.6) == 2, "the newest stays in the row")
        // A row heading for a card that has gone itself settles on the nearest.
        #expect(row.resumeIndex(heading: ids[0], position: 2.7) == 2)
        #expect(row.resumeIndex(heading: ids[0], position: -0.4) == 0)
    }

    /// A card thrown, then a flick before it has flown off: the row is between cards when the
    /// card leaves. The gap took the card nearest where the row was, so a flick heading for the
    /// third card, still at 1.1, landed on the second (Greptile on PR #882). It goes on to the
    /// card it was heading for, at its new place, and the row keeps its speed.
    @Test func aFlickStillLandsOnItsCardWhenAnEarlierThrowLeaves() {
        let ids = Self.ids
        var row = MobileTabRow(cards: ids)
        row.startThrow(ids[0])
        let flicked = row.finishThrow(ids[0], position: 1.1, heading: ids[2])
        #expect(flicked?.settle == 1 && abs((flicked?.position ?? 0) - 0.1) < 0.0001)
        // Without a flick under way the row closes the gap around the card in focus, as before.
        var still = MobileTabRow(cards: ids)
        still.startThrow(ids[0])
        let held = still.finishThrow(ids[0], position: 1.1)
        #expect(held?.settle == 0 && abs((held?.position ?? 0) - 0.1) < 0.0001)
        // A settle reports its speed, so the row can carry on from it.
        let settle = MobileTabCarousel.Settle(from: 1, velocity: 15, target: 2)
        #expect(abs(settle.velocity(after: 0) - 15) < 0.0001)
        #expect(settle.velocity(after: 0.05) < 15 && settle.velocity(after: 0.05) > 0)
    }
}

struct MobilePageMenuTests {
    /// Victor's recording of Arc Search 1.49 on an iPhone 16 Pro Max (440 × 956 pt): the closed
    /// menu's sheet starts at 508 pt with the recording's 85.6 × 88.7 tiles. Square tiles with
    /// slightly less horizontal padding (Victor's call) put it at 508.0 pt. The address capsule
    /// is at 524.7 pt; Display Options opens to four more rows.
    @Test func heightMatchesTheSquareTiles() {
        #expect(abs(MobilePageMenu.height(width: 440, safeBottom: 34) - (956 - 508.0)) < 1)
        #expect(abs(MobilePageMenu.height(displayOptionsOpen: true, width: 440, safeBottom: 34)
            - MobilePageMenu.height(width: 440, safeBottom: 34) - 192) < 0.001)
    }

    /// The tiles: 88.1 pt square from 16.3 pt in, 18.3 pt apart, their tops 81 pt down the sheet.
    @Test func fourTilesFillTheWidthAndThreeStayCentred() {
        let four = MobilePageMenu.tileFrames(count: 4, width: 440)
        #expect(abs(four[0].minX - 16.33) < 0.01)
        #expect(abs(four[3].maxX - (440 - 16.33)) < 0.01)
        #expect(abs(four[1].minX - four[0].maxX - 18.33) < 0.01)
        #expect(abs(four[0].width - 88.0875) < 0.01 && four[0].height == four[0].width)
        #expect(abs(four[0].minY - 80.9) < 0.01)
        let wide = MobilePageMenu.tileFrames(count: 4, width: 540)
        #expect(wide.allSatisfy { $0.width == $0.height }, "every sheet width keeps the buttons square")
        let three = MobilePageMenu.tileFrames(count: 3, width: 440)
        #expect(abs(three[1].midX - 220) < 0.01)
        #expect(MobilePageMenu.tiles(canSummarize: false) == [.findOnPage, .pin, .share])
        #expect(MobilePageMenu.displayOptions.map(\.label) == ["Translate", "Reader Mode", "Page Zoom", "Request Desktop Site"])
    }

    @Test func zoomStepsByTenthsWithinLimits() {
        #expect(MobilePageMenu.zoom(1, stepping: true) == 1.1)
        #expect(MobilePageMenu.zoom(1.1, stepping: false) == 1)
        #expect(MobilePageMenu.zoom(0.5, stepping: false) == 0.5)
        #expect(MobilePageMenu.zoom(3, stepping: true) == 3)
        #expect(MobilePageMenu.zoomLabel(1) == nil)
        #expect(MobilePageMenu.zoomLabel(1.3) == "130%")
    }

    /// "Arc scrubbed 22 trackers / Problems? Tap to restore original page" in the recording.
    @Test func theFooterCountsWhatWasScrubbed() {
        #expect(MobilePageMenu.scrubbedLabel(0) == nil)
        #expect(MobilePageMenu.scrubbedLabel(22)?.text == "Cra scrubbed 22 trackers")
        #expect(MobilePageMenu.scrubbedLabel(1)?.text == "Cra scrubbed 1 tracker")
        #expect(MobilePageMenu.restoreHint == "Problems? Tap to restore original page")
    }
}

struct MobileBlocklistTests {
    static let list = MobileBlocklist(text: "# comment\n\nads.example.com\nDoubleClick.net\nanalytics.example.org\n")

    @Test func listedDomainsCoverTheirSubdomains() {
        #expect(Self.list.domains == ["ads.example.com", "doubleclick.net", "analytics.example.org"])
        #expect(Self.list.blocks(host: "ads.example.com"))
        #expect(Self.list.blocks(host: "static.G.doubleclick.net"))
        #expect(!Self.list.blocks(host: "example.com"))
        #expect(!Self.list.blocks(host: "notdoubleclick.net"))
        #expect(!Self.list.blocks(host: "net"))
    }

    @Test func aRequestIsStoppedOnlyWhileItsKindIsSwitchedOn() {
        var options = MobileSiteOptions()
        #expect(Self.list.stops(host: "x.doubleclick.net", with: options))
        #expect(Self.list.stops(host: "eu.analytics.example.org", with: options))
        options.blockAds = false
        #expect(!Self.list.stops(host: "x.doubleclick.net", with: options))
        #expect(Self.list.stops(host: "eu.analytics.example.org", with: options))
        #expect(!Self.list.stops(host: "example.com", with: MobileSiteOptions()))
    }

    @Test func aDomainIsATrackerWhenItsNameSaysSo() {
        #expect(Self.list.domains(of: .trackers) == ["analytics.example.org"])
        #expect(Self.list.domains(of: .ads) == ["ads.example.com", "doubleclick.net"])
    }

    /// The JSON WebKit compiles: one third-party block rule per domain, valid JSON whose filter
    /// matches the domain and its subdomains only.
    @Test func rulesAreValidContentBlockerJSON() throws {
        let json = MobileBlocklist.rulesJSON(blocking: ["doubleclick.net"])
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let trigger = try #require(rules.first?["trigger"] as? [String: Any])
        let filter = try #require(trigger["url-filter"] as? String)
        #expect(trigger["load-type"] as? [String] == ["third-party"])
        #expect((rules.first?["action"] as? [String: String])?["type"] == "block")
        let regex = try NSRegularExpression(pattern: filter)
        func matches(_ url: String) -> Bool { regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
        #expect(matches("https://doubleclick.net/ad.js") && matches("https://g.doubleclick.net:443/x"))
        #expect(!matches("https://notdoubleclick.net/") && !matches("https://doubleclickxnet/") && !matches("https://example.com/doubleclick.net/"))
    }

    @Test func cookieBannerRuleHidesTheKnownContainers() throws {
        let json = MobileBlocklist.cookieBannerRulesJSON()
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let action = try #require(rules.first?["action"] as? [String: String])
        #expect(action["type"] == "css-display-none")
        #expect(action["selector"]?.contains("#onetrust-banner-sdk") == true)
        #expect(action["selector"]?.contains("[id^=\"sp_message_container\"]") == true)
    }

    @Test func aSitesSwitchesPickItsRuleLists() {
        var options = MobileSiteOptions()
        #expect(MobileBlocklist.ruleLists(for: options) == ["ads", "trackers", "cookie-banners"])
        options.blockAds = false
        options.blockCookieBanners = false
        #expect(MobileBlocklist.ruleLists(for: options) == ["trackers"])
    }
}

struct MobileSwipeTests {
    @Test func aDragCommitsByDistanceOrByAFlickInItsOwnDirection() {
        #expect(MobileSwipe.direction(translation: 150, velocity: 0, width: 393) == 1)
        #expect(MobileSwipe.direction(translation: -150, velocity: 0, width: 393) == -1)
        #expect(MobileSwipe.direction(translation: 60, velocity: 0, width: 393) == 0)
        #expect(MobileSwipe.direction(translation: 60, velocity: 900, width: 393) == 1)
        #expect(MobileSwipe.direction(translation: 60, velocity: -900, width: 393) == 0)
        #expect(MobileSwipe.direction(translation: 10, velocity: 2000, width: 393) == 0)
    }

    @Test func theBarSwipeMovesAlongTheTabRow() {
        #expect(MobileSwipe.tabStep(translation: 200, velocity: 0, width: 393, hasOlder: true, hasNewer: true) == -1)
        #expect(MobileSwipe.tabStep(translation: -200, velocity: 0, width: 393, hasOlder: true, hasNewer: true) == 1)
        #expect(MobileSwipe.tabStep(translation: 200, velocity: 0, width: 393, hasOlder: false, hasNewer: true) == 0)
    }

    /// Arc Search: back on a tab's first page archives the tab; the opposite swipe reopens it.
    @Test func backOnTheFirstPageArchivesTheTabAndForwardBringsItBack() {
        func swipe(_ translation: CGFloat, back: Bool = false, forward: Bool = false, other: Bool = true, reopen: Bool = false) -> MobileSwipe.Navigation {
            MobileSwipe.navigation(translation: translation, velocity: 0, width: 393, canGoBack: back, canGoForward: forward,
                                   hasOtherTab: other, canReopenTab: reopen)
        }
        #expect(swipe(200, back: true) == .back)
        #expect(swipe(200) == .archiveTab)
        #expect(swipe(200, other: false) == .none)
        #expect(swipe(-200, forward: true, reopen: true) == .forward)
        #expect(swipe(-200, reopen: true) == .reopenTab)
        #expect(swipe(-200) == .none)
        #expect(swipe(40, back: true) == .none)
    }

    @Test func edgesOnlyKeepsTheSwipeToTheSides() {
        #expect(MobileSwipe.mayStart(at: 200, width: 393, mode: .fromAnywhere))
        #expect(!MobileSwipe.mayStart(at: 200, width: 393, mode: .fromEdges))
        #expect(MobileSwipe.mayStart(at: 10, width: 393, mode: .fromEdges))
        #expect(MobileSwipe.mayStart(at: 385, width: 393, mode: .fromEdges))
    }

    /// A scroll view's room to either side: none on a page that fits, both ways in the middle
    /// of a zoomed page, and none past the end it sits at.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/627")) func scrollRoomIsWhatIsLeftOnEitherSide() {
        #expect(MobileSwipe.ScrollRoom(offsetX: 0, contentWidth: 393, width: 393) == .init(left: 0, right: 0))
        #expect(MobileSwipe.ScrollRoom(offsetX: 300, contentWidth: 1179, width: 393) == .init(left: 300, right: 486))
        #expect(MobileSwipe.ScrollRoom(offsetX: 786, contentWidth: 1179, width: 393) == .init(left: 786, right: 0))
        #expect(MobileSwipe.ScrollRoom(offsetX: -10, contentWidth: 800, width: 393, insetLeft: 10) == .init(left: 0, right: 417))
        #expect(MobileSwipe.ScrollRoom(offsetX: 900, contentWidth: 800, width: 393) == .init(left: 900, right: 0), "rubber-banding past the end")
    }

    /// Zoomed in, or on a carousel, a sideways drag scrolls what is under the finger; at its end,
    /// or where nothing scrolls, it goes Back or Forward. The screen's edge always navigates.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/627")) func aSidewaysDragScrollsWhatCanScrollBeforeItNavigates() {
        func starts(at x: CGFloat = 200, right: Bool, mode: MobileSwipeToNavigate = .fromAnywhere, _ scrollers: [MobileSwipe.ScrollRoom]) -> Bool {
            MobileSwipe.pageSwipeStarts(at: x, width: 393, mode: mode, touches: 1, velocity: CGPoint(x: right ? 600 : -600, y: 40),
                                        scrollers: scrollers)
        }
        let page = MobileSwipe.ScrollRoom(left: 0, right: 0)
        #expect(starts(right: true, [page]), "a page that fits goes Back")
        #expect(starts(right: false, [page]), "and Forward")

        let zoomedMiddle = MobileSwipe.ScrollRoom(left: 300, right: 486)
        #expect(!starts(right: true, [zoomedMiddle]), "zoomed in, the page scrolls")
        #expect(!starts(right: false, [zoomedMiddle]))

        let zoomedAtLeft = MobileSwipe.ScrollRoom(left: 0, right: 786)
        #expect(starts(right: true, [zoomedAtLeft]), "at its left end, a drag right goes Back")
        #expect(!starts(right: false, [zoomedAtLeft]))

        let carousel = MobileSwipe.ScrollRoom(left: 0, right: 1200)
        #expect(!starts(right: false, [carousel, page]), "the carousel under the finger scrolls")
        #expect(!starts(right: true, [MobileSwipe.ScrollRoom(left: 120, right: 0), page]), "and back again")
        #expect(starts(right: true, [carousel, page]), "at its start, a drag right goes Back")

        #expect(starts(at: 10, right: true, [zoomedMiddle]), "the left edge always goes Back")
        #expect(starts(at: 385, right: false, [carousel]), "the right edge always goes Forward")
        #expect(!starts(right: true, mode: .fromEdges, [page]), "From Edges keeps its rule")
    }

    /// Two fingers are a pinch: the page zooms instead of being dragged sideways.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/628")) func twoFingersNeverSwipeThePage() {
        let page = MobileSwipe.ScrollRoom(left: 0, right: 0)
        #expect(MobileSwipe.pageSwipeStarts(at: 200, width: 393, mode: .fromAnywhere, touches: 1, velocity: CGPoint(x: 600, y: 0), scrollers: [page]))
        #expect(!MobileSwipe.pageSwipeStarts(at: 200, width: 393, mode: .fromAnywhere, touches: 2, velocity: CGPoint(x: 600, y: 0), scrollers: [page]))
        #expect(!MobileSwipe.pageSwipeStarts(at: 10, width: 393, mode: .fromEdges, touches: 2, velocity: CGPoint(x: 600, y: 0), scrollers: [page]))
        #expect(!MobileSwipe.pageSwipeStarts(at: 200, width: 393, mode: .fromAnywhere, touches: 1, velocity: CGPoint(x: 300, y: 250), scrollers: [page]),
                "a drag that is not clearly sideways is the page's scroll")
    }

    /// The flick up from the tab button switches once it is far enough or quick enough upwards.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/537")) func theFlickUpSwitchesByDistanceOrSpeed() {
        #expect(MobileSwipe.switchesToPreviousTab(dragUp: 120, velocityUp: 0))
        #expect(!MobileSwipe.switchesToPreviousTab(dragUp: 50, velocityUp: 0))
        #expect(MobileSwipe.switchesToPreviousTab(dragUp: 50, velocityUp: 700))
        #expect(!MobileSwipe.switchesToPreviousTab(dragUp: 10, velocityUp: 2000))
        #expect(!MobileSwipe.switchesToPreviousTab(dragUp: 120, velocityUp: -800), "pulled back down before letting go")
        #expect(MobileSwipe.previousTabProgress(dragUp: 0) == 0)
        #expect(MobileSwipe.previousTabProgress(dragUp: 200) == 0.5)
        #expect(MobileSwipe.previousTabProgress(dragUp: 900) == 1)
        #expect(MobileSwipe.previousTabProgress(dragUp: -40) == 0)
    }

    /// The flick for the previous tab starts anywhere on the bar's left end, not only on the
    /// 47 pt button: a thumb that came down beside it opened the tab row (#537, reporter's
    /// follow-up). A flick leaning towards the middle still counts as up.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/537")) func theFlickStartsAnywhereOnTheBarsLeftEnd() {
        let size = CGSize(width: 393, height: 852)
        let zone = MobileBottomBar.previousTabZone(in: size, safeBottom: 34)
        let frames = MobileBottomBar.frames(in: size, safeBottom: 34)
        #expect(zone.contains(frames.tabs.insetBy(dx: -6, dy: -6)), "the button and its slop")
        #expect(zone.contains(CGPoint(x: 85, y: frames.tabs.midY)), "beside the button, towards the pill")
        #expect(zone.contains(CGPoint(x: 4, y: 850)), "the screen's corner")
        #expect(zone.contains(CGPoint(x: 30, y: frames.bar.minY + 1)), "the bar's top edge")
        #expect(!zone.intersects(frames.pill), "the pill keeps its drag up to the tab row")
        #expect(!zone.contains(CGPoint(x: 30, y: frames.bar.minY - 1)), "the page above the bar")
        #expect(abs(zone.maxX - 108.5) < 0.01, "halfway between the button and the pill")

        func drag(_ vx: CGFloat, _ vy: CGFloat, inZone: Bool = true, previous: Bool = true) -> MobileSwipe.BarDrag {
            MobileSwipe.barDrag(velocity: CGPoint(x: vx, y: vy), startsInPreviousTabZone: inZone, hasPreviousTab: previous)
        }
        #expect(drag(0, -900) == .previousTab)
        #expect(drag(700, -600) == .previousTab, "a thumb's flick leaning towards the middle")
        #expect(drag(-500, -400) == .previousTab)
        #expect(drag(900, -300) == .neighbour, "close to flat is a swipe along the bar")
        #expect(drag(900, 0) == .neighbour)
        #expect(drag(0, -900, inZone: false) == .tabRow)
        #expect(drag(700, -600, inZone: false) == .neighbour)
        #expect(drag(0, -900, previous: false) == .tabRow, "one tab: nothing to flick to, so the row opens")
    }

    /// Arc Search 1.49 (the reporter's recording): a drag up from the "+" pill pulls the search
    /// sheet out under the finger, and it opens once let go far enough up or flicked.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/623")) func aDragUpFromThePillPullsTheSearchSheetOut() {
        let size = CGSize(width: 393, height: 852)
        let frames = MobileBottomBar.frames(in: size, safeBottom: 34)
        let zone = MobileBottomBar.searchPullZone(in: size, safeBottom: 34)
        #expect(zone.contains(frames.pill.insetBy(dx: -6, dy: -6)), "the pill and its slop")
        #expect(!zone.intersects(MobileBottomBar.previousTabZone(in: size, safeBottom: 34)), "the tab button keeps its flick")
        #expect(!zone.intersects(frames.menu), "and the menu button its own")
        #expect(zone.contains(CGPoint(x: 196, y: 850)), "down to the screen's edge")
        #expect(!zone.contains(CGPoint(x: 196, y: frames.bar.minY - 1)), "not the page above the bar")
        #expect(!zone.contains(CGPoint(x: 275, y: frames.pill.midY)), "the bar between the pill and the menu drags the tab row")

        func drag(_ vx: CGFloat, _ vy: CGFloat, onPill: Bool = true) -> MobileSwipe.BarDrag {
            MobileSwipe.barDrag(velocity: CGPoint(x: vx, y: vy), startsInPreviousTabZone: false, hasPreviousTab: true,
                                startsInSearchPullZone: onPill)
        }
        #expect(drag(0, -800) == .searchSheet)
        #expect(drag(300, -500) == .searchSheet, "leaning a little")
        #expect(drag(800, -200) == .neighbour, "along the bar from the pill still changes tab")
        #expect(drag(0, -800, onPill: false) == .tabRow, "from beside the pill the row opens")

        #expect(MobileSwipe.searchPullProgress(dragUp: 0) == 0)
        #expect(MobileSwipe.searchPullProgress(dragUp: 130) == 0.5)
        #expect(MobileSwipe.searchPullProgress(dragUp: 600) == 1)
        #expect(MobileSwipe.searchPullOpens(dragUp: 150, velocityUp: 0))
        #expect(!MobileSwipe.searchPullOpens(dragUp: 60, velocityUp: 0), "too short: back into the pill")
        #expect(MobileSwipe.searchPullOpens(dragUp: 40, velocityUp: 800), "a flick")
        #expect(!MobileSwipe.searchPullOpens(dragUp: 200, velocityUp: -600), "pulled back down before letting go")
    }

    /// The open sheet goes down with a drag from anywhere on it, its suggestions included, as in
    /// Arc Search; scrolled suggestions scroll back first.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/623")) func theWholeSheetDragsDown() {
        #expect(MobileSwipe.sheetDragStarts(velocity: CGPoint(x: 0, y: 600), onList: false, listOffset: 0))
        #expect(MobileSwipe.sheetDragStarts(velocity: CGPoint(x: 0, y: 600), onList: true, listOffset: 0), "on the suggestions")
        #expect(!MobileSwipe.sheetDragStarts(velocity: CGPoint(x: 0, y: 600), onList: true, listOffset: 112), "scrolled: they scroll back")
        #expect(!MobileSwipe.sheetDragStarts(velocity: CGPoint(x: 0, y: -600), onList: true, listOffset: 0), "up scrolls the suggestions")
        #expect(!MobileSwipe.sheetDragStarts(velocity: CGPoint(x: 600, y: 100), onList: false, listOffset: 0))
    }

    @Test func pullToRefreshActsOnRelease() {
        #expect(MobileSwipe.refreshes(pullAtRelease: 130))
        #expect(!MobileSwipe.refreshes(pullAtRelease: 100))
    }

    /// Pushing a pull back past the top hands the rest of the drag to the page's scrolling,
    /// instead of making the finger lift and start a second gesture.
    @Test func pushingAPullBackPastTheTopHandsOffToScrolling() {
        #expect(MobileSwipe.pullHandsOff(pull: 0))
        #expect(MobileSwipe.pullHandsOff(pull: -4))
        #expect(!MobileSwipe.pullHandsOff(pull: 6))
    }

    /// #655: the open sheet dragged down keeps its top under the finger (the keyboard goes as the drag starts) and
    /// sinks into the pill when let go far enough down or flicked; a short, slow drag lets it rise back open.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/655"))
    func theOpenSheetGoesDownTheWayItCameUp() {
        #expect(MobileSwipe.sheetDragDownPull(startPull: 420, dragDown: 0) == 420)
        #expect(MobileSwipe.sheetDragDownPull(startPull: 420, dragDown: 150) == 270)
        #expect(MobileSwipe.sheetDragDownPull(startPull: 420, dragDown: 600) == 0)
        #expect(MobileSwipe.sheetDragDownPull(startPull: 420, dragDown: -30) == 450, "back up past where it started")
        #expect(MobileSwipe.sheetDragDownCloses(dragDown: 120, velocityDown: 0))
        #expect(MobileSwipe.sheetDragDownCloses(dragDown: 30, velocityDown: 900))
        #expect(!MobileSwipe.sheetDragDownCloses(dragDown: 40, velocityDown: 100))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/655"))
    func aSheetBelowTheKeyboardsTopIsOutOfSight() {
        #expect(MobileSwipe.sheetUnderKeyboard(sheetTop: 600, keyboardTop: 583))
        #expect(!MobileSwipe.sheetUnderKeyboard(sheetTop: 300, keyboardTop: 583))
        #expect(!MobileSwipe.sheetUnderKeyboard(sheetTop: 700, keyboardTop: nil), "no keyboard: nothing covers it")
    }
}

struct MobileSummaryTests {
    @Test func thePageIsCutAtASentenceToFitTheModel() {
        let sentence = "This is a sentence about pizza. "
        let long = String(repeating: sentence, count: 400)
        let clipped = MobileSummary.clipped(long)
        #expect(clipped.count <= MobileSummary.maxTextLength)
        #expect(clipped.hasSuffix("pizza."))
        #expect(MobileSummary.clipped("a   b\n\n\n  c ") == "a b\nc")
        #expect(MobileSummary.prompt(title: "Pizza", text: "Dough.", language: "Danish")
            == "Answer in Danish.\n\nWEB PAGE:\n<webpage>\nTitle: Pizza\nDough.\n</webpage>")
    }

    @Test func aPageNeedsSomeTextToBeSummarized() {
        #expect(!MobileSummary.canSummarize(text: "Sign in"))
        #expect(MobileSummary.canSummarize(text: String(repeating: "Words about a thing. ", count: 20)))
    }

    @Test func anAnswerIsTidiedAndAnEmptyOneIsNoAnswer() {
        let answer = MobileSummary.Answer(overview: "  About pizza.\n", sections: [
            .init(title: " Dough ", body: "Flour and water."), .init(title: "", body: "No title"), .init(title: "Empty", body: "  "),
        ])
        #expect(answer.cleaned == MobileSummary.Answer(overview: "About pizza.", sections: [.init(title: "Dough", body: "Flour and water.")]))
        #expect(MobileSummary.Answer(overview: " ", sections: []).cleaned == nil)
        #expect(MobileSummary.fakeAnswer(title: "T", text: "One. Two. Three.").sections.map(\.body) == ["Two.", "Three."])
    }
}

struct MobileBrowseForMeTests {
    /// DuckDuckGo's HTML results, trimmed to two results and an ad (its markup, 11 Nov 2026).
    static let results = """
    <div class="result results_links results_links_deep result--ad">
      <a rel="nofollow" class="result__a" href="https://duckduckgo.com/y.js?ad_domain=shop.example&amp;u3=x">Buy Pizza Ovens</a>
      <a class="result__snippet" href="https://duckduckgo.com/y.js?ad_domain=shop.example">An ad.</a>
    </div>
    <div class="result results_links results_links_deep web-result">
      <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fpizza%3Fa%3D1%26b%3D2&amp;rut=abc">Neapolitan <b>pizza</b> &amp; its dough</a></h2>
      <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fpizza">A soft, thin <b>pizza</b> from Naples.</a>
    </div>
    <div class="result results_links results_links_deep web-result">
      <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fother&amp;rut=def">Same site again</a></h2>
      <a class="result__snippet" href="#">More.</a>
    </div>
    <div class="result results_links results_links_deep web-result">
      <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FPizza&amp;rut=ghi">Pizza - Wikipedia</a></h2>
      <a class="result__snippet" href="#">Pizza is a dish.</a>
    </div>
    """

    @Test func readsTheResultsAndLeavesAdsOut() {
        let hits = MobileBrowseForMe.hits(fromResultsHTML: Self.results)
        #expect(hits.map(\.url) == ["https://www.example.com/pizza?a=1&b=2", "https://www.example.com/other", "https://en.wikipedia.org/wiki/Pizza"])
        #expect(hits[0].title == "Neapolitan pizza & its dough")
        #expect(hits[0].snippet == "A soft, thin pizza from Naples.")
        #expect(hits[0].host == "example.com")
        #expect(MobileBrowseForMe.pick(hits).map(\.host) == ["example.com", "en.wikipedia.org"])
        #expect(MobileBrowseForMe.hits(fromResultsHTML: "<html>nothing</html>").isEmpty)
    }

    @Test func theQueryGoesToDuckDuckGosPlainResults() {
        #expect(MobileBrowseForMe.searchURL("what to do & see")?.absoluteString == "https://html.duckduckgo.com/html/?q=what%20to%20do%20%26%20see")
    }

    @Test func thePromptGivesEachPageItsSiteAndAClippedText() {
        let source = MobileBrowseForMe.Source(hit: .init(title: "T", url: "https://www.example.com/a"), title: "Pizza", text: String(repeating: "Dough rests. ", count: 100))
        let prompt = MobileBrowseForMe.prompt(query: "pizza", sources: [source], language: "English")
        #expect(prompt.hasPrefix("Answer in English.\n\nQUESTION: pizza\n\nWEB PAGES:\n<page 1 site=\"example.com\">\nPizza\nDough rests."))
        #expect(prompt.count < 700)
    }

    @Test func aTabRemembersItsQuery() {
        let address = MobileBrowseForMe.tabAddress(query: "what to do at joshua tree?")
        #expect(MobileBrowseForMe.query(fromTabAddress: address) == "what to do at joshua tree?")
        #expect(URL(string: address)?.host == nil)
        #expect(MobileBrowseForMe.query(fromTabAddress: "https://example.com") == nil)
    }

    @Test func thePageEscapesWhatItWasGiven() {
        let source = MobileBrowseForMe.Source(hit: .init(title: "Hit", url: "https://example.com/a?x=1&y=2"), title: "<b>Title</b>", text: "", image: "/pic.jpg")
        let answer = MobileBrowseForMe.Answer(title: "A <script>", points: [.init(emoji: "🍕", term: "Dough", text: "Rests & rises.")],
                                              sections: [.init(heading: "Oven", text: "400 \"degrees\".")])
        let html = MobileBrowseForMe.pageHTML(query: "pizza <i>", answer: answer, sources: [source], searchURL: "https://duckduckgo.com/?q=pizza")
        #expect(html.contains("<title>A &lt;script&gt;</title>"))
        #expect(html.contains("<span>pizza &lt;i&gt;</span>"))
        #expect(html.contains("<b>Dough</b> — Rests &amp; rises."))
        #expect(html.contains("href=\"https://example.com/a?x=1&amp;y=2\""))
        #expect(html.contains("src=\"https://example.com/pic.jpg\""))
        #expect(html.contains("Read 1 web page<"))
        #expect(!html.contains("<script>"))
    }

    @Test func anAnswerWithNothingInItIsNoAnswer() {
        #expect(MobileBrowseForMe.Answer(title: "T", points: [.init(emoji: "", term: "", text: " ")], sections: []).cleaned == nil)
        #expect(MobileBrowseForMe.readingLabel(6) == "Reading 6 web pages")
    }
}

struct MobileSpacesTests {
    /// A Mac sidebar: one space with a pinned tab, a folder holding a tab, and a Today tab; and
    /// a second, empty space.
    static func sidebar() -> (SidebarDocument, folder: UUID) {
        var document = SidebarDocument.fresh()
        let space = document.spaces[0]
        var pinned = SidebarItem.tab("https://mail.example/inbox", title: "Mail", parent: space.pinnedContainerID)
        pinned.title = "Inbox"
        var folder = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let inside = SidebarItem.tab("https://docs.example/", title: "Docs", parent: folder.id)
        folder.children = [inside.id]
        let today = SidebarItem.tab("https://news.example/story", title: "", parent: space.todayContainerID)
        document.items += [pinned, folder, inside, today]
        for (container, children) in [(space.pinnedContainerID, [pinned.id, folder.id]), (space.todayContainerID, [today.id])] {
            let index = document.items.firstIndex { $0.id == container }!
            document.items[index].children = children
        }
        let secondID = UUID()
        let containers = [SidebarItem.container(.favorites(spaceID: secondID)), .container(.pinned(spaceID: secondID)), .container(.today(spaceID: secondID))]
        document.items += containers
        document.spaces.append(Space(id: secondID, title: "Play", emoji: "🎮", theme: SpaceTheme.presets[1], favoritesContainerID: containers[0].id,
                                     pinnedContainerID: containers[1].id, todayContainerID: containers[2].id, createdAt: Date()))
        document.spaceOrder.append(secondID)
        return (document, folder.id)
    }

    /// Arc Search's Spaces sheet (Victor's screenshots, 13 Nov): the pinned tabs and folders,
    /// folders shut until tapped, a line, then Today. Favorites stay out, as Arc Search leaves out
    /// the desktop's favorites.
    @Test func aSpaceListsItsPinsFoldersAndTodayTabs() {
        var (document, folder) = Self.sidebar()
        let space = document.spaces[0]
        let favorite = SidebarItem.tab("https://fav.example/", title: "Favorite", parent: space.favoritesContainerID)
        document.items.append(favorite)
        let favorites = document.items.firstIndex { $0.id == space.favoritesContainerID }!
        document.items[favorites].children = [favorite.id]
        let spaces = MobileSpaces.spaces(in: document)
        #expect(spaces.map(\.title) == ["Personal", "Play"])
        #expect(spaces[0].rows.map(\.title) == ["Inbox", "Work", "Today", "news.example"])
        #expect(spaces[0].rows[0].kind == .tab(url: "https://mail.example/inbox"))
        #expect(spaces[0].rows[1].kind == .folder(open: false))
        #expect(spaces[0].rows[2].kind == .todayHeader)
        #expect(spaces[1].rows.isEmpty)
        #expect(spaces[0].colors == SpaceTheme.presets[0].colors)
        let opened = MobileSpaces.spaces(in: document, openFolders: [folder])
        #expect(opened[0].rows.map(\.title) == ["Inbox", "Work", "Docs", "Today", "news.example"])
        #expect(opened[0].rows.map(\.depth) == [0, 0, 1, 0, 0])
        #expect(opened[0].rows[1].kind == .folder(open: true))
    }

    /// The sheet reads the Mac's sidebar each time it opens, and that read takes a moment. A
    /// reopened sheet showed "Connecting" (a bright flash in dark mode) for it every time; it now
    /// opens on what the last read found, and "Connecting" is only for the first opening.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/556")) func aReopenedSheetShowsTheLastReadAtOnce() {
        var sheet = MobileSpacesSheet()
        #expect(sheet.opening == nil, "nothing read yet: Connecting")
        let (document, _) = Self.sidebar()
        sheet.remember(.spaces(document), askedICloud: true)
        #expect(sheet.opening == .spaces(document))
        var changed = document
        changed.spaces.removeLast()
        sheet.remember(.spaces(changed), askedICloud: true)
        #expect(sheet.opening == .spaces(changed), "the newer read replaces it")
        sheet.remember(.nothingSynced, askedICloud: true)
        #expect(sheet.opening == .nothingSynced, "Sync turned off on the Mac shows as such")
        var signedOut = MobileSpacesSheet()
        signedOut.remember(.unavailable, askedICloud: true)
        #expect(signedOut.opening == .unavailable, "without iCloud the explanation shows at once too")
    }

    /// The tab row's look for its sync card doesn't ask iCloud: Spaces it finds make the first
    /// opening instant, a file not brought down yet doesn't hide Spaces read before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/556")) func aQuickLookOnlyAddsSpaces() {
        let (document, _) = Self.sidebar()
        var sheet = MobileSpacesSheet()
        sheet.remember(.nothingSynced, askedICloud: false)
        #expect(sheet.opening == nil)
        sheet.remember(.spaces(document), askedICloud: false)
        #expect(sheet.opening == .spaces(document))
        sheet.remember(.nothingSynced, askedICloud: false)
        sheet.remember(.unavailable, askedICloud: false)
        #expect(sheet.opening == .spaces(document))
    }

    @Test func theSyncedFileReadsBack() throws {
        let (document, _) = Self.sidebar()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        #expect(MobileSpaces.document(from: data)?.spaces.count == 2)
        #expect(MobileSpaces.document(from: Data("{}".utf8)) == nil)
    }

    /// The phone reads the sidebar.json the Mac saves, dates as ISO 8601 text and all. A plain
    /// decoder wants numbers there, so every real Mac's Spaces came out as "nothing synced".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/465")) func theMacsSavedSidebarReads() throws {
        let url = try #require(Bundle.module.url(forResource: "sidebar.json", withExtension: nil, subdirectory: "Fixtures/Model/recorded"))
        let document = try #require(MobileSpaces.document(from: Data(contentsOf: url)))
        #expect(!document.spaces.isEmpty)
        #expect(!MobileSpaces.spaces(in: document).isEmpty)
    }

    /// The phone's build can be older than the Mac that wrote the file. An item kind, a folder
    /// symbol, a split layout or a whole Space shape the phone doesn't know yet leaves that one
    /// thing out; the rest of the Mac's Spaces still show, never "nothing synced".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/465")) func aNewerMacsSidebarStillReads() throws {
        let document = try #require(MobileSpaces.document(from: Data(Self.newerMacSidebar.utf8)))
        let spaces = MobileSpaces.spaces(in: document)
        #expect(spaces.map(\.title) == ["Work"])
        #expect(spaces[0].symbol == "briefcase")
        #expect(spaces[0].rows.map(\.title) == ["Inbox", "Odd", "Linear", "Left", "Right", "Notes", "Today", "Story"])
        #expect(spaces[0].rows[1].kind == .folder(open: false))
        let opened = MobileSpaces.spaces(in: document, openFolders: [UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!])
        #expect(opened[0].rows.map(\.title).prefix(3) == ["Inbox", "Odd", "Docs"])
        #expect(MobileSpaces.document(from: Data(#"{"spaces": "soon"}"#.utf8)) == nil)
    }

    /// A Mac sidebar.json from a later Cra than this one: today's newest fields (folder symbols,
    /// live folders, splits, tab groups, theme variants, per-Space engines) plus keys, item kinds
    /// ("easel", "note"), a container kind, a split orientation, a folder symbol and a Space
    /// shape that no Cra writes yet.
    static let newerMacSidebar = #"""
    {
      "version": 3,
      "boosts": [{"host": "example.com"}],
      "spaceOrder": ["00000000-0000-0000-0000-00000000000A", "00000000-0000-0000-0000-00000000000B"],
      "spaces": [
        {"id": "00000000-0000-0000-0000-00000000000A", "title": "Work", "emoji": "", "symbol": "briefcase",
         "searchEngine": "ddg", "createdAt": "2026-11-17T09:00:00Z", "wallpaper": {"kind": "gradient"},
         "theme": {"colors": ["#A687C8", "#3A3660"], "intensity": 0.8, "noise": 0.1, "appearance": "auto", "vibrant": true,
                   "accent": "#FF00AA", "solid": false, "key": ["#A687C8"], "grain": 0.3,
                   "dark": {"colors": ["#221133"], "intensity": 0.6, "noise": 0.1}},
         "favoritesContainerID": "00000000-0000-0000-0000-0000000000F1",
         "pinnedContainerID": "00000000-0000-0000-0000-0000000000F2",
         "todayContainerID": "00000000-0000-0000-0000-0000000000F3"},
        {"id": "00000000-0000-0000-0000-00000000000B", "title": "Later", "theme": "aurora", "layout": {"rows": 2},
         "createdAt": "2026-11-17T09:00:00Z"}
      ],
      "items": [
        {"id": "00000000-0000-0000-0000-0000000000F1", "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"container": {"_0": {"favorites": {"spaceID": "00000000-0000-0000-0000-00000000000A"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000F2", "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "children": ["00000000-0000-0000-0000-0000000000B1", "00000000-0000-0000-0000-0000000000B2", "00000000-0000-0000-0000-0000000000B4",
                      "00000000-0000-0000-0000-0000000000E1", "00000000-0000-0000-0000-0000000000C1", "00000000-0000-0000-0000-0000000000B6"],
         "data": {"container": {"_0": {"pinned": {"spaceID": "00000000-0000-0000-0000-00000000000A"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000F3", "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "children": ["00000000-0000-0000-0000-0000000000D1", "00000000-0000-0000-0000-0000000000E2"],
         "data": {"container": {"_0": {"today": {"spaceID": "00000000-0000-0000-0000-00000000000A"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000F4", "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"container": {"_0": {"standalone": {"windowID": "00000000-0000-0000-0000-0000000000F9"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000B1", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Inbox",
         "children": [], "isUnread": true, "createdAt": "2026-11-17T09:00:00Z", "pinnedAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://mail.example/inbox", "savedURL": "https://mail.example/", "savedTitle": "Mail",
                  "muted": false, "timeLastActiveAt": "2026-11-17T10:00:00Z", "referrerID": "00000000-0000-0000-0000-0000000000B6",
                  "faviconKey": "mail.example", "customIconKey": "pick-1", "tileColor": "#112233", "themeColor": "#445566",
                  "homeTitle": "Mail", "liveItemURL": "https://github.com/a/b/pull/1", "liveSubtitle": "octocat",
                  "liveGoneAt": "2026-11-17T11:00:00Z", "readingProgress": 0.4}}}},
        {"id": "00000000-0000-0000-0000-0000000000B2", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Odd",
         "children": ["00000000-0000-0000-0000-0000000000B3"], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "folderIcon": "tinted", "folderSymbol": "rocket", "tabGroup": false, "data": {"folder": {}}},
        {"id": "00000000-0000-0000-0000-0000000000B3", "parentID": "00000000-0000-0000-0000-0000000000B2",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://docs.example", "savedURL": "https://docs.example", "savedTitle": "Docs", "muted": false}}}},
        {"id": "00000000-0000-0000-0000-0000000000B4", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Linear",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z", "folderSymbol": "code",
         "pluginFolder": {"source": "linear", "plugin": {"id": "linear", "settings": {"team": "CRA"}}, "hiddenItems": [],
                          "lastFetch": "2026-11-17T09:30:00Z", "lastError": "quotaExceeded"},
         "data": {"folder": {}}},
        {"id": "00000000-0000-0000-0000-0000000000E1", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Sketches",
         "children": ["00000000-0000-0000-0000-0000000000E3"], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"easel": {"_0": {"canvasID": "00000000-0000-0000-0000-0000000000E9"}}}},
        {"id": "00000000-0000-0000-0000-0000000000E3", "parentID": "00000000-0000-0000-0000-0000000000E1",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://sketch.example", "savedURL": "https://sketch.example", "savedTitle": "Sketch", "muted": false}}}},
        {"id": "00000000-0000-0000-0000-0000000000C1", "parentID": "00000000-0000-0000-0000-0000000000F2",
         "children": ["00000000-0000-0000-0000-0000000000C2", "00000000-0000-0000-0000-0000000000C3"], "isUnread": false,
         "createdAt": "2026-11-17T09:00:00Z",
         "data": {"split": {"_0": {"orientation": "grid", "focusTabID": "00000000-0000-0000-0000-0000000000C2",
                  "widthFactors": {"00000000-0000-0000-0000-0000000000C2": 1, "00000000-0000-0000-0000-0000000000C3": 1}}}}},
        {"id": "00000000-0000-0000-0000-0000000000C2", "parentID": "00000000-0000-0000-0000-0000000000C1",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://left.example", "savedURL": "https://left.example", "savedTitle": "Left", "muted": false}}}},
        {"id": "00000000-0000-0000-0000-0000000000C3", "parentID": "00000000-0000-0000-0000-0000000000C1",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://right.example", "savedURL": "https://right.example", "savedTitle": "Right", "muted": true}}}},
        {"id": "00000000-0000-0000-0000-0000000000B6", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Notes",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://notes.example", "savedURL": "https://notes.example", "savedTitle": "", "muted": false,
                  "sleep": {"after": "never"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000D1", "parentID": "00000000-0000-0000-0000-0000000000F3",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://news.example/story", "savedURL": "https://news.example/story", "savedTitle": "Story", "muted": false}}}},
        {"id": "00000000-0000-0000-0000-0000000000E2", "parentID": "00000000-0000-0000-0000-0000000000F3", "title": "Scratch",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z", "data": {"note": {"text": "hi"}}}
      ],
      "profiles": [{"id": "00000000-0000-0000-0000-0000000000AA", "name": "Work", "color": "#00FF00"}],
      "profileFavorites": [{"containerID": "00000000-0000-0000-0000-0000000000F1", "pinned": true}]
    }
    """#
}

struct MobileFavoritesTests {
    @Test func aPageTogglesInAndOutWhateverItsTrackers() {
        var favorites = MobileFavorites()
        let added = favorites.toggle(url: "https://example.com/a?utm_source=x", title: "A")
        #expect(added)
        #expect(favorites.contains("https://example.com/a#part"))
        #expect(!favorites.contains("https://example.com/b"))
        let stillThere = favorites.toggle(url: "https://example.com/a", title: "A")
        #expect(!stillThere)
        #expect(favorites.sites.isEmpty)
        favorites.toggle(url: "https://example.org/", title: "")
        #expect(favorites.sites[0].title == "example.org")
    }

    @Test func fourShowUnderTheFieldInTheirOrder() throws {
        var favorites = MobileFavorites()
        for name in ["a", "b", "c", "d", "e"] { favorites.toggle(url: "https://\(name).example", title: name) }
        favorites.move(from: 4, to: 0)
        #expect(favorites.shown().map(\.title) == ["e", "a", "b", "c"])
        let saved = try JSONEncoder().encode(favorites)
        #expect(try JSONDecoder().decode(MobileFavorites.self, from: saved) == favorites)
        #expect(try JSONDecoder().decode(MobileFavorites.self, from: Data("{}".utf8)).sites.isEmpty)
    }
}

struct MobileMotionTests {
    /// The shared ease-out starts quick, ends soft and stays inside 0...1.
    @Test func theEaseOutLeavesQuicklyAndSettlesSoftly() {
        #expect(MobileMotion.easeOut(0) == 0 && MobileMotion.easeOut(1) == 1)
        #expect(MobileMotion.easeOut(0.5) == 0.875)
        #expect(MobileMotion.easeOut(-1) == 0 && MobileMotion.easeOut(2) == 1)
        #expect(MobileMotion.easeOut(0.1) > 0.25, "a quick start")
        #expect(MobileMotion.easeOut(0.9) > 0.99, "a soft end")
    }

    /// Arc Search's tab row: each frame leaves about 0.54 of the distance of the frame before,
    /// once the motion is under way.
    @Test func theTabRowSettlesAtArcSearchsRate() {
        let spring = MobileMotion.tabRowSettle
        let frame = 1.0 / 30
        let ratio = spring.remaining(after: 6 * frame) / spring.remaining(after: 5 * frame)
        #expect(abs(ratio - 0.6) < 0.08)
        #expect(spring.remaining(after: 0.3) < 0.03)
        #expect(abs(spring.stiffness - 341.5) < 1 && abs(spring.damping - 36.96) < 0.1)
    }

    @Test func aCardIsItsPageWithinFiveFrames() {
        #expect(MobileMotion.tabOpen.remaining(after: 5.0 / 30) < 0.1)
    }

    /// The new tab drawer let go on its way down settles with a small overshoot, not a critical
    /// damp.
    @Test func theNewTabDrawerSettlesWithASmallOvershoot() {
        let spring = MobileNewTabDrawer.bounce
        #expect(spring.dampingRatio > 0.7 && spring.dampingRatio < 1)
        #expect(spring.response > 0.2 && spring.response < MobileSearchMotion.settleDuration)
        #expect(spring.overshoot > 0.005 && spring.overshoot < 0.06)
    }

    /// The field's buttons come in with a spring that overshoots visibly, from well under their size.
    @Test func theFieldsButtonsComeInWithAnOvershoot() {
        #expect(MobileMotion.accessoryEnter.overshoot > 0.05)
        #expect(MobileSearchMotion.accessoryEnterScale < MobileSearchMotion.accessoryLeaveScale)
    }

    /// The incognito word toggled off, on and off again within one slide: only the last slide's
    /// end may hide the word. Before, the first slide's end saw incognito off and hid the word
    /// halfway through the last one.
    @Test func anOlderMovesEndDoesNotCutTheLatestOneShort() {
        var moves = MobileMotion.Ticket()
        let firstOff = moves.next()
        _ = moves.next()
        let lastOff = moves.next()
        #expect(!moves.isCurrent(firstOff), "the first slide back has been overtaken")
        #expect(moves.isCurrent(lastOff))
    }

    /// A spring's overshoot: none when critically damped, more the less damped it is.
    @Test func aSpringsOvershootGrowsAsItsDampingFalls() {
        #expect(MobileMotion.Spring(response: 0.3, dampingRatio: 1).overshoot == 0)
        #expect(MobileMotion.Spring(response: 0.3, dampingRatio: 1.2).overshoot == 0)
        let half = MobileMotion.Spring(response: 0.3, dampingRatio: 0.5).overshoot
        #expect(abs(half - 0.163) < 0.001)
        #expect(MobileMotion.Spring(response: 0.3, dampingRatio: 0.8).overshoot < half)
    }

    @Test func draggingTheBarUpOpensTheRowByDistanceOrFlick() {
        #expect(MobileMotion.switcherProgress(dragUp: 150) == 0.5)
        #expect(MobileMotion.switcherProgress(dragUp: 900) == 1)
        #expect(MobileMotion.opensSwitcher(dragUp: 120, velocityUp: 0))
        #expect(MobileMotion.opensSwitcher(dragUp: 40, velocityUp: 800))
        #expect(!MobileMotion.opensSwitcher(dragUp: 40, velocityUp: 100))
    }

    /// The page card on a flick up shrinks straight with the hand, all the way to the top of the
    /// screen, rounded at the device's corners from its first frame.
    @Test func theFlickedPageShrinksStraightWithTheHand() {
        let startY: CGFloat = 800
        #expect(MobileMotion.flickCardProgress(dragUp: 0, startY: startY) == 0)
        #expect(abs(MobileMotion.flickCardProgress(dragUp: 400, startY: startY) - 0.5) < 0.001, "straight, no easing")
        #expect(MobileMotion.flickCardProgress(dragUp: 800, startY: startY) == 1)
        #expect(MobileMotion.flickCardProgress(dragUp: 900, startY: startY) == 1)
        let steps = (1...8).map { MobileMotion.flickCardProgress(dragUp: CGFloat($0) * 100, startY: startY) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 }, "never goes back up")

        #expect(MobileMotion.flickCornerRadius == 44, "the device's own corners, from the first frame")
    }

    /// The page shrinks into the bottom-left with the screen's own shape, so the tab's top colour
    /// and what lies under the bar are in it: 60 % of the screen's width, 10 pt above the bar.
    @Test func theFlickedPageBecomesACardInTheBottomLeft() {
        let screen = CGRect(x: 0, y: 0, width: 393, height: 852)
        let card = MobileMotion.flickCardFrame(in: screen, aboveBar: 776, safeTop: 59)
        #expect(abs(card.height - (776 - 59) * 0.5) < 0.001, "half the tab area's height")
        #expect(abs(card.width - card.height * screen.width / screen.height) < 0.001, "the screen's own shape")
        #expect(card.minX == screen.minX + 16)
        #expect(abs(card.maxY - 752) < 0.001, "16 pt from the left, 24 pt above the bar")
        #expect(card.minY > screen.minY, "anchored above the bar, growing up")
        let start = MobileMotion.flickStartFrame(in: screen, aboveBar: 776)
        #expect(start.minX == screen.minX + 20 && start.maxX == screen.maxX - 20, "20 pt at the sides")
        #expect(start.minY == 20, "20 pt from the top of the screen")
        #expect(abs(start.maxY - 756) < 0.001, "20 pt above the tab bar")
    }

    /// The tab being dragged up can grow only as far as its bottom reaching the screen's edge.
    @Test func theDraggedTabNeverPassesTheScreensBottom() {
        #expect(abs(MobileMotion.flickCardLimit(fingerY: 600, screenHeight: 852) - 252 / 0.55) < 0.001)
        let height = MobileMotion.flickCardLimit(fingerY: 600, screenHeight: 852)
        #expect(abs(600 + 0.55 * height - 852) < 0.001)
        #expect(MobileMotion.flickCardLimit(fingerY: 900, screenHeight: 852) == 0)
    }

    /// The card hangs from the finger: a still hand leaves it straight, and a sideways pull sets
    /// it rocking and settling straight again.
    @Test func theFlickedCardSwingsFromTheFingerAndSettlesStraight() {
        #expect(MobileMotion.flickSwingTarget(velocityX: 0) == 0)
        #expect(MobileMotion.flickSwingTarget(velocityX: 6000) == MobileMotion.flickSwingTarget(velocityX: 60_000))
        #expect(MobileMotion.flickSwingTarget(velocityX: -6000) == -MobileMotion.flickSwingTarget(velocityX: 6000))
        var angle: CGFloat = 0, speed: CGFloat = 0
        for _ in 0..<120 {
            (angle, speed) = MobileMotion.flickSwingStep(angle: angle, speed: speed, target: 0, dt: 1.0 / 60)
        }
        #expect(angle == 0 && speed == 0, "a still hand never tips it")
        var peak: CGFloat = 0, sides = 0
        var last: CGFloat = 0
        for frame in 0..<36 {
            let target = MobileMotion.flickSwingTarget(velocityX: frame < 6 ? 900 : 0)
            (angle, speed) = MobileMotion.flickSwingStep(angle: angle, speed: speed, target: target, dt: 1.0 / 60)
            peak = max(peak, abs(angle))
            if angle * last < 0 { sides += 1 }
            last = angle
        }
        #expect(peak > 0.005 && peak < 0.1, "a sideways pull tips it, five degrees at most")
        #expect(abs(MobileMotion.flickSwingTarget(velocityX: 60_000) - 5 * .pi / 180) < 0.0001)
        #expect(sides >= 2, "it rocks back and forth, elastic rather than damped flat")
        #expect(abs(angle) < 0.01, "and hangs straight again within half a second")
    }
}

struct MobileOnboardingTests {

    @Test func longPhonesKeepThePhoneMock() {
        // Apple's published portrait sizes and landscape safe areas (spec 17a, 17b).
        for (window, left, right) in [(CGSize(width: 393, height: 852), CGFloat(0), CGFloat(0)),
                                      (CGSize(width: 852, height: 393), 59, 59),
                                      (CGSize(width: 375, height: 667), 0, 0),
                                      (CGSize(width: 667, height: 375), 0, 0)] {
            let mock = MobileOnboarding.mock(window: window, safeLeft: left, safeRight: right)
            #expect(mock.shape == .phone)
            #expect(mock.size == CGSize(width: 330, height: 640)) // Existing phone design.
            #expect(mock.logicalSize == CGSize(width: 330, height: 640)) // Existing phone design.
            #expect(mock.columnWidth == 330)
            #expect(mock.keyHeight == 30)
            #expect(mock.keyWidth == 26)
        }
    }

    @Test func iPadsKeepThePhoneMock() {
        // Apple's published 11-inch iPad sizes and side safe areas (spec 17c).
        for window in [CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 834)] {
            let mock = MobileOnboarding.mock(window: window, safeLeft: 0, safeRight: 0)
            #expect(mock.shape == .phone)
            #expect(mock.size == CGSize(width: 330, height: 640)) // Existing phone design.
            #expect(mock.logicalSize == CGSize(width: 330, height: 640)) // Existing phone design.
            #expect(mock.columnWidth == 330)
            #expect(mock.keyHeight == 30)
            #expect(mock.keyWidth == 26)
        }
    }

    @Test func closedMockMatchesTheWindow() {
        // Job 010 verify.md: closed window 466x678, side insets 0 and 84 (spec 17d).
        let mock = MobileOnboarding.mock(window: CGSize(width: 466, height: 678), safeLeft: 0, safeRight: 84)
        #expect(mock.shape == .duoClosed)
        #expect(mock.size.width == 330) // Spec's retained phone width.
        #expect(abs(mock.size.width / mock.size.height / (466.0 / 678) - 1) < 0.005)
        // Job 010 window, at the existing mock's 330 / Apple's 393 pt phone width.
        #expect(abs(mock.logicalSize.width - 466 * 330 / 393.0) < 0.01)
        #expect(abs(mock.logicalSize.height - 678 * 330 / 393.0) < 0.01)
        #expect(abs((mock.size.width / mock.logicalSize.width) / (mock.size.height / mock.logicalSize.height) - 1) < 0.005)
        #expect(mock.columnWidth == mock.logicalSize.width)
        #expect(mock.keyWidth == (mock.logicalSize.width - 52) / 10) // Existing keyboard margins.
        #expect(mock.keyHeight == 30) // Existing phone keyboard height.
    }

    @Test func openMockMatchesTheWindow() {
        // Job 010 verify.md: open window 951x669, side insets 0 and 84 (spec 17e).
        let mock = MobileOnboarding.mock(window: CGSize(width: 951, height: 669), safeLeft: 0, safeRight: 84)
        #expect(mock.shape == .duoOpen)
        #expect(mock.size.height == 450) // Spec's unfolded height above Next.
        #expect(abs(mock.size.width / mock.size.height / (951.0 / 669) - 1) < 0.005)
        // Job 010 window, at the existing mock's 330 / Apple's 393 pt phone width.
        #expect(abs(mock.logicalSize.width - 951 * 330 / 393.0) < 0.01)
        #expect(abs(mock.logicalSize.height - 669 * 330 / 393.0) < 0.01)
        #expect(abs((mock.size.width / mock.logicalSize.width) / (mock.size.height / mock.logicalSize.height) - 1) < 0.005)
        #expect(mock.columnWidth == 540) // SheetHost's wide content cap.
        #expect(mock.keyWidth == (0.82 * mock.logicalSize.width - 36) / 10) // Research keyboard: 82% row, nine gaps.
        #expect(mock.keyHeight == 36) // Research open keyboard, about 1.7:1 keys.
    }

    @Test func oneSidedInsetAloneDoesNotChooseAShortMock() {
        // Apple's 852x393 landscape size; synthetic one-sided 59 pt inset (spec 17f).
        let mock = MobileOnboarding.mock(window: CGSize(width: 852, height: 393), safeLeft: 0, safeRight: 59)
        #expect(mock.shape == .phone)
        #expect(mock.logicalSize == CGSize(width: 330, height: 640)) // Existing phone design.
        #expect(mock.columnWidth == 330)
        #expect(mock.keyWidth == 26)
        #expect(mock.keyHeight == 30)
    }

    @Test func splitViewKeepsThePhoneMock() {
        // Research's measured 469x669 Split View half; unmeasured insets supplied as 0 (spec 17g).
        let mock = MobileOnboarding.mock(window: CGSize(width: 469, height: 669), safeLeft: 0, safeRight: 0)
        #expect(mock.shape == .phone)
        #expect(mock.logicalSize == CGSize(width: 330, height: 640)) // Existing phone design.
        #expect(mock.columnWidth == 330)
        #expect(mock.keyWidth == 26)
        #expect(mock.keyHeight == 30)
    }

    @Test func postureMocksFitWithoutScaling() {
        // Job 010 window/insets; spec's default headings 66 closed and 33 open (spec 17h).
        for (window, available, heading) in [(CGSize(width: 466, height: 678), CGFloat(644), CGFloat(66)),
                                            (CGSize(width: 951, height: 669), 635, 33)] {
            let mock = MobileOnboarding.mock(window: window, safeLeft: 0, safeRight: 84)
            #expect(MobileOnboarding.fitScale(available: available, topInset: 0, bottomInset: 34,
                                             heading: heading, scalable: mock.size.height) == 1)
        }
    }
    @Test func iPhone17KeepsItsOnboardingLayout() {
        // Apple safe-area values for iPhone 17: 852 - 62 - 34 = 756; two-line heading from the spec, pending verifier measurement.
        #expect(MobileOnboarding.fitScale(available: 756, topInset: 62, bottomInset: 34, heading: 66, scalable: 640) == 1)
        // Spec: title 66, grid at 273 pt wide + 56 pt radios; reserve 18 + 50 + 16 for Next.
        #expect(MobileOnboarding.fitScale(available: 756, topInset: 62, bottomInset: 34, heading: 66, scalable: 329,
                                             topPadding: 50, spacing: 30, bottomReserved: 84) == 1)
    }

    @Test func closedScreenFitsTheDemo() {
        // Cra Duo closed, build.md: safe height 644; heading 32 1/3 on base, 64 2/3 after fitting on head.
        for heading: CGFloat in [32 + 1.0 / 3, 64 + 2.0 / 3] {
            // Measured top inset 0 and bottom inset 34; design padding 40, gap 24, mock 640.
            let fixed: CGFloat = 40 + heading + 24
            let scale = MobileOnboarding.fitScale(available: 644, topInset: 0, bottomInset: 34, heading: heading, scalable: 640)
            #expect(scale < 1)
            #expect(fixed + 640 * scale <= 644)
        }
    }

    @Test func openScreenFitsTheDemo() {
        // Cra Duo open: 669 - 0 - 34 = 635, one-line heading 33 (spec; measurement left to verifier).
        let fixed: CGFloat = 40 + 33 + 24
        let scale = MobileOnboarding.fitScale(available: 635, topInset: 0, bottomInset: 34, heading: 33, scalable: 640)
        #expect(scale < 1)
        #expect(fixed + 640 * scale <= 635)
    }

    @Test func bottomInsetLimitsTheCentringAllowance() {
        // Synthetic boundary: 100 + 640 - 671 = 69 pt overflow, between the 68 and 80 pt thresholds.
        let fixed: CGFloat = 100, scalable: CGFloat = 640, available: CGFloat = 671
        // Cra Duo closed insets measured in build.md: top 0, bottom 34; design top padding 40.
        let top: CGFloat = 0, bottom: CGFloat = 34
        let scale = MobileOnboarding.fitScale(available: available, topInset: top, bottomInset: bottom,
                                             heading: fixed - 40 - 24, scalable: scalable)
        #expect(scale < 1)
        #expect(abs(fixed + scalable * scale - available) < 1e-9)
    }

    @Test func iconReservesTheNextBlockWithoutCentring() {
        // Synthetic fit boundary: open screen's 635 pt safe height, two-line title 66, capped grid 360 + 56.
        let scale = MobileOnboarding.fitScale(available: 635, topInset: 0, bottomInset: 34, heading: 66,
                                             scalable: 416, topPadding: 50, spacing: 30, bottomReserved: 84)
        #expect(scale < 1)
        // Design Next block: 18 pt bottom spacer + 50 pt button + 16 pt gap.
        #expect(abs(50 + 66 + 30 + 416 * scale + 84 - 635) < 1e-9)
    }

    @Test func otherIPhonesKeepTheirOnboardingLayout() {
        // Apple safe-area values from the spec: 13 mini 812 - 50 - 34; 17 Pro Max 956 - 62 - 34.
        for available: CGFloat in [728, 860] {
            // Spec two-line heading 66 and 640 pt mock; narrowest grid 255 + 56, capped grid 360 + 56.
            #expect(MobileOnboarding.fitScale(available: available, topInset: available == 728 ? 50 : 62, bottomInset: 34, heading: 66, scalable: 640) == 1)
            #expect(MobileOnboarding.fitScale(available: available, topInset: available == 728 ? 50 : 62, bottomInset: 34, heading: 66,
                                             scalable: available == 728 ? 311 : 416, topPadding: 50, spacing: 30, bottomReserved: 84) == 1)
        }
    }

    @Test func fitScaleHonorsTheCentringBoundaryAndClamps() {
        // Constructed boundary fixtures: fixed 100, scalable 640, allowance 34 as on the measured closed screen.
        #expect(MobileOnboarding.fitScale(available: 740, topInset: 0, bottomInset: 34, heading: 36, scalable: 640) == 1)
        #expect(MobileOnboarding.fitScale(available: 800, topInset: 0, bottomInset: 34, heading: 36, scalable: 640) == 1)
        #expect(MobileOnboarding.fitScale(available: 672, topInset: 0, bottomInset: 34, heading: 36, scalable: 640) == 1)
        let scale = MobileOnboarding.fitScale(available: 671, topInset: 0, bottomInset: 34, heading: 36, scalable: 640)
        #expect(scale < 1)
        #expect(abs(100 + 640 * scale - 671) < 1e-9)
        #expect(MobileOnboarding.fitScale(available: 50, topInset: 0, bottomInset: 0, heading: 36, scalable: 640) == 0)
    }

    @Test func theStepsFollowArcSearchsOrderAndSkipAIWhereThereIsNone() {
        #expect(MobileOnboarding.steps(canUseAI: true) == [.welcome, .meet, .browseForMe, .pinch, .icon, .blocking, .defaultBrowser])
        #expect(MobileOnboarding.steps(canUseAI: false) == [.welcome, .meet, .icon, .blocking, .defaultBrowser])
        #expect(MobileOnboarding.buttonTitle(for: .defaultBrowser) == "Set as Default Browser")
        #expect(MobileOnboarding.defaultBrowserSteps == ["1. Open Cra in Settings", "2. Tap on \u{201C}Default Browser App\u{201D}", "3. Select Cra"])
        #expect(MobileOnboarding.plain(MobileOnboarding.browseTitle) == "Let Cra search and summarize for you")
        #expect(MobileOnboarding.plain(MobileOnboarding.welcomeTitle) == "Get what you want twice as fast.")
        #expect(!MobileOnboarding.showsNext(.pinch, tried: false) && MobileOnboarding.showsSkip(.pinch, tried: false))
        #expect(MobileOnboarding.showsNext(.browseForMe, tried: true) && !MobileOnboarding.showsSkip(.browseForMe, tried: true))
        #expect(MobileOnboarding.showsNext(.icon, tried: false) && !MobileOnboarding.showsSkip(.icon, tried: false))
        #expect(MobileOnboarding.isVivid(.blocking) && !MobileOnboarding.isVivid(.defaultBrowser))
        #expect(MobileOnboarding.buttonTitle(for: .welcome) == "Next")
        #expect(MobileOnboarding.buttonTitle(for: .blocking) == "Let’s go")
        #expect(MobileOnboarding.cards.map(\.title) == ["Protect your privacy", "Auto-archives old tabs", "Keep your logins", "Navigate faster"])
    }

    @Test func iconsMapToTheirAlternateNames() {
        #expect(MobileAppIcon.allCases.map(\.alternateName) == [
            nil, "AppIcon-Midnight", "AppIcon-Mono", "AppIcon-Violet", "AppIcon-Original", "AppIcon-Candy", "AppIcon-Hologram",
            "AppIcon-Neon", "AppIcon-FlutedGlass", "AppIcon-Schoolbook", "AppIcon-Colorful", "AppIcon-Canary", "AppIcon-EarlyBirds",
        ])
        #expect(MobileAppIcon(alternateName: "AppIcon-Violet") == .violet)
        #expect(MobileAppIcon(alternateName: nil) == .segments)
        #expect(MobileAppIcon(alternateName: "Gone") == .segments)
        #expect(MobileAppIcon.mono.previewName == "AppIcon-Mono-Preview")
        #expect(MobileAppIcon(alternateName: "AppIcon-FlutedGlass") == .flutedGlass)
    }

    /// The iPhone offers the Mac's icons under the Mac's names (Settings ▸ Icon): Arc's set by Provok came to the Mac
    /// on 23 Nov 2026 and was asked for on the iPhone on X (Chanan Krivisky). Cra's own four come first, so the ones
    /// onboarding offers are in reach on the sheet's sideways row; Arc's set follows in the Mac's order.
    @Test func iPhoneHasTheMacsIconsWithCrasOwnFirst() {
        #expect(MobileAppIcon.allCases.map(\.rawValue) == [
            "segments", "midnight", "mono", "violet", "original", "candy", "hologram", "neon", "fluted-glass",
            "schoolbook", "colorful", "canary", "early-birds",
        ])
        #expect(MobileAppIcon.allCases.map(\.label) == [
            "Cra", "Midnight", "Mono", "Violet", "Original", "Candy", "Hologram", "Neon", "Fluted Glass", "Schoolbook",
            "Colorful", "Canary", "Early Birds",
        ])
        #expect(Array(MobileAppIcon.allCases.prefix(4)) == MobileAppIcon.onboardingChoices)
        #expect(MobileAppIcon.earlyBirds.previewName == "AppIcon-EarlyBirds-Preview")
    }

    /// Onboarding's icon step keeps its two-by-two grid of Cra's own icons; the pickers in Settings have all of them.
    @Test func onboardingOffersCrasOwnFour() {
        #expect(MobileAppIcon.onboardingChoices == [.segments, .midnight, .mono, .violet])
        #expect(Set(MobileAppIcon.onboardingChoices).isSubset(of: MobileAppIcon.allCases))
    }
}

struct MobileDownloadsTests {
    /// Arc Search 1.16: downloads get sequential numbers so files aren't overwritten.
    @Test func aRepeatedDownloadIsNumberedNotOverwritten() {
        #expect(MobileDownloads.freeName(for: "report.pdf", taken: []) == "report.pdf")
        #expect(MobileDownloads.freeName(for: "report.pdf", taken: ["report.pdf"]) == "report 2.pdf")
        #expect(MobileDownloads.freeName(for: "report.pdf", taken: ["report.pdf", "report 2.pdf"]) == "report 3.pdf")
        #expect(MobileDownloads.freeName(for: "README", taken: ["README"]) == "README 2")
        #expect(MobileDownloads.freeName(for: "archive.tar.gz", taken: ["archive.tar.gz"]) == "archive.tar 2.gz")
    }

    @Test func aNameCannotLeaveTheFolderOrHide() {
        #expect(MobileDownloads.safeName("../../etc/passwd") == "_.._etc_passwd")
        #expect(MobileDownloads.safeName(".hidden") == "hidden")
        #expect(MobileDownloads.safeName("  ") == "Download")
    }

    @Test func theListKeepsNewestFirstAndSaysWhereAFileCameFrom() throws {
        var downloads = MobileDownloads()
        let old = MobileDownloads.Item(name: "a.pdf", source: "https://www.example.com/a.pdf", date: Date(timeIntervalSince1970: 1), bytes: 2_048)
        let new = MobileDownloads.Item(name: "b.pkpass", source: "https://tickets.example/b", date: Date(timeIntervalSince1970: 2), bytes: 10)
        downloads.add(old)
        downloads.add(new)
        #expect(downloads.items.map(\.name) == ["b.pkpass", "a.pdf"])
        #expect(MobileDownloads.detail(for: old).hasPrefix("example.com · "))
        #expect(MobileDownloads.opening(forName: "b.pkpass") == .walletPass)
        #expect(MobileDownloads.opening(forName: "a.PDF") == .preview)
        downloads.remove([new.id])
        let saved = try JSONEncoder().encode(downloads)
        #expect(try JSONDecoder().decode(MobileDownloads.self, from: saved) == downloads)
    }

    /// GitHub #569: Continue Anyway allows the host the warning named, and only that host, for
    /// the rest of the run. (The load failing again after Continue Anyway was App Transport
    /// Security, which a web view's trust answer can't override; CertificateTests pins that in the app.)
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/569"))
    func aCertificateExceptionIsForOneHost() {
        var exceptions = MobileCertificateExceptions()
        #expect(!exceptions.allows("self-signed.example"))
        exceptions.allow("Self-Signed.Example")
        #expect(exceptions.allows("self-signed.example"))
        #expect(exceptions.allows("SELF-SIGNED.EXAMPLE"))
        #expect(!exceptions.allows("other.example"))
        #expect(!exceptions.allows("www.self-signed.example"), "a subdomain is another host")
        exceptions.allow("self-signed.example")
        #expect(exceptions.hosts == ["self-signed.example"])
    }
}

struct MobileFidgetTests {
    @Test func theSpinSlowsDownAndStops() {
        var angle = 0.0, speed = MobileFidget.launchSpeed(angularVelocity: 200)
        #expect(speed == 60)
        var seconds = 0.0
        while MobileFidget.isSpinning(speed: speed) {
            (angle, speed) = MobileFidget.step(angle: angle, speed: speed, elapsed: 1.0 / 60)
            seconds += 1.0 / 60
        }
        #expect(seconds > 4 && seconds < 7)
        #expect(angle > 60)
    }

    @Test func itSettlesUprightOnTheTurnItWasHeadingFor() {
        #expect(abs(MobileFidget.restAngle(from: 7, speed: 1) - 4 * Double.pi) < 1e-9)
        #expect(abs(MobileFidget.restAngle(from: 7, speed: -1) - 2 * Double.pi) < 1e-9)
        #expect(MobileFidget.restAngle(from: -1, speed: -1) == -2 * Double.pi)
        #expect(MobileFidget.quarterTurns(from: 0, to: 3.3) == 2)
    }
}

struct MobilePageBehindSearchTests {
    /// Arc Search pushes the page back as a card under the status bar while the sheet is up:
    /// 10 pt in from each side on a 393 pt screen.
    @Test func thePageSitsBehindTheSearchSheetAsACard() {
        let placed = MobilePageBehindSearch.transform(in: CGSize(width: 393, height: 852), safeTop: 59)
        #expect(abs(placed.scale - 373.0 / 393) < 1e-9)
        // The scaled page's top edge: half the lost height, plus the shift.
        let top = 852 * (1 - placed.scale) / 2 + placed.shiftDown
        #expect(abs(top - 59) < 1e-9)
        // White under the dim comes out #cccccc, the screenshot's colour.
        #expect(Int(((1 - MobilePageBehindSearch.dim) * 255).rounded()) == 0xcc)
    }

    /// The page follows the search drawer: closed it is the page itself, open the card, and
    /// halfway its top is halfway to the status bar.
    @Test func thePageFollowsTheDrawerAsItOpens() {
        let size = CGSize(width: 393, height: 852)
        let closed = MobilePageBehindSearch.transform(in: size, safeTop: 59, progress: 0)
        #expect(closed.scale == 1 && closed.shiftDown == 0)
        let half = MobilePageBehindSearch.transform(in: size, safeTop: 59, progress: 0.5)
        let top = size.height * (1 - half.scale) / 2 + half.shiftDown
        #expect(abs(top - 29.5) < 1e-9, "the page's top follows the drawer halfway")
        let open = MobilePageBehindSearch.transform(in: size, safeTop: 59, progress: 1)
        let card = MobilePageBehindSearch.transform(in: size, safeTop: 59)
        #expect(abs(open.scale - card.scale) < 1e-9 && abs(open.shiftDown - card.shiftDown) < 1e-9)
        #expect(MobilePageBehindSearch.transform(in: size, safeTop: 59, progress: 2).scale == card.scale)
    }
}

/// What the screen does once something is chosen in the search sheet.
struct MobileSheetLeaveTests {
    /// The sheet rises and fades out over a quarter of a second, as Arc Search's, instead of sinking into the pill.
    @Test func theSheetRisesAndFadesForAChoice() {
        #expect(MobileSheetLeave.leaveRise == 160)
        #expect(MobileSheetLeave.leaveDuration == 0.25)
    }

    /// A new tab from the sheet stays under the canvas colour until it has drawn, and not past the longest hold.
    @Test func aNewPageIsCoveredUntilItHasDrawn() {
        #expect(!MobileSheetLeave.liftsCover(elapsed: 0.1, sinceDrawn: 0.1))
        #expect(MobileSheetLeave.liftsCover(elapsed: 0.25, sinceDrawn: 0.1))
        #expect(!MobileSheetLeave.liftsCover(elapsed: 1.0, sinceDrawn: nil))
        #expect(MobileSheetLeave.liftsCover(elapsed: 1.5, sinceDrawn: nil))
        // Drawn, it waits for that paint to reach the screen: lifted at once, two white frames showed first.
        #expect(!MobileSheetLeave.liftsCover(elapsed: 0.6, sinceDrawn: 0))
        #expect(!MobileSheetLeave.liftsCover(elapsed: 0.6, sinceDrawn: 0.05))
        #expect(MobileSheetLeave.liftsCover(elapsed: 0.6, sinceDrawn: 0.1))
    }
}

/// The switch between Browse for Me and the search engine on their pages.
struct MobileBrowseToggleTests {
    /// TapSmart's screenshot of Arc Search (402 × 874 pt, bar top at 798.3 pt): the capsule spans
    /// 278–386 pt across and 738–781 pt down.
    @Test func theSwitchSitsWhereArcSearchPutsIt() {
        let frame = MobileBrowseToggle.frame(screenWidth: 402, barTop: 798)
        #expect(frame == CGRect(x: 278, y: 738, width: 108, height: 43))
        #expect(MobileBrowseToggle.segmentFrame(for: .browseForMe) == CGRect(x: 6, y: 6, width: 42, height: 31))
        #expect(MobileBrowseToggle.segmentFrame(for: .engine) == CGRect(x: 60, y: 6, width: 42, height: 31))
    }

    /// A Browse for Me tab shows its side; the engine's results show the other; other pages none.
    @Test func eachPageKnowsItsSideAndQuery() {
        let browse = MobileBrowseToggle.state(tabAddress: MobileBrowseForMe.tabAddress(query: "best places paris"), pageURL: "about:blank", engine: .google)
        #expect(browse?.side == .browseForMe && browse?.query == "best places paris")
        let results = MobileBrowseToggle.state(tabAddress: "https://www.google.com/search?q=best+places%20paris&hl=en",
                                               pageURL: "https://www.google.com/search?q=best+places%20paris&hl=en", engine: .google)
        #expect(results?.side == .engine && results?.query == "best places paris")
        #expect(MobileBrowseToggle.state(tabAddress: "https://example.com/search?q=x", pageURL: "https://example.com/search?q=x", engine: .google) == nil)
        // Another engine's results are not the chosen engine's.
        #expect(MobileBrowseToggle.state(tabAddress: "", pageURL: "https://www.bing.com/search?q=x", engine: .google) == nil)
    }

    @Test(arguments: ["C++ tutorial", "a+b c&d=e", "100% + # ? /", "café + 東京 🧪"])
    func literalPlusSearchQueriesRoundTrip(_ query: String) {
        for engine in MobileSearchEngine.allCases {
            let address = engine.searchURL(query)
            #expect(address.contains("%2B"), "literal plus must be percent encoded for \(engine)")
            #expect(engine.query(fromResultsURL: address) == query, "\(engine)")
        }
    }

    /// Every engine's own results address reads back the query it was made from.
    @Test func everyEnginesResultsReadBack() {
        for engine in MobileSearchEngine.allCases {
            #expect(engine.query(fromResultsURL: engine.searchURL("risotto vs paella & more")) == "risotto vs paella & more", "\(engine)")
        }
        #expect(MobileSearchEngine.duckduckgo.query(fromResultsURL: "https://duckduckgo.com/?t=h_&q=cats&ia=web") == "cats")
        #expect(MobileSearchEngine.google.query(fromResultsURL: "https://www.google.com/search?q=") == nil)
    }
}

struct MobileSelectionQueryTests {
    /// Selected text becomes one line, cut at a word within 200 characters.
    @Test func selectedTextBecomesAQuestion() {
        #expect(MobileBrowseForMe.query(fromSelection: "  wood-fired\n\tpizza   ovens ") == "wood-fired pizza ovens")
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let query = MobileBrowseForMe.query(fromSelection: long)
        #expect(query.count <= 200 && query.hasSuffix("word") && !query.hasSuffix(" "))
        #expect(MobileBrowseForMe.query(fromSelection: String(repeating: "x", count: 300)).count == 200)
        #expect(MobileBrowseForMe.query(fromSelection: " \n ").isEmpty)
    }
}

/// Links from other apps' share sheets, waiting in the App Group for the app.
struct MobileShareInboxTests {
    /// #829: "Tabs" and "Favorites" read like the Mac's synced Spaces, so a link seemed to go to the Mac and didn't. The
    /// share sheet's places say they are the iPhone's own, until the phone can save into a Mac Space (Arc Search's places).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/829")) func thePlacesSayTheyAreOnTheIPhone() {
        #expect(MobileShareInbox.Destination.tabs.label == "iPhone Tabs")
        #expect(MobileShareInbox.Destination.favorites.label == "iPhone Favorites")
    }

    /// A saved link joins the row behind what is on screen.
    @Test func aSavedLinkJoinsTheRowWithoutTakingTheScreen() {
        let now = Date(timeIntervalSince1970: 0)
        let shown = MobileTab(url: "https://a.example", lastActive: now)
        var document = MobileTabsDocument(tabs: [shown], selected: shown.id)
        document.add(MobileTab(url: "https://b.example", title: "B", lastActive: now))
        #expect(document.selected == shown.id && document.tabs.map(\.url) == ["https://a.example", "https://b.example"])
    }

    @Test func savedLinksWaitOnceEachAndRememberThePlace() {
        var inbox = MobileShareInbox()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept1 = inbox.save(url: "https://tidbits.com/a", title: " TidBITS ", to: .favorites, at: now)
        #expect(kept1)
        let kept2 = inbox.save(url: "https://tidbits.com/a", title: "TidBITS again", to: .favorites, at: now)
        #expect(kept2)
        let kept3 = inbox.save(url: "https://tidbits.com/a", title: "", to: .tabs, at: now)
        #expect(kept3)
        let kept4 = inbox.save(url: "file:///etc/hosts", title: "x", to: .tabs, at: now)
        #expect(!kept4)
        let kept5 = inbox.save(url: "javascript:alert(1)", title: "x", to: .tabs, at: now)
        #expect(!kept5)
        #expect(inbox.items.map(\.title) == ["TidBITS again", "tidbits.com"])
        #expect(inbox.lastDestination == .tabs)
        let taken = inbox.take()
        #expect(taken.count == 2)
        #expect(inbox.items.isEmpty && inbox.lastDestination == .tabs)
        for index in 0..<(MobileShareInbox.limit + 5) { inbox.save(url: "https://e.example/\(index)", title: "", to: .tabs, at: now) }
        #expect(inbox.items.count == MobileShareInbox.limit && inbox.items.first?.url == "https://e.example/5")
    }

    /// The extension writes, the app takes: one file in the shared folder, read back whole.
    @Test func theFileCarriesLinksFromTheExtensionToTheApp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in
            inbox.save(url: "https://crabrowser.app", title: "Cra", to: .favorites, at: Date(timeIntervalSince1970: 0))
        }
        #expect(saved == true)
        let place = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.lastDestination }
        #expect(place == .favorites)
        let taken = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.take() } ?? []
        #expect(taken.map(\.url) == ["https://crabrowser.app"] && taken.first?.destination == .favorites)
        let left = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.items.count }
        #expect(left == 0)
        // A file from a newer or broken build is an empty inbox, not a crash.
        try Data("{\"items\":[{\"url\":1}],\"lastDestination\":\"space\"}".utf8).write(to: folder.appendingPathComponent(MobileShareInbox.fileName))
        let broken = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox }
        #expect(broken == MobileShareInbox())
    }
}

/// Translate's batching and the scripts it runs on the page.
struct MobileTranslateTests {
    @Test func textsGoInBatchesUnderTheLimit() {
        #expect(MobileTranslate.batches(["aaaa", "bbbb", "cc", "dddddddddd", "e"], maxCharacters: 8) == [[0, 1], [2], [3], [4]])
        #expect(MobileTranslate.batches([], maxCharacters: 8).isEmpty)
        #expect(MobileTranslate.languageSample(["short", "the longest text", "middle one"], limit: 22) == "the longest text middl")
    }

    /// The written-back texts go in as JSON, so quotes and script-looking text stay text.
    @Test func translationsAreEmbeddedAsData() {
        let script = MobileTranslate.applyScript(["Hej \"verden\"", "</script><b>x</b>"])
        #expect(script.contains(#"["Hej \"verden\"","<\/script><b>x<\/b>"]"#))
        #expect(MobileTranslate.collectScript.contains("\\p{L}") && MobileTranslate.collectScript.contains("3000"))
    }
}

/// "Open App Links in...": which navigations are offered to an installed app first.
struct MobileAppLinksTests {
    @Test func onlyATappedLinkToAnotherSiteGoesToTheApp() {
        let app = MobileAppLinks.nativeApp
        #expect(app.offersApp(isLinkTap: true, isMainFrame: true, from: "https://news.ycombinator.com/", to: "https://www.youtube.com/watch?v=x"))
        #expect(!app.offersApp(isLinkTap: false, isMainFrame: true, from: "https://news.ycombinator.com/", to: "https://www.youtube.com/watch?v=x"), "typed or redirected")
        #expect(!app.offersApp(isLinkTap: true, isMainFrame: false, from: "https://a.example/", to: "https://www.youtube.com/"), "inside a frame")
        #expect(!app.offersApp(isLinkTap: true, isMainFrame: true, from: "https://www.youtube.com/", to: "https://m.youtube.com/watch"), "same site")
        #expect(!app.offersApp(isLinkTap: true, isMainFrame: true, from: "https://a.example/", to: "mailto:x@example.com"))
        #expect(app.offersApp(isLinkTap: true, isMainFrame: true, from: nil, to: "https://www.youtube.com/"))
        #expect(!MobileAppLinks.browser.offersApp(isLinkTap: true, isMainFrame: true, from: "https://a.example/", to: "https://www.youtube.com/"))
    }
}

/// App Settings ▸ Languages: what the answers are written in.
struct MobileLanguagesTests {
    @Test func answersFollowTheSettingThenThePhone() throws {
        #expect(MobileLanguages.answerCode(setting: nil, preferred: ["da-DK", "en-US"]) == "da")
        #expect(MobileLanguages.answerCode(setting: nil, preferred: ["fo-FO", "nn-NO"]) == "nb", "the first language the model writes")
        #expect(MobileLanguages.answerCode(setting: nil, preferred: ["fo-FO"]) == "en")
        #expect(MobileLanguages.answerCode(setting: "ja", preferred: ["da-DK"]) == "ja")
        #expect(MobileLanguages.englishName("da") == "Danish")
        let old = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"answerLanguage":"xx"}"#.utf8))
        #expect(old.answerLanguage == nil, "an unknown language follows the phone")
        let kept = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"answerLanguage":"fr"}"#.utf8))
        #expect(kept.answerLanguage == "fr")
    }
}

/// Custom search engines: an https address with `%s` for the query.
struct MobileCustomSearchTests {
    @Test func aCustomEngineSearchesItsAddressAndReadsItsQueryBack() {
        #expect(MobileSearch.isValidTemplate("https://search.brave.com/search?q=%s"))
        #expect(!MobileSearch.isValidTemplate("http://example.com/?q=%s"), "https only")
        #expect(!MobileSearch.isValidTemplate("https://example.com/?q="), "needs %s")
        #expect(!MobileSearch.isValidTemplate("https://example.com/%s?q=%s"), "one %s")
        let brave = MobileSearch(.google, customTemplate: "https://search.brave.com/search?q=%s&source=web")
        #expect(brave.label == "search.brave.com")
        #expect(brave.searchURL("risotto & paella") == "https://search.brave.com/search?q=risotto%20%26%20paella&source=web")
        #expect(brave.query(fromResultsURL: brave.searchURL("risotto & paella")) == "risotto & paella")
        #expect(brave.query(fromResultsURL: "https://www.google.com/search?q=x") == nil)
        #expect(brave.suggestURL("x") == nil)
        let endless = MobileSearch(.google, customTemplate: "https://www.startpage.com/do/search?q=%s")
        #expect(endless.label == "startpage.com")
        #expect(endless.query(fromResultsURL: "https://www.startpage.com/do/search?q=cats&page=2") == "cats")
        #expect(MobileSearch(.bing, customTemplate: "not an address %s") == .bing, "a bad address falls back")
    }

    @Test func settingsChooseTheCustomEngine() throws {
        var settings = MobileSettings()
        settings.customSearchURL = "https://search.brave.com/search?q=%s"
        settings.searchChoice = .custom
        #expect(settings.searchChoice == .custom && settings.search.label == "search.brave.com")
        let saved = try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.searchChoice == .custom)
        settings.searchChoice = .engine(.kagi)
        #expect(settings.search == .kagi && settings.customSearchURL != nil, "the address is kept for later")
    }
}

/// The summary as text, for Copy and Share.
struct MobileSummaryTextTests {
    @Test func theSummaryReadsAsTextWithItsSource() {
        let answer = MobileSummary.Answer(overview: "A guide to the stars.", sections: [.init(title: "Seeing", body: "Go somewhere dark.")])
        #expect(answer.plainText(title: " Night sky ", address: "https://example.com/stars?utm_source=x") ==
            "Night sky\n\nA guide to the stars.\n\nSeeing\nGo somewhere dark.\n\nSummarized for you by Cra\nhttps://example.com/stars")
        #expect(answer.plainText(title: "", address: nil).hasPrefix("A guide to the stars."))
    }
}

/// Browse for Me's follow-ups and Sources (Arc Search 1.24).
struct MobileBrowseFollowUpTests {
    @Test func followUpsAreChipsThatAskAgainAndSourcesAreListed() {
        let answer = MobileBrowseForMe.Answer(title: "Ovens", points: [.init(emoji: "🔥", term: "Heat", text: "Hot.")], sections: [],
                                              followUps: [" best ovens ", "Best ovens", "", "pizza ovens", "a", "b"]).cleaned
        #expect(answer?.followUps == ["best ovens", "pizza ovens", "a"])
        let hit = MobileBrowseForMe.Hit(title: "Oven guide", url: "https://ovens.example/guide", snippet: "")
        let html = MobileBrowseForMe.pageHTML(query: "pizza ovens", answer: answer!, sources: [.init(hit: hit, title: "Oven guide", text: "")],
                                              searchURL: "https://www.google.com/search?q=pizza%20ovens")
        #expect(html.contains("href=\"\(MobileBrowseForMe.tabAddress(query: "best ovens"))\""))
        #expect(!html.contains(">pizza ovens</a>"), "the question itself is not offered again")
        #expect(html.contains("<h2>Sources</h2>") && html.contains("https://ovens.example/guide"))
    }
}

/// The Spaces sheet's colour and text.
struct MobileSpacesSheetTests {
    @Test func darkSpacesGetWhiteTextAndLightOnesDark() {
        let phantom = MobileSpaces.sheetStyle(colors: ["#181818", "#262626"])
        #expect(phantom == .init(fill: "#696969", lightText: true))
        #expect(MobileSpaces.sheetStyle(colors: ["#8A57B5"])?.lightText == true, "a purple like Arc Search's")
        #expect(MobileSpaces.sheetStyle(colors: ["#C7CAFF", "#FFE5E5"])?.lightText == false)
        #expect(MobileSpaces.sheetStyle(colors: []) == nil)
    }

    /// In dark mode Arc Search draws a Space's sheet in shades of its colour at fixed perceived
    /// lightness (OKLCH), the hue the Space's own.
    @Test func darkModeShadesTheSpacesColour() throws {
        let cream = try #require(MobileSpaces.darkSheetStyle(colors: ["#F4F1EA", "#E6DCC8"]))
        // Arc's, measured in Victor's IMG_1900–1902: #3A341B to #433013, bar #5F4307, name #F8E8A0,
        // rows #FDF7DF, close disc #756843; folder front #6F5600, back #E9B300, edge #FCEDBC.
        #expect([cream.top, cream.bottom, cream.bar, cream.title, cream.text, cream.closeDisc] ==
                ["#39331C", "#422F14", "#5F4307", "#F8E8A0", "#FAF5E4", "#726747"])
        #expect([cream.folderFront, cream.folderBack, cream.folderEdge] == ["#705700", "#E9B303", "#FDEEBD"])
        // A muted purple Space gets the same perceived lightness as Arc's blue one (IMG_1904: top
        // #313044, close disc #64637D, folder front #1F2AFF, rows #F2F3FF) in its own hue.
        let purple = try #require(MobileSpaces.darkSheetStyle(colors: ["#6F5F7F", "#646172"]))
        #expect(purple.top == "#3C2D40")
        #expect(purple.closeDisc == "#71607B")
        #expect(purple.folderFront == "#8500B7")
        #expect(purple.text == "#FCF1FF")
        // A grey Space has no hue to keep: neutral shades, not a made-up colour.
        let grey = try #require(MobileSpaces.darkSheetStyle(colors: ["#808080"]))
        #expect(grey.top == "#333333")
        #expect(MobileSpaces.darkSheetStyle(colors: []) == nil)
    }
}

/// Site icons for rows the phone never visited: the icons a site's home page names, best first.
struct MobileFaviconLinkTests {
    /// A dark, colourless icon with see-through parts (GitHub's mark) would vanish on a dark
    /// sheet; Arc Search draws it in the text's colour. Coloured or filled-in icons stay as they are.
    @Test func darkMarksAreDrawnInTheTextsColourOnDark() {
        #expect(MobileFavicons.drawsAsMark(coverage: 0.55, luminance: 0.08, chroma: 0.02, lightShare: 0))
        // GitHub's octocat is #1F2328: a ratio-based saturation calls that 22 % saturated.
        #expect(MobileFavicons.drawsAsMark(coverage: 0.62, luminance: 0.13, chroma: 0.035, lightShare: 0), "a dark slate mark")
        #expect(!MobileFavicons.drawsAsMark(coverage: 0.55, luminance: 0.4, chroma: 0.5, lightShare: 0.1), "a coloured icon")
        #expect(!MobileFavicons.drawsAsMark(coverage: 1, luminance: 0.08, chroma: 0.02, lightShare: 0), "a filled square keeps its shape")
        #expect(!MobileFavicons.drawsAsMark(coverage: 0.55, luminance: 0.7, chroma: 0.02, lightShare: 0.9), "a light mark shows already")
        #expect(!MobileFavicons.drawsAsMark(coverage: 0.78, luminance: 0.15, chroma: 0, lightShare: 0.14), "Vercel: a white triangle on a black disc")
    }

    @Test func theHomePagesIconsComeBestFirst() {
        let html = """
        <html><head>
        <link rel="icon" href="/favicon-16.png" sizes="16x16">
        <LINK REL="shortcut icon" href='/favicon.ico'>
        <link rel="apple-touch-icon" href="https://cdn.example/touch.png">
        <link rel="icon" type="image/svg+xml" href="/icon.svg">
        <link rel="icon" href="/favicon-32.png" sizes="32x32">
        <link rel="stylesheet" href="/site.css">
        </head><body><link rel="icon" href="/late.png"></body></html>
        """
        let links = MobileFavicons.iconLinks(inHTML: html, page: URL(string: "https://app.example/dashboard")!)
        // Sized icons largest first (an unsized one, often an .ico holding several, between 32
        // and 16), then the touch icon, which is drawn as an app icon; SVG and the body are skipped.
        #expect(links == ["https://app.example/favicon-32.png", "https://app.example/favicon.ico", "https://app.example/favicon-16.png",
                          "https://cdn.example/touch.png"])
        #expect(MobileFavicons.iconLinks(inHTML: "<p>none</p>", page: URL(string: "https://x.example/")!) == ["https://x.example/favicon.ico"])
    }

    /// The tab switcher showed every site's icon as a square: an open page's touch icon, listed
    /// first and largest by most sites, came first. It is an app icon, an opaque square; the
    /// site's own favicon, round or see-through, comes before it, and so does an unnamed
    /// `/favicon.ico`. The touch icon is used only when the site has nothing else.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/793")) func anOpenPagesOwnFaviconComesBeforeItsTouchIcon() {
        let page = URL(string: "https://news.example/story")!
        let touch = MobileFavicons.IconLink(rel: "apple-touch-icon", href: "https://news.example/touch-180.png", sizes: "180x180")
        let links = [
            touch,
            MobileFavicons.IconLink(rel: "icon", href: "https://news.example/round-32.png", sizes: "32x32", type: "image/png"),
            MobileFavicons.IconLink(rel: "stylesheet", href: "https://news.example/site.css"),
            MobileFavicons.IconLink(rel: "icon", href: "https://news.example/mark.svg", sizes: "any", type: "image/svg+xml"),
        ]
        #expect(MobileFavicons.bestFirst(links, page: page)
            == ["https://news.example/round-32.png", "https://news.example/favicon.ico", "https://news.example/touch-180.png"])
        #expect(MobileFavicons.bestFirst([touch], page: page) == ["https://news.example/favicon.ico", "https://news.example/touch-180.png"])
        // A page's HTML ranks the same way.
        let html = #"<head><link rel="apple-touch-icon" href="/t.png" sizes="180x180"><link rel="icon" href="/i.png" sizes="16x16"></head>"#
        #expect(MobileFavicons.iconLinks(inHTML: html, page: page)
            == ["https://news.example/i.png", "https://news.example/favicon.ico", "https://news.example/t.png"])
    }
}

/// The query capsule on a Browse for Me page edits the question.
struct MobileBrowseQueryEditTests {
    @Test func theCapsuleOpensTheQuestionForEditing() {
        let address = MobileBrowseForMe.editAddress(query: "risotto & paella?")
        #expect(MobileBrowseForMe.query(fromEditAddress: address) == "risotto & paella?")
        #expect(MobileBrowseForMe.query(fromEditAddress: "https://example.com") == nil)
        let answer = MobileBrowseForMe.Answer(title: "T", points: [.init(emoji: "", term: "", text: "x")], sections: [])
        let html = MobileBrowseForMe.pageHTML(query: "risotto & paella?", answer: answer, sources: [], searchURL: "https://www.google.com/search?q=x")
        #expect(html.contains("class=\"query\" href=\"\(address)\""))
    }
}

/// Starter questions for someone new (Arc Search 1.13).
struct MobileStarterRowsTests {
    @Test func someoneNewSeesSampleQuestionsUntilTheirFirstSearch() {
        let rows = MobileSuggestions.starterRows(favorites: 0, hasSearched: false, incognito: false)
        #expect(rows.map(\.text) == ["how do i make my boss like me", "lebron vs lebron jr", "tips for seasonal depression", "will tiktok be banned"])
        #expect(MobileSuggestions.starterRows(favorites: 1, hasSearched: false, incognito: false).isEmpty)
        #expect(MobileSuggestions.starterRows(favorites: 0, hasSearched: true, incognito: false).isEmpty)
        #expect(MobileSuggestions.starterRows(favorites: 0, hasSearched: false, incognito: true).isEmpty)
    }
}

/// Browse for Me pages follow the phone's text size.
struct MobileBrowseDynamicTypeTests {
    @Test func thePageIsSizedAgainstTheSystemBodyStyle() {
        let answer = MobileBrowseForMe.Answer(title: "T", points: [.init(emoji: "", term: "", text: "x")], sections: [])
        let html = MobileBrowseForMe.pageHTML(query: "q", answer: answer, sources: [], searchURL: "https://www.google.com/search?q=q")
        #expect(html.contains("font: -apple-system-body"))
        let style = html[html.range(of: "<style>")!.upperBound..<html.range(of: "</style>")!.lowerBound]
        #expect(style.range(of: #"font-size: \d+px"#, options: .regularExpression) == nil, "no fixed text sizes")
    }
}

struct MobileBlockerNoticesTests {
    @Test func theTipShowsOnceOnAPageThatBlockedSomethingOutsideIncognito() {
        #expect(MobileBlockerNotices.showsTip(blocked: 14, alreadyShown: false, isIncognito: false))
        #expect(!MobileBlockerNotices.showsTip(blocked: 0, alreadyShown: false, isIncognito: false))
        #expect(!MobileBlockerNotices.showsTip(blocked: 14, alreadyShown: true, isIncognito: false))
        #expect(!MobileBlockerNotices.showsTip(blocked: 14, alreadyShown: false, isIncognito: true))
    }

    @Test func theTipCountsLikeArcSearch() {
        #expect(MobileBlockerNotices.tipTitle(14) == ("Cra just blocked 14 trackers", "14"))
        #expect(MobileBlockerNotices.tipTitle(1) == ("Cra just blocked 1 tracker", "1"))
    }

    @Test func theTipIsRememberedInSettingsAndOlderFilesHaveNotSeenIt() throws {
        let old = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"hasSearched":true}"#.utf8))
        #expect(!old.hasSeenBlockTip)
        var settings = MobileSettings()
        settings.hasSeenBlockTip = true
        let back = try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.hasSeenBlockTip)
    }

    @Test func aThumbsUpTurnsTheSitesBlockersOffAndLeavesOtherSitesAlone() {
        var settings = MobileSettings()
        settings.disableBlockers(for: "www.google.com")
        let google = settings.options(for: "google.com")
        #expect(!google.blockAds && !google.blockTrackers && !google.blockCookieBanners)
        #expect(google.pinchToSummarize)
        #expect(settings.options(for: "example.com") == MobileSiteOptions())
        #expect(MobileBlockerNotices.disabledLabel(site: "google.com") == "Blockers disabled for google.com")
    }
}

struct MobileCoachMarkTests {
    @Test func itShowsWithTheStarterQuestionsWhenBrowseForMeCanBePicked() {
        #expect(MobileCoachMark.shows(startersShown: true, offersBrowseForMe: true))
        #expect(!MobileCoachMark.shows(startersShown: false, offersBrowseForMe: true))
        #expect(!MobileCoachMark.shows(startersShown: true, offersBrowseForMe: false))
    }

    @Test func theLineDropsRunsAcrossAndStopsAboveTheChip() {
        let line = MobileCoachMark.path(from: CGPoint(x: 220, y: 273), toChipTop: CGPoint(x: 369, y: 418))
        #expect(line.firstTurn == CGPoint(x: 220, y: 320))
        #expect(line.secondTurn == CGPoint(x: 369, y: 320))
        #expect(line.end == CGPoint(x: 369, y: 412))
    }
}

struct MobileSyncIntroTests {
    @Test func theCardShowsUntilClosedOrSynced() {
        #expect(MobileSyncIntro.showsCard(hasSpaces: false, dismissed: false))
        #expect(!MobileSyncIntro.showsCard(hasSpaces: true, dismissed: false))
        #expect(!MobileSyncIntro.showsCard(hasSpaces: false, dismissed: true))
    }

    /// Arc Search asks to set up the share extension once, after the desktop's Spaces arrive.
    @Test func theSharePromptAsksOnceTheSpacesAreHere() throws {
        #expect(MobileSyncIntro.showsSharePrompt(hasSpaces: true, seen: false))
        #expect(!MobileSyncIntro.showsSharePrompt(hasSpaces: false, seen: false))
        #expect(!MobileSyncIntro.showsSharePrompt(hasSpaces: true, seen: true))
        let old = try JSONDecoder().decode(MobileSettings.self, from: Data("{}".utf8))
        #expect(!old.hasSeenSharePrompt)
        var settings = MobileSettings()
        settings.hasSeenSharePrompt = true
        let back = try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.hasSeenSharePrompt)
        #expect(MobileSyncIntro.guideSteps.filter { $0.text.contains("{icon}") }.allSatisfy { $0.symbol != nil })
    }

    @Test func theWayToSyncMentionsICloudOnlyWhenItIsOff() {
        #expect(!MobileSyncIntro.haveMacBody(iCloud: true).contains("Sign in to iCloud"))
        #expect(MobileSyncIntro.haveMacBody(iCloud: false).hasSuffix("Sign in to iCloud on this iPhone too."))
    }

    /// The steps lead where the Mac's switch is: Settings' first tab, the one named after the user,
    /// and the switch by the name the Mac gives it. General has had no Sync since the redesign (#377).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/897"))
    func theWayToSyncNamesTheMacsSwitchWhereItIs() {
        #expect(SettingsTab.first == .sync)
        for iCloud in [true, false] {
            let body = MobileSyncIntro.haveMacBody(iCloud: iCloud)
            #expect(body.contains("first tab"))
            #expect(body.contains(SettingsTab.syncSwitch))
            #expect(!body.contains(SettingsTab.general.title))
        }
    }

    @Test func closingTheCardIsKeptAndOlderFilesHaveNotClosedIt() throws {
        let old = try JSONDecoder().decode(MobileSettings.self, from: Data("{}".utf8))
        #expect(!old.hasDismissedSyncCard)
        var settings = MobileSettings()
        settings.hasDismissedSyncCard = true
        #expect(try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(settings)).hasDismissedSyncCard)
    }
}

struct MobileAITests {
    @Test func everyPhoneThatCanRunAppleIntelligenceGetsTheButtons() {
        #expect(MobileAIState.ready.offersFeatures)
        #expect(MobileAIState.turnedOff.offersFeatures)
        #expect(MobileAIState.preparing.offersFeatures)
        #expect(!MobileAIState.unsupported.offersFeatures)
        #expect(MobileAIState.ready.canRun && !MobileAIState.turnedOff.canRun && !MobileAIState.preparing.canRun)
    }

    @Test func aTapAsksToSwitchItOnOrToWait() {
        #expect(MobileAI.prompt(for: .ready) == nil)
        #expect(MobileAI.prompt(for: .unsupported) == nil)
        let off = MobileAI.prompt(for: .turnedOff)
        #expect(off?.title == "Turn on Apple Intelligence")
        #expect(off?.opensSettings == true)
        #expect(off?.message.contains("Settings \u{25B8} Apple Intelligence & Siri") == true)
        #expect(MobileAI.prompt(for: .preparing)?.opensSettings == false)
    }
}

/// Arc Search's recent tabs under the empty field (#591): the phone's and the Mac's, newest first.
struct MobileRecentTabsTests {
    static func mac(_ url: String, _ title: String, _ date: Double?) -> SidebarItem {
        var item = SidebarItem.tab(url, title: title, parent: nil)
        if case .tab(var tab) = item.data {
            tab.timeLastActiveAt = date.map(Date.init(timeIntervalSince1970:))
            item.data = .tab(tab)
        }
        return item
    }

    /// A one-Space sidebar with `today` in its Today list.
    static func sidebar(today: [SidebarItem]) -> SidebarDocument {
        var document = SidebarDocument.fresh()
        let container = document.spaces[0].todayContainerID
        document.items += today
        if let index = document.items.firstIndex(where: { $0.id == container }) { document.items[index].children = today.map(\.id) }
        return document
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/591")) func mergesAndFiltersRecentTabs() {
        let selected = MobileTab(url: "https://selected.example", title: "Selected", lastActive: Date(timeIntervalSince1970: 5))
        let phone = MobileTab(url: "https://phone.example", title: "Phone", lastActive: Date(timeIntervalSince1970: 4))
        let privateTab = MobileTab(url: "https://private.example", lastActive: Date(timeIntervalSince1970: 9), isIncognito: true)
        let mac = Self.mac
        var renamed = mac("https://rename.example", "Saved", 8)
        renamed.title = "Renamed"
        let document = Self.sidebar(today: [renamed, mac("https://saved.example", "Saved", 7), mac("https://host.example/path", "", 6),
                                            mac("https://host.example/path", "Old", 1), mac(selected.url, "Selected duplicate", 20),
                                            mac(phone.url, "Phone duplicate", 19), mac("https://undated.example", "Undated", nil),
                                            mac("", "Empty", 21)])
        let rows = MobileRecentTabs.rows(phone: [selected, phone, privateTab], selected: selected.id, mac: document, limit: 10)
        #expect(rows.map(\.title) == ["Renamed", "Saved", "host.example", "Phone"])
        #expect(rows.last?.source == .phone(phone.id))
        #expect(rows.first?.source == .mac)
        #expect(MobileRecentTabs.rows(phone: [selected, phone], selected: selected.id, mac: document, limit: 2).count == 2)
        #expect(MobileRecentTabs.rows(phone: [selected, phone], selected: selected.id, mac: nil).map(\.title) == ["Phone"])
    }

    /// The same page in another form (scheme, "www.", trailing slash, fragment) is one row, the
    /// phone's when the phone has it. An incognito tab is no tab here, so it hides nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/591")) func aPageListedTwiceShowsOnce() {
        let phone = MobileTab(url: "https://www.news.example/story/", title: "Story", lastActive: Date(timeIntervalSince1970: 1))
        let privateTab = MobileTab(url: "https://secret.example/", lastActive: Date(timeIntervalSince1970: 2), isIncognito: true)
        let document = Self.sidebar(today: [Self.mac("http://news.example/story#comments", "Story on the Mac", 9),
                                            Self.mac("https://docs.example/a", "Doc", 8), Self.mac("https://www.docs.example/a/", "Doc again", 7),
                                            Self.mac("https://secret.example", "Secret on the Mac", 6),
                                            Self.mac("https://docs.example/a?page=2", "Doc page 2", 5)])
        let rows = MobileRecentTabs.rows(phone: [phone, privateTab], selected: nil, mac: document, limit: 10)
        #expect(rows.map(\.title) == ["Doc", "Secret on the Mac", "Doc page 2", "Story"])
        #expect(rows.last?.source == .phone(phone.id))
    }

    /// Arc Sync brought the Mac's Spaces over (pinned tabs, folders, Today) but never its
    /// favorites (ATH3): a Mac favorite isn't a recent tab, and neither is a blank window's tab.
    /// Tabs inside folders and splits are.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/591")) func macTabsComeFromItsSyncedSpaces() {
        var document = Self.sidebar(today: [Self.mac("https://today.example", "Today", 1)])
        var space = document.spaces[0]
        var folder = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let inFolder = Self.mac("https://folder.example", "In a folder", 4)
        var split = SidebarItem.split(parent: space.pinnedContainerID)
        let inSplit = Self.mac("https://split.example", "In a split", 3)
        folder.children = [inFolder.id]
        split.children = [inSplit.id]
        let favorite = Self.mac("https://favorite.example", "Favorite", 9)
        document.items += [folder, inFolder, split, inSplit, favorite]
        for (container, children) in [(space.pinnedContainerID, [folder.id, split.id]), (space.favoritesContainerID, [favorite.id])] {
            if let index = document.items.firstIndex(where: { $0.id == container }) { document.items[index].children = children }
        }
        #expect(MobileRecentTabs.rows(phone: [], selected: nil, mac: document, limit: 10).map(\.title) == ["In a folder", "In a split", "Today"])

        space.standaloneWindowID = UUID()
        document.spaces[0] = space
        #expect(MobileRecentTabs.rows(phone: [], selected: nil, mac: document).isEmpty)
    }

    /// The sidebar comes from another device: a folder listed inside itself still ends, and its
    /// tab is listed once.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/591")) func aFolderInsideItselfStillEnds() {
        var folder = SidebarItem.folder("Loop", parent: nil)
        let inFolder = Self.mac("https://loop.example", "In the loop", 1)
        folder.children = [folder.id, inFolder.id]
        let document = Self.sidebar(today: [folder, inFolder])
        #expect(MobileRecentTabs.rows(phone: [], selected: nil, mac: document, limit: 10).map(\.title) == ["In the loop"])
    }
}

/// The bottom bar's buttons and the page menu's controls tick under the finger (#675).
struct MobilePressHapticsTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/675"))
    func theBarsButtonsTickOnlyAsTheFingerComesDown() {
        #expect(MobilePressHaptics.barButtons == ["bar-tabs", "bar-search", "bar-menu", "bar-spaces", "bar-settings"])
        for id in MobilePressHaptics.barButtons {
            #expect(MobilePressHaptics.tick(for: id, edge: .down) == .selection)
            #expect(MobilePressHaptics.tick(for: id, edge: .up) == nil)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/675"))
    func theMenusTilesAndRowsTickOnPress() {
        // Find on Page and Share tick once; Pin and Summarize again as the finger lets go.
        for id in ["menu-tile-findOnPage", "menu-tile-share"] {
            #expect(MobilePressHaptics.tick(for: id, edge: .down) == .press)
            #expect(MobilePressHaptics.tick(for: id, edge: .up) == nil)
        }
        for id in ["menu-tile-pin", "menu-tile-summarize"] {
            #expect(MobilePressHaptics.tick(for: id, edge: .down) == .press)
            #expect(MobilePressHaptics.tick(for: id, edge: .up) == .release)
        }
        for id in [
            "menu-row-displayOptions", "menu-row-translate", "menu-row-readerMode",
            "menu-row-requestDesktopSite", "menu-row-siteSettings",
            "menu-zoom-in", "menu-zoom-out", "menu-zoom-value",
            "menu-reload-without-blockers",
        ] {
            #expect(MobilePressHaptics.tick(for: id, edge: .down) == .press)
            #expect(MobilePressHaptics.tick(for: id, edge: .up) == nil)
        }
        // The address gives one very subtle selection tick instead of an impact.
        #expect(MobilePressHaptics.tick(for: "menu-host", edge: .down) == .selection)
        #expect(MobilePressHaptics.tick(for: "menu-host", edge: .up) == nil)
        // The zoom row itself has no action: only its stepper ticks.
        #expect(MobilePressHaptics.tick(for: "menu-row-pageZoom", edge: .down) == nil)
        #expect(MobilePressHaptics.policy(for: "nothing") == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/675"))
    func theCapsulesButtonsTickOnlyAsTheFingerLetsGo() {
        for id in ["menu-back", "menu-forward", "menu-reload", "menu-copy-link"] {
            #expect(MobilePressHaptics.tick(for: id, edge: .down) == nil)
            #expect(MobilePressHaptics.tick(for: id, edge: .up) == .release)
        }
    }
}

struct MobileSnapshotTests {
    /// A capture that came back black is not kept as the tab's picture, and is not shown on a
    /// flick's card, while a dark page still is: the black flash after a quick flick.
    @Test func aBlackCaptureIsBlankButADarkPageIsNot() {
        #expect(MobileSnapshot.looksBlank(red: 0, green: 0, blue: 0))
        #expect(MobileSnapshot.looksBlank(red: 0.01, green: 0.01, blue: 0.02))
        // iOS's dark background, #1c1c1e, with nothing on it.
        #expect(!MobileSnapshot.looksBlank(red: 0.11, green: 0.11, blue: 0.118))
        #expect(!MobileSnapshot.looksBlank(red: 1, green: 1, blue: 1))
    }
}

struct MobileFlickLandingTests {
    static let landing = MobileMotion.FlickLanding(from: CGPoint(x: 120, y: 300), to: CGPoint(x: 196, y: 426),
                                                   velocity: CGPoint(x: -1500, y: -800), angle: 0.08, spin: 0.4,
                                                   scale: 0.6)
    static let frames = stride(from: 0.0, through: 2.0, by: 1.0 / 120).map { landing.frame(after: $0) }

    /// Let go thrown left, the tab carries on left before it comes in: an arc, not a straight
    /// line to its place.
    @Test func aTabThrownSidewaysCarriesOnSidewaysFirst() {
        let leftmost = Self.frames.map(\.center.x).min() ?? 0
        #expect(leftmost < 120 - 20, "it keeps going the way it was thrown")
        #expect(Self.frames.last?.center == CGPoint(x: 196, y: 426))
        let offLine = Self.frames.map { frame -> CGFloat in
            let dx: CGFloat = 76, dy: CGFloat = 126
            return abs((frame.center.x - 120) * dy - (frame.center.y - 300) * dx) / hypot(dx, dy)
        }.max() ?? 0
        #expect(offLine > 20, "off the straight line from where it was let go to its place")
    }

    /// One smooth arc: each axis turns home at most once, never rocking back and forth.
    @Test func theLandingNeverRocksBackAndForth() {
        func crossings(_ values: [CGFloat]) -> Int { zip(values, values.dropFirst()).filter { $0 * $1 < 0 }.count }
        #expect(crossings(Self.frames.map { $0.center.x - 196 }) <= 1)
        #expect(crossings(Self.frames.map { $0.center.y - 426 }) <= 1)
        #expect(crossings(Self.frames.map(\.angle)) <= 1)
    }

    /// Worked out ahead, the landing is the same frames, ending on the one where it lands.
    @Test func theLandingWorkedOutAheadIsTheSameFrames() {
        let frames = Self.landing.frames(every: 1.0 / 120)
        #expect(frames.last?.done == true)
        #expect(frames.dropLast().allSatisfy { !$0.done })
        #expect(frames[10] == Self.landing.frame(after: 10.0 / 120))
        #expect(frames.count <= 2 * 120 + 1, "never longer than its two-second cap")
    }

    /// It lands straight, at the page's size, in its place.
    @Test func itLandsStraightAtThePagesSizeInItsPlace() {
        let landed = Self.frames.first { $0.done }
        #expect(landed?.angle == 0 && landed?.scale == 1 && landed?.center == CGPoint(x: 196, y: 426))
    }

    /// It grows to 101 % of the page and settles back on it, once.
    @Test func itGrowsJustPastThePageAndSettles() {
        let sizes = stride(from: 0.0, through: MobileMotion.flickGrow, by: 0.005)
            .map { MobileMotion.flickGrowth(from: 0.6, after: $0) }
        let peak = sizes.max() ?? 0
        #expect(peak > 1.005 && peak <= 1.0101)
        let top = sizes.firstIndex(of: peak) ?? 0
        #expect(zip(sizes[..<top], sizes[1...top]).allSatisfy { $0 <= $1 }, "it only rises to the top")
        #expect(zip(sizes[top...], sizes[(top + 1)...]).allSatisfy { $0 >= $1 }, "then only falls")
        #expect(abs((sizes.last ?? 0) - 1) < 0.0001)
        // Not all at once: a fifth of the way in it has done well under half its growth.
        let early = MobileMotion.flickGrowth(from: 0.6, after: MobileMotion.flickGrow * 0.2)
        #expect(early > 0.6 && (early - 0.6) / 0.41 < 0.45)
    }

    /// It leaves the hand at the hand's own speed, the sideways part counting more, always rising
    /// a little, straight up when the hand was still, and no faster than a hard flick.
    @Test func itLeavesTheHandAtTheHandsSpeed() {
        let gain = MobileMotion.flickSidewaysGain
        #expect(gain > 1, "a sideways throw shows more than an upward one")
        #expect(MobileMotion.flickLaunch(velocity: CGPoint(x: 700, y: -900)) == CGPoint(x: 700 * gain, y: -900))
        #expect(MobileMotion.flickLaunch(velocity: CGPoint(x: 0, y: 500)).y == -100)
        #expect(MobileMotion.flickLaunch(velocity: .zero) == CGPoint(x: 0, y: -600))
        #expect(MobileMotion.flickLaunch(velocity: CGPoint(x: 9000, y: -9000)) == CGPoint(x: 4000 * gain, y: -4000))
    }
}

struct MobileSideInsetsTests {
    // Measured in BrowserViewController.layoutChrome on Cra Duo, closed, iOS 27.1:
    // bounds 466 × 678, safeAreaInsets (top: 0, left: 0, bottom: 34, right: 84).
    @Test func closedDuoKeepsTheFieldAndFocusedCardLeftOfTheStatusColumn() {
        let size = CGSize(width: 466, height: 678)
        let sides = MobileSideInsets.applied(size: size, safeLeft: 0, safeRight: 84)
        #expect(sides.left == 0 && sides.right == 84)
        let field = MobileSearchSheet.openFieldFrame(width: size.width, sideInsets: sides)
        #expect(field == CGRect(x: 16, y: 16, width: 350, height: 48))
        #expect(field.maxX <= 382)
        #expect(MobileSearchSheet.accessoryFrame(field: field).maxX <= 382)
        #expect(MobileSearchSheet.incognitoToggleFrame(field: field).maxX <= 382)
        #expect(MobileSearchSheet.incognitoToggleFrame(field: field, labelledWidth: MobileSearchSheet.incognitoLabelledWidth).maxX <= 382)
        let usable = CGSize(width: 382, height: size.height)
        #expect(MobileTabCarousel.placement(relative: 0, in: size, sideInsets: sides).frame.maxX <= 382)
        for relative: CGFloat in [-1, 0, 1] {
            #expect(MobileTabCarousel.placement(relative: relative, in: size, sideInsets: sides)
                == MobileTabCarousel.placement(relative: relative, in: usable))
        }
        #expect(MobileTabCarousel.pitch(in: size, sideInsets: sides) == MobileTabCarousel.pitch(in: usable))
        #expect(MobileTabCarousel.position(start: 1, translation: -100, count: 4, in: size, sideInsets: sides)
            == MobileTabCarousel.position(start: 1, translation: -100, count: 4, in: usable))
        #expect(MobileTabCarousel.restingIndex(position: 1.2, velocity: -900, count: 4, in: size, sideInsets: sides)
            == MobileTabCarousel.restingIndex(position: 1.2, velocity: -900, count: 4, in: usable))
        // The same usable width with a left column shifts every card right by that inset.
        let left = MobileSideInsets.applied(size: size, safeLeft: 84, safeRight: 0)
        #expect(MobileTabCarousel.placement(relative: 0, in: size, sideInsets: left).frame
            == MobileTabCarousel.placement(relative: 0, in: usable).frame.offsetBy(dx: 84, dy: 0))
    }

    @Test func portraitIPhoneKeepsItsFieldAndCarousel() {
        let size = CGSize(width: 393, height: 852)
        let sides = MobileSideInsets.applied(size: size, safeLeft: 0, safeRight: 0)
        #expect(sides.left == 0 && sides.right == 0)
        #expect(MobileSearchSheet.openFieldFrame(width: size.width, sideInsets: sides)
            == CGRect(x: 16, y: 16, width: 361, height: 48))
        expectUnchangedCarousel(size: size, sides: sides)
    }

    @Test func landscapeIPhoneIgnoresItsSideSafeAreas() {
        // The spec's iPhone landscape fixture: 852 × 393 with 59 pt side insets.
        let size = CGSize(width: 852, height: 393)
        let sides = MobileSideInsets.applied(size: size, safeLeft: 59, safeRight: 59)
        #expect(sides.left == 0 && sides.right == 0)
        #expect(MobileSearchSheet.openFieldFrame(width: size.width, sideInsets: sides)
            == CGRect(x: 16, y: 16, width: 820, height: 48))
        expectUnchangedCarousel(size: size, sides: sides)
    }

    @Test func openDuoIgnoresAnySideSafeAreas() {
        // 951 × 669 is the research's open-screen size. Insets here are synthetic:
        // this builder keeps Cra Duo closed; open-posture measurement belongs to verification.
        let size = CGSize(width: 951, height: 669)
        for inset: CGFloat in [0, 59, 84] {
            let sides = MobileSideInsets.applied(size: size, safeLeft: inset, safeRight: inset)
            #expect(sides.left == 0 && sides.right == 0)
            #expect(MobileSearchSheet.openFieldFrame(width: size.width, sideInsets: sides)
                == CGRect(x: 16, y: 16, width: 919, height: 48))
            expectUnchangedCarousel(size: size, sides: sides)
        }
    }

    private func expectUnchangedCarousel(size: CGSize, sides: (left: CGFloat, right: CGFloat)) {
        for relative: CGFloat in [-1, 0, 1] {
            #expect(MobileTabCarousel.placement(relative: relative, in: size, sideInsets: sides)
                == MobileTabCarousel.placement(relative: relative, in: size))
        }
        #expect(MobileTabCarousel.pitch(in: size, sideInsets: sides) == MobileTabCarousel.pitch(in: size))
        #expect(MobileTabCarousel.position(start: 1, translation: -100, count: 4, in: size, sideInsets: sides)
            == MobileTabCarousel.position(start: 1, translation: -100, count: 4, in: size))
        #expect(MobileTabCarousel.restingIndex(position: 1.2, velocity: -900, count: 4, in: size, sideInsets: sides)
            == MobileTabCarousel.restingIndex(position: 1.2, velocity: -900, count: 4, in: size))
    }
}
