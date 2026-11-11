import CraCore
import Testing

struct ExtensionIconsTests {
    /// Google Translate's manifest has 16, 48 and 128 px icons. A 16 pt button on a Retina screen
    /// needs 32 px: Chrome draws the 48 px file there, Cra drew the 16 px one doubled.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"))
    func retinaTakesTheNextSizeUp() {
        let icons = ["16": "icons/16.png", "48": "icons/48.png", "128": "icons/128.png"]
        #expect(ExtensionIcons.files(icons, points: 16) == ["icons/16.png", "icons/48.png"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"), arguments: [
        // An exact 2x file is the one.
        (["16": "a", "32": "b", "48": "c", "128": "d"], ["a", "b"]),
        // Only large files: the smallest that is big enough serves both scales.
        (["48": "c", "128": "d"], ["c"]),
        (["128": "d"], ["d"]),
        // Only a small one: it is all there is (MATCH_SMALLER).
        (["16": "a"], ["a"]),
        // MV2 browser actions' 19 and 38 px.
        (["19": "s", "38": "l"], ["s", "l"]),
        // Keys that aren't sizes are ignored; nothing left is no icon.
        (["16": "a", "large": "x", "0": "z"], ["a"]),
        ([:], []),
    ])
    func choice(icons: [String: String], files: [String]) {
        #expect(ExtensionIcons.files(icons, points: 16) == files)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"))
    func threeTimesTakesTheLargerStill() {
        let icons = ["16": "a", "32": "b", "48": "c", "128": "d"]
        #expect(ExtensionIcons.files(icons, points: 16, scales: [3, 1, 2]) == ["a", "b", "c"])
    }
}
