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
        let expected: [[String]] = [["Copy", "Save...", "Send via iMessage..."], ["Retake"], ["New Easel", "Test", "Movies"]]
        #expect(titles(s) == expected)
        #expect(s[2][1].item == .easel(test.id) && s[2][2].item == .easel(movies.id))
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
        let expected: [[String]] = [["Save...", "Send via iMessage..."], ["Retake"], ["New Easel", "Test", "Movies"]]
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
        // the bottom. Cra's has seven rows there, without Save to Library and Edit.
        let s = CaptureMenuLayout.sections(easels: [test, movies])
        let seven: CGFloat = 49.5 + 280 + 18 + 5.5
        #expect(CaptureMenuLayout.height(s) == seven)
        let none: CGFloat = 55
        #expect(CaptureMenuLayout.height([]) == none)
    }

    @Test func returnRunsTheFirstRowOnceSomethingIsTyped() {
        let s = CaptureMenuLayout.sections(easels: [test, movies], filter: "mov")
        #expect(CaptureMenuLayout.defaultRow(s, filter: "mov")?.item == .easel(movies.id))
        #expect(CaptureMenuLayout.defaultRow(CaptureMenuLayout.sections(easels: [test]), filter: "") == nil)
    }
}
