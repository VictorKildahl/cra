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
        // Neither an icon nor a theme is needed, and the search engine follows Settings unless picked.
        d.title = "Work"
        #expect(d.icon == .none && !d.themeChosen && d.searchEngine == nil && d.canCreate)
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
        // Cra's Search Engine row comes after Arc's two, like them.
        let search = CGRect(x: 13.5, y: 316, width: 223, height: 36)
        #expect(f.search == search)
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

    /// Arc's SwiftUI page compares its width with 227 and 190.
    @Test func thePageHasThreeLayoutsByWidth() {
        typealias D = SpaceCreationLayout.Density
        #expect(D(sidebarWidth: 250) == .wide && D(sidebarWidth: 227.5) == .wide)
        #expect(D(sidebarWidth: 227) == .medium && D(sidebarWidth: 190.5) == .medium)
        #expect(D(sidebarWidth: 190) == .narrow && D(sidebarWidth: 165) == .narrow)
        #expect(D.wide.showsRowGlyphs && !D.medium.showsRowGlyphs && !D.narrow.showsRowGlyphs)
        #expect(D.wide.rowLabelInset == 32 && D.medium.rowLabelInset == 16 && D.narrow.rowLabelInset == 16)
        #expect(!D.wide.stacksPills && !D.medium.stacksPills && D.narrow.stacksPills)
        #expect(D.wide.subtitle.contains("\n") && D.medium.subtitle.contains("\n") && !D.narrow.subtitle.contains("\n"))
    }

    /// A 165 pt sidebar, measured: the subtitle on three lines, the Profile row 60 pt tall.
    @Test func aNarrowSidebarStacksTheProfileRowUnderALongerSubtitle() {
        let f = SpaceCreationLayout.frames(in: CGSize(width: 165, height: 1155), subtitleLines: 3)
        #expect(f.subtitle.height == 49.5)
        let field = CGRect(x: 13.5, y: 205.5, width: 138, height: 35)
        #expect(f.field == field)
        #expect(f.profile.height == 60 && f.theme.height == 36 && f.search.height == 60)
        #expect(f.theme.minY == f.profile.maxY + 7)
        let pill = SpaceCreationLayout.pillFrame(row: f.profile.size, labelEnd: 62, fits: 70, trailing: 30, stacked: true)
        let stacked = CGRect(x: 8, y: 29, width: 122, height: 23)
        #expect(pill == stacked)
    }

    @Test func aPillStandsAGapAfterItsLabelAndNeverRunsPastTheRow() {
        let row = CGSize(width: 223, height: 36)
        let pill = SpaceCreationLayout.pillFrame(row: row, labelEnd: 78, fits: 70, trailing: 30, stacked: false)
        let beside = CGRect(x: 85.5, y: 7.25, width: 70, height: 21.5)
        #expect(pill == beside)
        // A long name is cut to what the row has left.
        let long = SpaceCreationLayout.pillFrame(row: row, labelEnd: 120, fits: 140, trailing: 8, stacked: false)
        #expect(long.minX == 127.5 && long.maxX == 215)
        // Cra's Search Engine row stacks when its pill has no room beside the label.
        #expect(!SpaceCreationLayout.pillFits(rowWidth: 223, labelEnd: 120, fits: 140, trailing: 8))
        #expect(SpaceCreationLayout.pillFits(rowWidth: 301, labelEnd: 124, fits: 134, trailing: 8))
        let f = SpaceCreationLayout.frames(in: CGSize(width: 250, height: 1155), searchStacked: true)
        #expect(f.profile.height == 36 && f.search.height == 60)
    }

    @Test func thePartsFollowTheSidebarsWidth() {
        let f = SpaceCreationLayout.frames(in: CGSize(width: 328, height: 700))
        #expect(f.field.width == 301 && f.create.width == 301)
        #expect(f.picture.midX == 164)
        #expect(f.create.maxY == 656)
        #expect(SpaceCreationLayout.minimumHeight < 460)
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
        // Arc's code: each part 0.03 s after the one under it, the cards 0.3 s after the press.
        #expect([A.themeRowStart, A.profileRowStart, A.fieldStart, A.subtitleStart, A.titleStart] == [0.03, 0.06, 0.09, 0.12, 0.15])
        #expect(A.buttonsFade.lowerBound == 0 && A.titleStart < A.dropStart && A.partSlide == 80 && A.partFade < A.partSlideTime)
        #expect(A.glow.upperBound < A.cardFade.lowerBound && A.cardFade.upperBound < A.done && A.done < 2.6)
        #expect(A.progress(A.buttonsFade, at: 0.085) == 0.5)
        #expect(A.progress(A.cardFade, at: 0) == 0 && A.progress(A.cardFade, at: 5) == 1)
        let card = A.cardFrame(in: CGSize(width: 250, height: 1155))
        let expected = CGRect(x: 93.75, y: 538, width: 62.5, height: 79)
        #expect(card == expected)
    }

    /// Arc's cards, measured 120 times a second against the spring its code names.
    @Test func theCardsDropOnASpringAndTurnOverOnTheWay() {
        typealias A = SpaceCreationAnimation
        // Still until 0.3 s, then down without a bounce: half way 0.52 s in.
        #expect(A.drop(at: 0.30) == 0 && A.drop(at: 0.1) == 0)
        for (t, measured) in [(0.35, 0.05), (0.517, 0.506), (0.60, 0.662), (0.767, 0.861), (0.90, 0.938), (1.10, 0.982)] {
            #expect(abs(A.drop(at: t) - measured) < 0.03, "drop at \(t)")
        }
        var last = 0.0
        for i in 0...200 {
            let v = A.drop(at: Double(i) / 100)
            #expect(v >= last && v <= 1)
            last = v
        }
        // The turn keeps step with the drop: edge-on half way down, the card facing as the glow comes.
        #expect(A.turn(at: 0.2) == 0 && A.turn(at: 0.7) == .pi * A.drop(at: 0.7))
        #expect(abs(A.turn(at: 0.515) - .pi / 2) < 0.03)
        #expect(A.turn(at: A.glow.lowerBound) > .pi * 0.99)
        // A 40 pt picture, 1.4 card heights edge-on, the card's own height at the end.
        #expect(A.height(at: 0) == 40 && A.height(at: 1) == 79 && A.height(at: 2) == 79 && A.height(at: -1) == 40)
        #expect(abs(A.height(at: 0.5) - 110.6) < 1e-9)
        // Arc's, read off its frames (as fractions of the way): the picture, then the card.
        for (p, measured) in [(0.234, 69.0), (0.28, 76), (0.377, 100), (0.682, 96), (0.782, 93), (0.853, 87.6), (0.903, 84), (0.973, 79)] {
            #expect(abs(A.height(at: p) - measured) < 9, "height at \(p)")
        }
        // The picture and the card swap as they turn.
        #expect(A.pictureOpacity(at: 0.4) == 1 && abs(A.pictureOpacity(at: 0.53) - 0.4) < 1e-9 && A.pictureOpacity(at: 1) == 0)
        #expect(A.cardOpacity(at: 0.3) == 0 && A.cardOpacity(at: 0.4) == 0.5 && A.cardOpacity(at: 0.7) == 1)
        #expect(A.cardOpacity(at: A.cardFade.upperBound) == 0)
    }

    @Test func aSwipeBackFollowsTheFingersAndLeavesPastHalfOrOnAFlick() {
        typealias S = SpaceCreationSwipe
        #expect(S.pull(travel: 0, width: 250) == 0 && S.pull(travel: 100, width: 250) == 0.4)
        #expect(S.pull(travel: -80, width: 250) == 0 && S.pull(travel: 400, width: 250) == 1 && S.pull(travel: 10, width: 0) == 0)
        #expect(!S.leaves(pull: 0.4, velocity: 0) && S.leaves(pull: 0.6, velocity: 0) && !S.leaves(pull: 0.5, velocity: 0.5))
        // A flick out leaves from anywhere; a flick back in stays, however far out it was.
        #expect(S.leaves(pull: 0.1, velocity: 2) && !S.leaves(pull: 0.9, velocity: -2) && !S.leaves(pull: 0, velocity: 2))
    }
}
