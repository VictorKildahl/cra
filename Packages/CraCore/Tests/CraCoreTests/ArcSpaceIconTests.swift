import CraCore
import Testing

/// Arc space icons import as the same icon in Cra: emoji, and the Icon tab's glyphs as the SF Symbol
/// in the same slot of Cra's Icon tab, which used to come over as 🗂️.
struct ArcSpaceIconTests {
    static let any: (String) -> Bool = { _ in true }

    /// Arc's Icon tab has 56 glyphs (7 rows of 8), each once, and Cra's grid has one per slot.
    @Test
    func pickerHasArcsFiftySixGlyphs() {
        #expect(ArcSpaceIcon.picker.count == 56)
        #expect(Set(ArcSpaceIcon.picker.map(\.arc)).count == 56)
        #expect(Set(SpaceIcon.pickerSymbols).count == 56)
    }

    @Test(arguments: [
        ("star", "star.fill"), ("flash", "bolt.fill"), ("planet", "globe.americas.fill"), ("cloudOutline", "cloud"),
        ("train", "tram.fill"), ("rss", "dot.radiowaves.up.forward"), ("search", "magnifyingglass"),
    ])
    func iconTabGlyphsBecomeTheirSymbol(arc: String, symbol: String) {
        #expect(ArcSpaceIcon.icon(["icon": arc], symbolExists: Self.any) == .symbol(symbol))
    }

    /// A glyph Cra has no symbol for (Arc's brand marks, a name from a later Arc) keeps an icon.
    @Test(arguments: ["github", "linear", "figma", "someFutureGlyph"])
    func unknownGlyphsGetTheFallback(arc: String) {
        #expect(ArcSpaceIcon.icon(["icon": arc], symbolExists: Self.any) == .emoji("🗂️"))
    }

    /// Emoji read as before: `emoji_v2` first (it holds ZWJ sequences the number can't), then the number.
    @Test
    func emojiReadAsBefore() {
        #expect(ArcSpaceIcon.icon(["emoji_v2": "🧑‍💻", "emoji": 11036], symbolExists: Self.any) == .emoji("🧑‍💻"))
        #expect(ArcSpaceIcon.icon(["emoji": 128038], symbolExists: Self.any) == .emoji("🐦"))
        #expect(ArcSpaceIcon.icon(nil, symbolExists: Self.any) == .none)
        #expect(ArcSpaceIcon.icon([:], symbolExists: Self.any) == .emoji("🗂️"))
    }

    /// Arc's `symbol` case names an SF Symbol: kept when macOS has it, the fallback otherwise.
    @Test
    func symbolCaseNeedsARealSymbol() {
        #expect(ArcSpaceIcon.icon(["symbol": "leaf.fill"], symbolExists: { $0 == "leaf.fill" }) == .symbol("leaf.fill"))
        #expect(ArcSpaceIcon.icon(["symbol": "no.such.symbol"], symbolExists: { $0 == "leaf.fill" }) == .emoji("🗂️"))
    }
}
