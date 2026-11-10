import CraCore
import Testing

struct MCPUnicodeTests {
    private func expectExact(_ text: String) {
        let pieces = MCPInputPlan.textPieces(text)
        #expect(pieces.allSatisfy { !$0.isEmpty && $0.utf16.count <= MCPInputPlan.pieceUTF16Limit })
        #expect(Array(pieces.joined().unicodeScalars) == Array(text.unicodeScalars))
        #expect(Array(pieces.joined().utf16) == Array(text.utf16))
        for piece in pieces {
            let units = Array(piece.utf16)
            #expect(!UTF16.isTrailSurrogate(units.first!) && !UTF16.isLeadSurrogate(units.last!))
        }
    }

    @Test func asciiStaysOneCharacterPerPiece() {
        #expect(MCPInputPlan.textPieces("") == [])
        #expect(MCPInputPlan.textPieces("Ab 1!") == ["A", "b", " ", "1", "!"])
        #expect(MCPInputPlan.textPieces("a\nb") == ["a", "\n", "b"])
        #expect(MCPInputPlan.textPieces("Mäx 🦊") == ["M", "ä", "x", " ", "🦊"])
    }

    @Test func shortSequencesRespectChromiumTerminator() {
        #expect(MCPInputPlan.textPieces("🇨🇭") == ["🇨", "🇭"])
        #expect(MCPInputPlan.textPieces("👍🏽") == ["👍", "🏽"])
        #expect(MCPInputPlan.textPieces("e\u{301}") == ["e\u{301}"])
        #expect(MCPInputPlan.textPieces("1\u{FE0F}\u{20E3}") == ["1\u{FE0F}\u{20E3}"])
        #expect(MCPInputPlan.textPieces("🇨🇭🇩🇪") == ["🇨", "🇭", "🇩", "🇪"])
        for text in ["🇨🇭", "👍🏽", "e\u{301}", "1\u{FE0F}\u{20E3}"] { expectExact(text) }
    }

    @Test func longGraphemesSplitBetweenScalars() {
        let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
        #expect(family.count == 1 && family.utf16.count == 11)
        #expect(MCPInputPlan.textPieces(family) == ["👨\u{200D}", "👩\u{200D}", "👧\u{200D}", "👦"])
        #expect(MCPInputPlan.textPieces("👩🏽\u{200D}💻") == ["👩", "🏽\u{200D}", "💻"])
        let stacked = "e" + String(repeating: "\u{301}", count: 5)
        #expect(stacked.count == 1)
        #expect(MCPInputPlan.textPieces(stacked) == ["e\u{301}\u{301}", "\u{301}\u{301}\u{301}"])
        #expect(MCPInputPlan.textPieces("a" + family + "b") == ["a", "👨\u{200D}", "👩\u{200D}", "👧\u{200D}", "👦", "b"])
        for text in [family, "👩🏽\u{200D}💻", stacked, "x\(family)🇨🇭\(stacked)\n👍🏽ä", "🏳\u{FE0F}\u{200D}🌈"] { expectExact(text) }
    }

    @Test func roundtripKeepsUnnormalisedScalars() {
        let decomposed = "Cafe\u{301} Å"
        let composed = "Café Å"
        #expect(decomposed == composed)
        #expect(Array(MCPInputPlan.textPieces(decomposed).joined().unicodeScalars) == Array(decomposed.unicodeScalars))
        #expect(Array(MCPInputPlan.textPieces(composed).joined().unicodeScalars) == Array(composed.unicodeScalars))
        expectExact("\u{1100}\u{1161}\u{11A8}" + String(repeating: "\u{20D7}", count: 7) + "\u{10FFFF}")
    }

    @Test func textCapBoundaries() {
        let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
        #expect(MCPInputPlan.textPieces(String(repeating: family, count: 25)).count == 100)
        #expect(MCPInputPlan.typesKeys(String(repeating: family, count: 25)))
        #expect(!MCPInputPlan.typesKeys(String(repeating: family, count: 26)))
        #expect(MCPInputPlan.validText(String(repeating: "a", count: 19_999) + "\n"))
        #expect(!MCPInputPlan.validText(String(repeating: "a", count: 20_000) + "\n"))
        #expect(MCPInputPlan.validText(String(repeating: "🦊", count: 20_000)))
        #expect(!MCPInputPlan.validText(String(repeating: "🦊", count: 20_001)))
        // Few characters can still be a huge payload: the UTF-8 bound holds them back.
        let stacked = "e" + String(repeating: "\u{301}", count: 4)
        #expect(MCPInputPlan.validText(String(repeating: stacked, count: 11_111)))
        #expect(!MCPInputPlan.validText(String(repeating: stacked, count: 11_112)))
    }

    @Test func controlsAreRejected() {
        for text in ["\t", "\r", "\r\n", "a\u{0}b", "\u{1b}[A", "\u{7f}", "👍🏽\u{8}"] { #expect(!MCPInputPlan.validText(text)) }
        #expect(MCPInputPlan.validText("line\nline 👨\u{200D}👩\u{200D}👧\u{200D}👦"))
    }

    @Test func durationBudgetCoversPlannedPauses() {
        let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
        let worstPause = MCPInputPlan.keyHold(1) + MCPInputPlan.keyGap(1)
        #expect(MCPInputPlan.durationBudget(text: "") == 45)
        #expect(MCPInputPlan.durationBudget(text: family) > MCPInputPlan.durationBudget(text: "a"))
        var previous = 0.0
        for count in [0, 1, 10, 64, 99, 100] {
            let text = String(repeating: "a", count: count)
            let budget = MCPInputPlan.durationBudget(text: text)
            let pieces = Double(MCPInputPlan.textPieces(text).count)
            #expect(budget >= 45 && budget <= 100 && budget >= previous)
            // Every typed piece keeps at least 50 ms for its focus check and key dispatches beyond the worst pauses.
            #expect(budget - 45 - pieces * worstPause >= pieces * 0.05)
            previous = budget
        }
        // Longer text goes in as one insertion per line, whatever its length.
        for count in [101, 256, 20_000] { #expect(MCPInputPlan.durationBudget(text: String(repeating: "a", count: count)) == 60) }
    }

    @Test func navigationKeysStay() {
        #expect(MCPInputPlan.keys["PageUp"]?.code == "PageUp")
        #expect(MCPInputPlan.keys["PageUp"]?.virtual == 33)
        #expect(MCPInputPlan.keys["PageDown"]?.code == "PageDown")
        #expect(MCPInputPlan.keys["PageDown"]?.virtual == 34)
    }
}
