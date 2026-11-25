import Foundation

/// The theme editor's preset swatches (Arc 1.171: SpaceStyleEditor's preset pages). Arc's colours
/// are named colours in ARCClients_BaseAssets' asset catalog, four groups of nine
/// (ColorPickerBrand1–9, Drab, Pastel, Greyscale), defined in sRGB, extended linear sRGB or
/// Display P3; these are their sRGB values, as Arc writes them to StorableSidebar.json (Brand8 →
/// 0.4236, 0.7286, 0.8512). Each page also sets the pad's wheel (#632): a page-2 swatch is three
/// colours on Arc's `analogous` wheel, and every other page gives one colour, which + takes across
/// the wheel (`complimentary`).
public enum SpaceColorPresets {
    public static let brand = ["#F2EAE4", "#F29BBB", "#A6729D", "#F25E6B", "#FF8558", "#F8D558", "#34E895", "#6CBAD9", "#666789"]
    public static let drab = ["#4E3A5A", "#693558", "#8F4042", "#B16D40", "#D7B35D", "#CDCCA4", "#7AA982", "#226149", "#26456B"]
    public static let pastel = ["#FEFBFA", "#FFE9F3", "#F1D1EC", "#FFCBD1", "#FFE0D3", "#FFF9E5", "#DEFDEB", "#DCF3FC", "#C5C6E5"]
    public static let greyscale = ["#FFFFFF", "#E6E6E6", "#CCCCCC", "#B2B2B2", "#808080", "#666666", "#333333", "#1A1A1A", "#000000"]
    /// The second colour Arc saves for each page-2 swatch (offline Arc 1.171 and 1.174, the swatches
    /// pressed over AX: `baseColors[1]` in StorableSidebar.json), 40° on round the analogous wheel.
    public static let brandPairs = ["#EFF1E3", "#EFB19B", "#A6727F", "#EAAF5A", "#F0E941", "#A4F454", "#38E5E7", "#7F7EDC", "#7F6589"]
    /// The third colour of each page-2 swatch (offline Arc 1.174, 20 Nov 2026: `overlayColors[1]`),
    /// 40° back the other way. Before #632 Cra's page 2 left it out and gave two colours.
    public static let brandThirds = ["#F3E4E7", "#EE9BEA", "#8A73A1", "#F25EC3", "#FF5597", "#FF7567", "#7BE762", "#5CD8B8", "#607D88"]

    /// One page of nine: a catalog group, alone or each colour with two more.
    public struct Page: Equatable, Sendable {
        /// The catalog group: Brand, Drab, Pastel or Greyscale.
        public let group: String
        public let colors: [String]
        /// Each swatch's second and third colours, for a page of analogous sets.
        public let seconds: [String]?
        public let thirds: [String]?

        /// Arc's asset name of swatch `i` (ColorPickerBrand4), which its accessibility label names.
        public func name(_ i: Int) -> String { "ColorPicker\(group)\(i + 1)" }

        /// What each swatch puts on the pad: one colour, or three.
        public var swatches: [[String]] {
            guard let seconds, let thirds else { return colors.map { [$0] } }
            return colors.indices.map { [colors[$0], seconds[$0], thirds[$0]] }
        }

        /// The wheel a swatch from this page puts on the pad (#632).
        public var wheel: SpaceColorWheel.Wheel { seconds == nil ? .complimentary : .analogous }
    }

    /// Arc's five pages (offline Arc 1.171, AX + captures): Brand, Brand sets, Pastel, Drab, Greyscale.
    public static let pages: [Page] = [
        Page(group: "Brand", colors: brand, seconds: nil, thirds: nil),
        Page(group: "Brand", colors: brand, seconds: brandPairs, thirds: brandThirds),
        Page(group: "Pastel", colors: pastel, seconds: nil, thirds: nil),
        Page(group: "Drab", colors: drab, seconds: nil, thirds: nil),
        Page(group: "Greyscale", colors: greyscale, seconds: nil, thirds: nil),
    ]

    /// The page that holds a theme's pad colours, so the editor opens where they are; nil when
    /// they are no preset's.
    public static func page(of key: [String]) -> Int? {
        let k = key.map { $0.uppercased() }
        return pages.firstIndex { $0.swatches.contains(k) }
    }

    /// The wheel for pad colours saved without one (before #632): a preset's own, else Cra's old
    /// one, which put a second and third colour 40° either side like Arc's analogous wheel. One
    /// colour's wheel doesn't matter: + on one colour always goes complimentary.
    public static func wheel(of key: [String]) -> SpaceColorWheel.Wheel {
        page(of: key).map { pages[$0].wheel } ?? (key.count > 1 ? .analogous : .complimentary)
    }

    /// A new space's theme: one of Arc's bright colours, one colour on Auto.
    public static func newSpaceTheme(index: Int = Int.random(in: 0..<9)) -> SpaceTheme {
        SpaceThemeVariants.theme(key: [brand[index % brand.count]], intensity: 0.8, noise: 0, appearance: "auto")
    }
}

