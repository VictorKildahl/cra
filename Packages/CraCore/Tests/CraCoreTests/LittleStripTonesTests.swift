import CraCore
import Testing

/// Arc's Little Arc draws its strip from the default theme's dark palette in every space (1.168 with a
/// yellow space focused; 1.172.1, the same pixels after switching spaces, #329). #549 reported that the
/// strip doesn't take a green-teal space's theme: that is Arc's behaviour, kept on purpose.
struct LittleStripTonesTests {
    static func bytes(_ c: RGB) -> [Int] { [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) } }

    /// The reporter's Work space (a green-teal gradient), a yellow space, Arc's default blue, a dark
    /// theme, and an Auto theme with two different halves.
    static let themes: [SpaceTheme] = [
        SpaceTheme(colors: ["#6E9A72", "#2E7A78"], intensity: 0.7, noise: 0.1, appearance: "light"),
        SpaceTheme(colors: ["#F8D558"], intensity: 0.6, noise: 0.1, appearance: "light"),
        SpaceTheme(colors: ["#3139FB"], intensity: 0.6, noise: 0.1, appearance: "dark"),
        SpaceTheme(colors: ["#141318", "#2B2638"], intensity: 0.9, noise: 0.14, appearance: "dark", accent: "#E63333"),
        SpaceTheme(light: SpaceTheme(colors: ["#F8D558"], intensity: 0.6, noise: 0.1, appearance: "light"),
                   dark: SpaceTheme(colors: ["#2861B3"], intensity: 0.6, noise: 0.1, appearance: "dark")),
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/549"), .bug("https://github.com/VictorKildahl/cra/issues/329"),
          arguments: themes, [false, true])
    func theStripIsArcsGradientWhateverTheSpaceTheme(theme: SpaceTheme, systemDark: Bool) {
        let tones = LittleStripTones(target: theme, systemDark: systemDark)
        #expect(Self.bytes(tones.left) == [0x24, 0x24, 0x38])
        #expect(Self.bytes(tones.right) == [0x31, 0x23, 0x39])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/549"))
    func onlyTheSpaceNameTakesTheSpacesColour() {
        let work = LittleStripTones(target: Self.themes[0], systemDark: true)
        let yellow = LittleStripTones(target: Self.themes[1], systemDark: true)
        #expect(work.left == yellow.left && work.right == yellow.right)
        #expect(work.spaceName != yellow.spaceName)
        // The colour (its accent first) 72 % of the way to white: #F8D558 → (253, 243, 208).
        #expect(Self.bytes(yellow.spaceName) == [253, 243, 208])
        let w = Self.bytes(work.spaceName)
        #expect(w[1] > w[0], "a green space's name stays green: \(w)")
        let accent = LittleStripTones(target: Self.themes[3], systemDark: true)
        #expect(Self.bytes(accent.spaceName) == [248, 198, 198])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/549"))
    func anAutoThemesNameFollowsMacOSButItsStripDoesnt() {
        let light = LittleStripTones(target: Self.themes[4], systemDark: false)
        let dark = LittleStripTones(target: Self.themes[4], systemDark: true)
        #expect(light.left == dark.left && light.right == dark.right)
        #expect(Self.bytes(light.spaceName) == [253, 243, 208])
        #expect(light.spaceName != dark.spaceName)
    }
}
