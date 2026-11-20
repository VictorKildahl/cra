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

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func theSiteControlCenterListsTheSitesBoostsOnOrOff() {
        let b = Boost(host: "example.com")
        var off = Boost(host: "docs.example.com"); off.enabled = false
        let other = Boost(host: "other.org")
        #expect(Boost.onSite(of: "https://docs.example.com/a", from: [b, off, other]).map(\.id) == [b.id, off.id])
        #expect(Boost.onSite(of: "cra://settings", from: [b]).isEmpty)
    }

    /// A Boost's colours leave the page's images alone, as in Arc (#602; Arc 1.174, 20 Nov 2026: Wikipedia's
    /// photos kept their pixels under a strong tint). On Cra's Chromium engine the tint is a colour matrix the
    /// engine draws every colour but images through, the same colours CSS's sepia hue-rotate saturate gave; the
    /// stylesheet then leaves the tint out and keeps the other controls.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/602"))
    func theTintIsAColourMatrixTheEngineDrawsAroundImages() throws {
        var b = Boost(host: "example.com")
        #expect(b.tintMatrix == nil && b.tintMatrixString == nil, "no tint, no matrix")
        b.hue = 0.7
        b.strength = 0.6
        b.contrast = 60
        let m = try #require(b.tintMatrix)
        #expect(m.count == 20 && Array(m[15...]) == [0, 0, 0, 1, 0], "alpha is left as it is")
        #expect(b.tintMatrixString?.split(separator: ",").count == 20)
        #expect(b.stylesheet.contains("sepia(") && b.stylesheet.contains("contrast("))
        let engine = b.stylesheet(engineTints: true)
        #expect(!engine.contains("sepia(") && !engine.contains("hue-rotate(") && engine.contains("contrast("),
                "the engine draws the tint; the rest stays CSS")

        // The CSS chain, step by step with its clamping, against the one matrix, for colours that stay in range.
        func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
        func css(_ c: [Double]) -> [Double] {
            var v = c
            let steps: [Boost.Matrix3] = [Boost.sepia(0.6), Boost.hueRotate(degrees: 0.7 * 360 - 38), Boost.saturate(2.2)]
            for step in steps {
                var next: [Double] = [0, 0, 0]
                for r in 0..<3 {
                    var sum = 0.0
                    for k in 0..<3 { sum += step[r][k] * v[k] }
                    next[r] = clamp(sum)
                }
                v = next
            }
            return v
        }
        func matrix(_ c: [Double]) -> [Double] {
            var out: [Double] = [0, 0, 0]
            for r in 0..<3 {
                var sum = m[r * 5 + 4]
                for k in 0..<3 { sum += m[r * 5 + k] * c[k] }
                out[r] = clamp(sum)
            }
            return out
        }
        for colour in [[0.2, 0.2, 0.2], [0.4, 0.3, 0.2], [0.1, 0.3, 0.5]] {
            for (a, b) in zip(css(colour), matrix(colour)) { #expect(abs(a - b) < 0.002, "\(colour)") }
        }
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