/// The editor pad's colour wheel, measured in Arc 1.174 (offline, 20 Nov 2026, #632: swatches, + and −
/// pressed over AX, each set read back from StorableSidebar.json). Arc works in Display P3 HSB: a
/// colour's place is its P3 hue (angle) and saturation (distance from the centre), and every colour on
/// the pad is the first one turned round the wheel at the first one's P3 saturation and brightness, so
/// Arc's state is only the first colour, how many there are and the wheel. Its two wheels (`wheel:
/// analogous | complimentary` in the saved theme) place them:
/// - analogous (a page-2 swatch): +40°, then −40°
/// - complimentary (+ on one colour, from whatever page): two colours 180° apart, three at +150° and
///   +210°, so the second moves when the third comes and moves back when it goes.
/// Rebuilt this way, all 32 of Arc's saved sets came out within 1/255. Before #632 Cra had one rule,
/// ±40° in sRGB HSB, for every swatch.
public enum SpaceColorWheel {
    public typealias Wheel = SpaceThemeWheel

    public static let spread = 40.0

    /// The hue offset of pad colour `i` on the analogous wheel: 0 for the first, then +40°, −40°.
    public static func offset(_ i: Int) -> Double { i == 0 ? 0 : (i == 1 ? spread : -spread) }

    /// The hue offsets of `count` pad colours (at most three) on `wheel`.
    public static func offsets(_ wheel: Wheel, count: Int) -> [Double] {
        let all: [Double]
        switch wheel {
        case .analogous: all = [0, spread, -spread]
        case .complimentary: all = count >= 3 ? [0, 150, 210] : [0, 180]
        }
        return Array(all.prefix(max(0, min(count, 3))))
    }

    /// Whether the pad's − is on with `count` colours on the pad. Arc's takes the last one too, which
    /// leaves the pad empty: Arc's colourless theme (SpaceThemeVariants.colourless, #300).
    public static func canRemove(_ count: Int) -> Bool { count > 0 }

    /// Whether the pad's + is on with `count` colours on the pad.
    public static func canAdd(_ count: Int) -> Bool { count >= 1 && count < 3 }

    /// Whether the pad's + is on for these colours: as `canAdd(_:)`, and off while the first is a
    /// grey (Arc: `isGreyscale`), as Arc's is for its black and white swatches. A grey has no hue
    /// to turn, so a second colour came out white beside black, a gradient no handle could fix (#455).
    public static func canAdd(_ key: [String]) -> Bool {
        canAdd(key.count) && !(key.first.map(isGreyscale) ?? false)
    }

    /// A grey, black or white: no hue (saturation below a byte's rounding).
    public static func isGreyscale(_ hex: String) -> Bool { hsb(hex).saturation < 0.01 }

    /// The pad's brightness for a first colour: 0.95, the pad's bright colours.
    public static let padBrightness = 0.95

    /// The darkest a dragged grey goes: black keeps a hue to show once it is dragged off the centre,
    /// rather than staying black wherever it goes (Cra's choice; Arc's drag from black isn't measured).
    static let darkestDrag = 0.2

    /// How far from the pad's centre the saturation would run out, in points (#754).
    public static let padFade = 178.0

    /// The palest a press goes: Arc's knob dragged past the pad's corner stopped 175 pt out at 0.10,
    /// so a colour keeps its hue at the rim instead of turning grey (#754).
    public static let padPalest = 0.1

    /// The P3 saturation of a press `distance` points from the pad's centre, as Arc's pad gives it
    /// (Arc 1.174.2, offline, 25 Nov 2026, #754): full at the centre, falling evenly towards the rim,
    /// never below `padPalest`. Presses 40, 80, 120 and 160 pt right of the centre read 0.78, 0.54,
    /// 0.32 and 0.12 at an even brightness, and a page-1 swatch at 0.55 sat 79 pt out. Cra had it the
    /// other way round, white at the centre and full at 153 pt, so a drag outward deepened the colour
    /// where Arc's pales it.
    public static func padSaturation(distance: Double) -> Double { max(padPalest, min(1, 1 - distance / padFade)) }

    /// How far from the pad's centre a colour's knob sits: where a press gives its saturation. A grey
    /// has no hue to place it by and sits at the centre, where Arc shows its black swatch.
    public static func padDistance(_ hex: String) -> Double {
        isGreyscale(hex) ? 0 : (1 - min(1, padHSB(hex).saturation)) * padFade
    }

    /// The knob a press on the pad takes (#754): the topmost one under the pointer (`knobs` bottom to
    /// top: centre and radius), else the main one (0), which then comes to the press, as Arc's pad does.
    /// Each knob had a drag of its own over the pad's, and a knob just placed often wouldn't move.
    public static func grabbedKnob(at point: CGPoint, knobs: [(centre: CGPoint, radius: CGFloat)]) -> Int {
        knobs.indices.reversed().first { i in
            hypot(point.x - knobs[i].centre.x, point.y - knobs[i].centre.y) <= knobs[i].radius
        } ?? 0
    }

