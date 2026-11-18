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
