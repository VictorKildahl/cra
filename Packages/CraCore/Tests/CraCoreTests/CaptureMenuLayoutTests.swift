import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's menu beside a capture (Arc 1.173.1, 17 Nov 2026): the easels are in the menu itself.
struct CaptureMenuLayoutTests {
    private let test = CaptureMenuLayout.Destination(id: UUID(), title: "Test")
    private let movies = CaptureMenuLayout.Destination(id: UUID(), title: "Movies")

    private func titles(_ sections: [[CaptureMenuLayout.Row]]) -> [[String]] { sections.map { $0.map(\.title) } }

    @Test func theEaselsAreRowsOfTheMenuAfterNewEasel() {
        let s = CaptureMenuLayout.sections(easels: [test, movies])
        let expected: [[String]] = [["Copy", "Save...", "Send via iMessage..."], ["Edit", "Retake"], ["New Easel", "Test", "Movies"]]
        #expect(titles(s) == expected)
        #expect(s[2][1].item == .easel(test.id) && s[2][2].item == .easel(movies.id))
    }

    /// Arc's Edit row (#851): the capture opens in Arc's image editor, Easel's tools over it. It sits with Retake,
    /// above it, as in Arc 1.174 (26 Nov 2026, live).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/851"))
    func editSitsAboveRetakeAsInArc() {
        let s = CaptureMenuLayout.sections(easels: [])
        #expect(s[1].map(\.item) == [.edit, .retake])
        #expect(s[1][0].title == "Edit")
    }

    @Test func withNoEaselThereIsStillNewEasel() {
        let last: [String]? = titles(CaptureMenuLayout.sections(easels: [])).last
        #expect(last == ["New Easel"])
    }

    @Test func anEaselWithoutANameIsUntitled() {
        let blank = CaptureMenuLayout.Destination(id: UUID(), title: "")
        let last: [String]? = titles(CaptureMenuLayout.sections(easels: [blank])).last
        #expect(last == ["New Easel", "Untitled Easel"])
    }

    @Test func typingNarrowsTheRowsWhateverTheCase() {
        let narrowed: [[String]] = titles(CaptureMenuLayout.sections(easels: [test, movies], filter: " mov "))
        let onlyMovies: [[String]] = [["Movies"]]
        #expect(narrowed == onlyMovies)
        let withE: [[String]] = titles(CaptureMenuLayout.sections(easels: [test, movies], filter: "E"))
        let expected: [[String]] = [["Save...", "Send via iMessage..."], ["Edit", "Retake"], ["New Easel", "Test", "Movies"]]
        #expect(withE == expected)
        #expect(CaptureMenuLayout.sections(easels: [test], filter: "zzz").isEmpty)
    }

    @Test func onlyTheLatestEaselsAreListedUntilOneIsTyped() {
        let many = (1...12).map { CaptureMenuLayout.Destination(id: UUID(), title: "Easel \($0)") }
        let all = CaptureMenuLayout.sections(easels: many)
        #expect(all.last?.count == 1 + CaptureMenuLayout.easelLimit)
        let twelfth: [[String]] = titles(CaptureMenuLayout.sections(easels: many, filter: "easel 12"))
        let expected: [[String]] = [["Easel 12"]]
        #expect(twelfth == expected)
    }

    /// A short page (a Peek, a Little Window) lists the easels that fit: the menu pinned to the top
    /// margin ran its bottom rows, the easels, off the page. Typing still reaches the rest.
    @Test func aShortPageListsTheEaselsThatFit() {
        let many = (1...8).map { CaptureMenuLayout.Destination(id: UUID(), title: "Easel \($0)") }
        let tall = CaptureMenuLayout.height(CaptureMenuLayout.sections(easels: many))
        let room = tall - 3 * CaptureMenuLayout.rowHeight
        let fitted = CaptureMenuLayout.sections(easels: many, maxHeight: room)
        #expect(CaptureMenuLayout.height(fitted) <= room)
        #expect(fitted.last?.count == 1 + many.count - 3)
        #expect(fitted.last?.first?.item == .newEasel)
        // Never fewer than New Easel, however short.
        #expect(CaptureMenuLayout.sections(easels: many, maxHeight: 50).last?.map(\.item) == [.newEasel])
        let typed: [[String]] = titles(CaptureMenuLayout.sections(easels: many, filter: "easel 8", maxHeight: room))
        #expect(typed == [["Easel 8"]])
    }

    /// The field holding the keyboard keeps ⌘A ⌘V ⌘X ⌘Z (and ⇧⌘Z) for its text; any other ⌘ key ends the
    /// capture as before, and ⌘C ⌘S still copy and save the picture.
    @Test func theFieldKeepsItsEditingKeys() {
        for key in ["a", "v", "x", "z"] { #expect(CaptureMenuLayout.fieldKeeps(commandKey: key)) }
        for key in ["c", "s", "w", "t", "l"] { #expect(!CaptureMenuLayout.fieldKeeps(commandKey: key)) }
        #expect(CaptureMenuLayout.fieldKeeps(commandKey: "Z"))
    }

    @Test func itsHeightFollowsItsRows() {
        // Arc's menu with two easels is 433 pt (866 px at 2x): the field, nine rows, two lines and
        // the bottom. Cra's has eight rows there, without Save to Library: 40 pt less.
        let s = CaptureMenuLayout.sections(easels: [test, movies])
        let eight: CGFloat = 49.5 + 320 + 18 + 5.5
        #expect(CaptureMenuLayout.height(s) == eight)
        let none: CGFloat = 55
        #expect(CaptureMenuLayout.height([]) == none)
    }

    @Test func returnRunsTheFirstRowOnceSomethingIsTyped() {
        let s = CaptureMenuLayout.sections(easels: [test, movies], filter: "mov")
        #expect(CaptureMenuLayout.defaultRow(s, filter: "mov")?.item == .easel(movies.id))
        #expect(CaptureMenuLayout.defaultRow(CaptureMenuLayout.sections(easels: [test]), filter: "") == nil)
    }
}

/// The capture menu's colours are ARC_Capture.bundle's named colours (Arc 1.174.3 Assets.car, read with
/// `assetutil --info`), which have a light value and a dark one: Arc's menu follows the Mac's appearance.
struct CaptureMenuTonesTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/822")) func inLightModeTheCaptureMenuIsLight() {
        let t = CaptureMenuTones(dark: false)
        #expect(t.fill == .init(.white), "Background: white")
        #expect(t.text == .init(.black), "TextColor: black")
        #expect(t.field == .init(.black, 0.07), "TextFieldBackground: black 7 %")
        #expect(t.prompt == .init(.black, 0.45), "SeeMoreEaselTextColor: black 45 %")
        #expect(t.icon == .init(.black, 0.3), "ButtonText: black 30 %")
        #expect(t.divider == .init(.black, 0.07))
        // The picked row is the same blue in both, its title white.
        #expect(t.hover == CaptureMenuTones(dark: true).hover)
        #expect(t.hoverText.rgb == .white)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/822")) func inDarkModeTheCaptureMenuKeepsArcsDarkColours() {
        let t = CaptureMenuTones(dark: true)
        #expect(t.fill == .init(RGB(0.071, 0.059, 0.18)), "Background (dark): (18,15,46)")
        #expect(t.text == .init(.white, 0.9), "TextColor (dark): white 90 %")
        #expect(t.field == .init(.white, 0.07) && t.prompt == .init(.white, 0.45))
        #expect(t.hover == .init(RGB(0.161, 0.18, 0.757)))
    }
}