    /// `count` pad colours on `wheel` from a first colour at P3 `hue`, `saturation` and `brightness`.
    static func set(hue: Double, saturation: Double, brightness: Double, count: Int, wheel: Wheel) -> [String] {
        offsets(wheel, count: max(1, count)).map { padHex(hue: hue + $0, saturation: saturation, brightness: brightness) }
    }

    /// The pad's colours with handle `handle` moved to `hue` (its own, offset included) and
    /// `saturation`: the set turns together and every colour keeps the first one's brightness, as
    /// Arc's pad does (a dark red dragged round Arc's pad stayed at HSB brightness ≈ 0.4 through navy and
    /// teal, the reporter's recording on #455). Before, every drag went to brightness 0.95, so a
    /// dark swatch jumped to a light colour at the first touch. An empty pad starts at `padBrightness`.
    public static func placed(_ key: [String], handle: Int, hue: Double, saturation: Double, wheel: Wheel) -> [String] {
        let brightness = key.first.map { first in
            let b = padHSB(first).brightness
            return isGreyscale(first) ? max(b, darkestDrag) : b
        } ?? padBrightness
        let count = max(1, key.count)
        let turn = offsets(wheel, count: count)[min(max(0, handle), count - 1)]
        return set(hue: hue - turn, saturation: saturation, brightness: brightness, count: count, wheel: wheel)
    }

    /// The pad after +: one colour more on the wheel, from the first one's hue, saturation and
    /// brightness (a dark colour gets dark companions, #455). + on one colour turns to the
    /// complimentary wheel whatever page the colour came from, as Arc's does; + on two keeps the
    /// wheel. Unchanged when + is off.
    public static func adding(to key: [String], wheel: Wheel) -> (key: [String], wheel: Wheel) {
        guard canAdd(key), let first = key.first else { return (key, wheel) }
        let w = key.count == 1 ? Wheel.complimentary : wheel
        let p = padHSB(first)
        return ([first] + set(hue: p.hue, saturation: p.saturation, brightness: p.brightness, count: key.count + 1, wheel: w).dropFirst(), w)
    }

    /// The pad after −: the last colour goes and the rest sit where the wheel puts that many, so a
    /// complimentary three goes back to a pair 180° apart (Arc's state keeps only the first colour,
    /// the count and the wheel).
    public static func removing(from key: [String], wheel: Wheel) -> [String] {
        guard let first = key.first, key.count > 1 else { return [] }
        let p = padHSB(first)
        return [first] + set(hue: p.hue, saturation: p.saturation, brightness: p.brightness, count: key.count - 1, wheel: wheel).dropFirst()
    }

    /// A colour's place on the pad: its Display P3 hue (degrees), saturation and brightness, as Arc's.
    public static func padHSB(_ hex: String) -> (hue: Double, saturation: Double, brightness: Double) {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        return hsb(r: encoded(0.8224621 * r + 0.1775380 * g),
                   g: encoded(0.0331941 * r + 0.9668058 * g),
                   b: encoded(0.0170827 * r + 0.0723974 * g + 0.9105199 * b))
    }

    /// The sRGB colour at a place on the pad (`hue` in degrees, any value, wrapped), clipped to sRGB
    /// (Arc saves extended sRGB, which can run a little past it on saturated greens and blues).
    public static func padHex(hue: Double, saturation: Double, brightness: Double) -> String {
        let p = rgb(hue: hue, saturation: saturation, brightness: brightness)
        let r = linear(p.r), g = linear(p.g), b = linear(p.b)
        return hex(r: encoded(1.2249401 * r - 0.2249404 * g),
                   g: encoded(-0.0420569 * r + 1.0420571 * g),
                   b: encoded(-0.0196376 * r - 0.0786361 * g + 1.0982735 * b))
    }

    private static func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

    private static func encoded(_ v: Double) -> Double {
        let v = max(0, v)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// A colour's sRGB HSB (hue in degrees), which the favourites' outline colours use.
    public static func hsb(_ hex: String) -> (hue: Double, saturation: Double, brightness: Double) {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        return hsb(r: c.r, g: c.g, b: c.b)
    }

    private static func hsb(r: Double, g: Double, b: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// `hue` in degrees (any value, wrapped), saturation and brightness 0...1, in sRGB.
    public static func hex(hue: Double, saturation: Double, brightness: Double) -> String {
        let c = rgb(hue: hue, saturation: saturation, brightness: brightness)
        return hex(r: c.r, g: c.g, b: c.b)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double) {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = max(0, min(1, saturation)), v = max(0, min(1, brightness))
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        switch Int(h) % 6 {
        case 0: return (c + m, x + m, m)
        case 1: return (x + m, c + m, m)
        case 2: return (m, c + m, x + m)
        case 3: return (m, x + m, c + m)
        case 4: return (x + m, m, c + m)
        default: return (c + m, m, x + m)
        }
    }

    private static func hex(r: Double, g: Double, b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
