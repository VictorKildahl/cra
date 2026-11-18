import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's "Create a Space" page (Arc 1.173.1, 18 Nov 2026).
struct SpaceCreationTests {
    private func draft() -> SpaceCreationDraft {
        SpaceCreationDraft(theme: SpaceColorPresets.newSpaceTheme(index: 0), profile: nil)
    }

    @Test func createSpaceIsOnAsSoonAsTheNameHasACharacter() {
        var d = draft()
        #expect(!d.canCreate)
        d.title = "H"
        #expect(d.canCreate)
        d.title = ""
        #expect(!d.canCreate)
        d.title = "   "
        #expect(!d.canCreate)
        // Neither an icon nor a theme is needed.
        d.title = "Work"
        #expect(d.icon == .none && !d.themeChosen && d.canCreate)
    }

    @Test func theNameIsTrimmedAndHeldToASpacesLength() {
        var d = draft()
        d.title = "  Hello  "
        #expect(d.createdTitle == "Hello")
        d.title = String(repeating: "x", count: 500)
        #expect(d.createdTitle == Space.limitedTitle(d.title))
    }

    @Test func theDockShowsADotUntilAThemeIsChosenThenTheIcon() {
        var d = draft()
        let dot = SpaceDockMark.dot(diameter: 8)
        #expect(d.dockMark == dot)
        d.icon = .emoji("🤩")
        #expect(d.dockMark == dot)
        d.themeChosen = true
        #expect(d.dockMark == .emoji("🤩"))
        d.icon = .none
        #expect(d.dockMark == dot)
        d.icon = .symbol("star")
        #expect(d.dockMark == .symbol("star"))
    }

    /// Arc's page in a 250 pt sidebar: the field 223 × 35 at 13.6, the rows 36 pt, 6 and 7 pt apart.
    @Test func thePartsStandWhereArcsDo() {
        let f = SpaceCreationLayout.frames(in: CGSize(width: 250, height: 1155))
        let field = CGRect(x: 13.5, y: 189, width: 223, height: 35)
        #expect(f.field == field)
        let profile = CGRect(x: 13.5, y: 230, width: 223, height: 36)
        #expect(f.profile == profile)
        let theme = CGRect(x: 13.5, y: 273, width: 223, height: 36)
        #expect(f.theme == theme)
        // The dashed "+" is 18 pt, centred in the field's height, 21 pt from the sidebar's edge.
        let icon = CGRect(x: 21, y: 197.5, width: 18, height: 18)
        #expect(f.icon == icon)
        let picture = CGRect(x: 93, y: 37, width: 64, height: 41)
        #expect(f.picture == picture)
        // Create Space ends 44 pt above the page's bottom; Cancel is centred 23 pt above it.
        let create = CGRect(x: 13.5, y: 1075.5, width: 223, height: 35.5)
        #expect(f.create == create)
        #expect(f.cancel.midY == 1132)
        #expect(f.title.minY == 98 && f.subtitle.minY == 128)
    }

    @Test func thePartsFollowTheSidebarsWidth() {
        let f = SpaceCreationLayout.frames(in: CGSize(width: 328, height: 700))
        #expect(f.field.width == 301 && f.create.width == 301)
        #expect(f.picture.midX == 164)
        #expect(f.create.maxY == 656)
        #expect(SpaceCreationLayout.minimumHeight < 420)
    }

    @Test func theDockDrawsCloserWithOneMoreItem() {
        // Five spaces and the new one, in a 250 pt sidebar's dock: 28 pt each.
        let six: [CGFloat] = Array(repeating: 28, count: 6)
        #expect(SpaceDock.widthsWhileCreating(count: 5, room: 230) == six)
        // Twelve spaces share what room there is, in half points.
        let many = SpaceDock.widthsWhileCreating(count: 12, room: 230)
        #expect(many.count == 13 && many[0] == 17.5)
        let one: [CGFloat] = [28, 28]
        #expect(SpaceDock.widthsWhileCreating(count: 1, room: 230) == one)
    }

    @Test func theCreationAnimationRunsFromTheBottomUp() {
        typealias A = SpaceCreationAnimation
        #expect(A.buttonsFade.lowerBound < A.rowsFade.lowerBound && A.rowsFade.lowerBound < A.headingFade.lowerBound)
        #expect(A.headingFade.upperBound <= A.tip.lowerBound && A.tip.upperBound <= A.cardDrop.lowerBound)
        #expect(A.cardDrop.upperBound < A.glow.lowerBound && A.glow.upperBound < A.cardFade.lowerBound)
        #expect(A.cardFade.upperBound < A.done && A.done < 2.6)
        #expect(A.progress(A.buttonsFade, at: 0.075) == 0.5)
        #expect(A.progress(A.cardDrop, at: 0) == 0 && A.progress(A.cardDrop, at: 5) == 1)
        let card = A.cardFrame(in: CGSize(width: 250, height: 1155))
        let expected = CGRect(x: 93.75, y: 538, width: 62.5, height: 79)
        #expect(card == expected)
    }
}
