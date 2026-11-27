import CraCore
import Foundation
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

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func theSiteControlCenterListsTheSitesBoostsOnOrOff() {
        let b = Boost(host: "example.com")
        var off = Boost(host: "docs.example.com"); off.enabled = false
        let other = Boost(host: "other.org")
        #expect(Boost.onSite(of: "https://docs.example.com/a", from: [b, off, other]).map(\.id) == [b.id, off.id])
        #expect(Boost.onSite(of: "cra://settings", from: [b]).isEmpty)
    }

    /// A Boost's colours leave the page's images alone, as in Arc (#602; Arc 1.174, 20 Nov 2026: Wikipedia's
    /// photos kept their pixels under a strong tint), in Arc's own colours: a colorize by lightness between the
    /// two handles' hues (21 Nov 2026). On Cra's Chromium engine the engine draws every colour but images
    /// through it; the stylesheet then leaves the tint out and keeps the other controls.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/602"))
    func theTintIsArcsColorizeTheEngineDrawsAroundImages() throws {
        var b = Boost(host: "example.com")
        #expect(b.tint == nil, "no tint, nothing for the engine")
        b.hue = 0.7
        b.strength = 0.6
        b.contrast = 60
        let tint = try #require(b.tint)
        #expect(tint.engineString.split(separator: ",").count == 6)
        #expect(b.stylesheet.contains("sepia(") && b.stylesheet.contains("contrast("))
        let engine = b.stylesheet(engineTints: true)
        #expect(!engine.contains("sepia(") && !engine.contains("hue-rotate(") && engine.contains("contrast("),
                "the engine draws the tint; the rest stays CSS")

        // Arc 1.174's own pixels (offline Arc, 21 Nov 2026), the handle at three places: the swatch's sRGB colour in,
        // Arc's out, within 4/255.
        let arc: [(hue: Double, strength: Double, in: [Double], out: [Double])] = [
            (0.5, 20.0 / 56, [0, 0, 0], [13, 14, 18]), (0.5, 20.0 / 56, [255, 255, 255], [246, 248, 248]),
            (0.5, 20.0 / 56, [255, 0, 0], [51, 154, 211]), (0.5, 20.0 / 56, [128, 128, 0], [26, 70, 122]),
            (0, 39.0 / 56, [128, 128, 128], [175, 127, 97]), (0, 39.0 / 56, [153, 255, 255], [245, 164, 150]),
            (0, 39.0 / 56, [0, 0, 0], [45, 40, 23]), (0.8342, 1, [255, 255, 255], [242, 216, 242]),
            (0.8342, 1, [0, 0, 0], [76, 26, 38]), (0.8342, 1, [128, 128, 128], [198, 83, 155]),
            (0.8342, 1, [255, 0, 0], [255, 24, 167]), (0.8342, 1, [128, 128, 0], [192, 0, 83]),
        ]
        for c in arc {
            var boost = Boost(host: "example.com")
            boost.hue = c.hue
            boost.strength = c.strength
            let t = try #require(boost.tint)
            let o = t.apply(c.in[0] / 255, c.in[1] / 255, c.in[2] / 255)
            for (got, want) in zip([o.r, o.g, o.b], c.out) {
                #expect(abs(got * 255 - want) <= 4, "\(c.hue) \(c.strength) \(c.in): \(got * 255) for Arc's \(want)")
            }
        }
        // Every saturated colour of one lightness comes out the same, as in Arc.
        let red = tint.apply(1, 0, 0), blue = tint.apply(0, 0, 1)
        #expect(abs(red.r - blue.r) < 1e-9 && abs(red.g - blue.g) < 1e-9 && abs(red.b - blue.b) < 1e-9)
    }

    /// The small wheel handle is the dark half of the tint (#478): moving it changes what happens to
    /// dark pixels but not light ones, and a boost saved before it was movable keeps Arc's eighth turn.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func theDarkHueIsTheSmallHandle() throws {
        var b = Boost(host: "example.com")
        b.hue = 0.2; b.strength = 0.6
        let original = try #require(b.tint)
        #expect(abs(original.darkHue - BoostWheel.accentOffset) < 1e-9)
        b.darkHue = 0.4
        let tint = try #require(b.tint)
        #expect(abs(tint.darkHue - 0.4) < 1e-9)
        let white = tint.apply(1, 1, 1), black = tint.apply(0, 0, 0)
        let oldWhite = original.apply(1, 1, 1), oldBlack = original.apply(0, 0, 0)
        #expect(max(abs(white.r - oldWhite.r), abs(white.g - oldWhite.g), abs(white.b - oldWhite.b)) < 1e-9,
                "light pixels keep the big handle's hue")
        #expect(max(abs(black.r - oldBlack.r), abs(black.g - oldBlack.g), abs(black.b - oldBlack.b)) > 0.01,
                "dark pixels follow the small handle")

        let old = """
        {"id":"6E4C0D40-CDBA-4F0D-9E4B-5A2D8E4B0001","host":"example.com","name":"My Boost","enabled":true,
         "hue":0.3,"strength":0.5,"invert":false,"contrast":50,"brightness":50,"saturation":50,"font":null,
         "textScale":1,"textCase":"none","zapped":[],"css":"","js":""}
        """
        let decoded = try JSONDecoder().decode(Boost.self, from: Data(old.utf8))
        #expect(decoded.darkHue == BoostWheel.accentOffset)
        let saved = try JSONEncoder().encode(b)
        #expect(String(data: saved, encoding: .utf8)?.contains("\"darkHue\":0.4") == true)
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

/// Arc's Boost editor motion, from 60 fps recordings of Arc 1.172.1.
struct BoostEditorMotionTests {
    @Test func opensByGrowingFromItsRightEdge() {
        #expect(BoostEditorMotion.openScale == 0.85 && BoostEditorMotion.openDuration == 0.28)
        #expect(BoostEditorMotion.openAnchor.x == 1 && BoostEditorMotion.openAnchor.y == 0.5)
    }

    @Test func codeWidensSlowlyAndBackNarrowsQuickly() {
        #expect(BoostEditorMotion.resizeDuration(fromWidth: 183, to: 480) == 0.35)
        #expect(BoostEditorMotion.resizeDuration(fromWidth: 480, to: 183) == 0.13)
        #expect(BoostEditorMotion.resizeDuration(fromWidth: 183, to: 183) == 0)
    }
}
