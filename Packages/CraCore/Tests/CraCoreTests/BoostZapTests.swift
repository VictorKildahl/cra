import CraCore
import Testing

/// Arc's Zap shelf and confirm popover (Arc 1.172.2, measured 12 Nov 2026).
struct BoostZapTests {
    @Test func theHintFollowsTheShelf() {
        #expect(BoostZap.hint(zapped: [], hovered: nil) == .instructions)
        #expect(BoostZap.hint(zapped: ["#ad"], hovered: nil) == .clickToUnzap)
        #expect(BoostZap.hint(zapped: ["#ad", ".promo"], hovered: 1) == .restore(".promo"))
        #expect(BoostZap.hint(zapped: ["#ad"], hovered: 3) == .clickToUnzap, "a cell that's gone restores nothing")
    }

    @Test func cellsAndHintSitWhereArcPutsThem() {
        // Arc: the shelf is 58 pt; its first cell is 38 pt at x 10 in a shelf 10 pt in from the card.
        #expect(BoostZap.shelfHeight == 58 && BoostZap.cellSide == 38)
        #expect(BoostZap.cellX(0) == 20)
        #expect(BoostZap.cellX(1) == 20 + 38 + BoostZap.cellGap)
        // "← Click to unzap" at 79.5 and the Restore pill at 61 with one cell (AX frames in the window).
        #expect(BoostZap.hintX(cells: 1, pill: false) == 79.5)
        #expect(BoostZap.hintX(cells: 1, pill: true) == 61)
    }

    @Test func unzapShowsItAgainAndZapKeepsOneOfEach() {
        var b = Boost(host: "example.com")
        b.zap("#ad"); b.zap(".promo"); b.zap("#ad"); b.zap("")
        #expect(b.zapped == ["#ad", ".promo"])
        b.unzap("#ad")
        #expect(b.zapped == [".promo"])
        #expect(!b.stylesheet.contains("#ad"), "an unzapped element is visible again")
        b.unzap(".promo")
        #expect(b.stylesheet.isEmpty)
    }

    @Test func readsWhatThePageZapped() {
        #expect(BoostZap.parseTaken("") == [])
        #expect(BoostZap.parseTaken(##"["#a",".b > p",""]"##) == ["#a", ".b > p"])
        #expect(BoostZap.parseTaken("not json") == [])
        #expect(BoostZap.parseTaken(##"["#a","x{} body{background:red} y","@import url(x)","a;b"]"##) == ["#a"],
                "the page answers: nothing that closes the rule or opens a block gets into the boost")
    }

    @Test func thePopoverSaysWhatArcSays() {
        #expect([BoostZap.zapThis, BoostZap.zapRelated, BoostZap.cancel] == ["Zap this", "Zap all related elements", "Cancel"])
        #expect(BoostZap.script.contains("Zap this") && BoostZap.script.contains("Zap all related elements"))
        #expect(BoostZap.script.contains("mix-blend-mode:multiply") && BoostZap.script.contains("display-p3 0.9686 0.8078 0.2745"))
    }
}
