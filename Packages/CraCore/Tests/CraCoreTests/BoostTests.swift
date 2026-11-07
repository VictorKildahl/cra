import CraCore
import Testing

/// Arc's Boosts (Arc 1.172.1): per-site restyles from the editor's controls.
struct BoostTests {
    @Test func aNewBoostChangesNothing() {
        let b = Boost(host: "www.Example.com")
        #expect(b.host == "example.com" && b.name == "My Boost" && b.enabled)
        #expect(b.colorsUntouched && b.stylesheet.isEmpty)
    }

    @Test func appliesToItsSiteAndSubdomains() {
        let b = Boost(host: "example.com")
        var off = Boost(host: "other.org"); off.enabled = false
        #expect(Boost.applying(to: "https://www.example.com/a", from: [b, off]).map(\.id) == [b.id])
        #expect(Boost.applying(to: "https://docs.example.com/", from: [b]).count == 1)
        #expect(Boost.applying(to: "https://notexample.com/", from: [b]).isEmpty)
        #expect(Boost.applying(to: "https://other.org/", from: [off]).isEmpty, "a disabled boost does nothing")
    }

    @Test func eachControlWritesItsRule() {
        var b = Boost(host: "example.com")
        b.invert = true
        b.contrast = 75
        b.font = 2
        b.textCase = .upper
        b.zapped = [".ad", "#banner"]
        b.css = "h1 { color: red }"
        let css = b.stylesheet
        #expect(css.contains("invert(1) hue-rotate(180deg)") && css.contains("contrast(1.5)"))
        #expect(css.contains("img, video") , "pictures are flipped back under an inverted page")
        #expect(css.contains("\"ui-serif\"") && css.contains("uppercase"))
        #expect(css.contains(".ad, #banner { display: none !important; }") && css.hasSuffix("h1 { color: red }"))
    }

    @Test func aTintNeedsStrength() {
        var b = Boost(host: "example.com")
        b.hue = 0.5
        #expect(b.stylesheet.isEmpty, "a hue alone, with the handle in the middle, tints nothing")
        b.strength = 0.6
        #expect(b.stylesheet.contains("sepia(0.6)"))
    }

    @Test func twentyFontsFiveToARow() {
        #expect(Boost.fonts.count == 20 && Set(Boost.fonts).count == 20)
    }
}
