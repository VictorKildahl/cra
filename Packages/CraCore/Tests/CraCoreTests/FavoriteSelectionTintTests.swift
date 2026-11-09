import Foundation
import Testing
@testable import CraCore

struct FavoriteSelectionTintTests {
    @Test(arguments: ["#4BC477", "#F02539", "#FFE000", "#367CF5"])
    func keepsSiteHue(icon: String) {
        let source = SpaceColorWheel.hsb(icon)
        for color in FavoriteSelectionTint.colors(iconColors: [icon], dark: true) {
            let result = SpaceColorWheel.hsb(color)
            let distance = abs(source.hue - result.hue)
            #expect(min(distance, 360 - distance) < 1)
        }
    }

    /// Victor, 9 Nov 2026: X and GitHub got a blue outline that has nothing to do with their
    /// logos. A logo without colour is outlined in ink that stands out on the tile.
    @Test(arguments: [nil, "#000000", "#FFFFFF", "#808080", "invalid"] as [String?])
    func neutralOrMissingIconsUseInk(icon: String?) {
        for dark in [true, false] {
            let colors = FavoriteSelectionTint.colors(iconColors: icon.map { [$0] }, dark: dark)
            #expect(colors == FavoriteSelectionTint.colors(iconColors: nil, dark: dark))
            #expect(Set(colors).count == 1)
            let tint = SpaceColorWheel.hsb(colors[0])
            #expect(tint.saturation < 0.05, "no hue for a logo that has none")
            #expect(dark ? tint.brightness > 0.9 : tint.brightness < 0.2)
        }
    }

    @Test func paleIconStaysVisibleOnBlack() {
        let color = FavoriteSelectionTint.colors(iconColors: ["#A0C7AC"], dark: true)[1]
        let tint = SpaceColorWheel.hsb(color)
        #expect(tint.saturation > 0.44 && tint.brightness > 0.80)
    }

    @Test func lightTilesUseADarkerOutline() {
        let light = FavoriteSelectionTint.colors(iconColors: ["#FFE000"], dark: false)[1]
        let dark = FavoriteSelectionTint.colors(iconColors: ["#FFE000"], dark: true)[1]
        #expect(HexColor.luminance(light)! < HexColor.luminance(dark)!)
    }

    @Test func keepsAllFourLogoColorsInTheirPositions() {
        let palette: [[UInt8]] = [[255, 0, 0, 255], [255, 255, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]]
        var pixels: [UInt8] = []
        for y in 0..<8 {
            for x in 0..<8 {
                let quadrant = y < 4 ? (x < 4 ? 0 : 1) : (x < 4 ? 3 : 2)
                pixels += palette[quadrant]
            }
        }
        let colors = FavoriteSelectionTint.sample(rgba: pixels, width: 8, height: 8)
        #expect(colors.count == 17 && colors.first == colors.last)
        #expect(colors[2] == "#FFFF00" && colors[6] == "#00FF00")
        #expect(colors[10] == "#0000FF" && colors[14] == "#FF0000")
        #expect(Set(FavoriteSelectionTint.colors(iconColors: colors, dark: true)).count == 4)
    }

    @Test func whiteAndTransparentPixelsDoNotDiluteTheLogo() {
        let pixels: [UInt8] = [255, 255, 255, 255, 0, 0, 0, 0, 128, 0, 0, 128, 255, 255, 255, 255]
        let colors = FavoriteSelectionTint.sample(rgba: pixels, width: 2, height: 2)
        #expect(colors.count == 17 && Set(colors) == ["#FF0000"])
    }

    @Test func missingOrNeutralPixelsFallBackSafely() {
        #expect(FavoriteSelectionTint.sample(rgba: [], width: 0, height: 0).isEmpty)
        #expect(FavoriteSelectionTint.sample(rgba: [255, 255, 255, 255], width: 1, height: 1).isEmpty)
        #expect(FavoriteSelectionTint.sample(rgba: [255], width: 4, height: 4).isEmpty)
    }
}

/// PR #267: the logo-coloured outline is opt-in; a fresh install and settings saved before it
/// existed keep Arc's neutral rim, and turning it on survives a save.
struct FavoriteLogoOutlineSettingTests {
    @Test func offUnlessTurnedOn() throws {
        let decoder = ModelFixtureTests.decoder
        for s in [AppSettings(), try decoder.decode(AppSettings.self, from: Data("{}".utf8))] {
            #expect(!s.favoriteLogoOutline)
        }
        var on = AppSettings()
        on.favoriteLogoOutline = true
        #expect(try decoder.decode(AppSettings.self, from: JSONEncoder().encode(on)).favoriteLogoOutline)
    }
}
