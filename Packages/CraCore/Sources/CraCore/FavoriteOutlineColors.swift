import Foundation

extension FavoriteSelectionTint {
    /// The outline's stops for a tile. A logo with no colour of its own (X, GitHub, a missing
    /// icon) gets one ink colour that stands out on the tile, as its glyph does, not a hue.
    public static func colors(iconColors: [String]?, dark: Bool) -> [String] {
        let tints = (iconColors ?? []).filter { HexColor.components($0) != nil }
            .map(SpaceColorWheel.hsb)
            .filter { $0.saturation >= 0.12 && $0.brightness >= 0.15 }
        guard !tints.isEmpty else {
            let ink = dark ? "#F2F2F2" : "#1C1C1C"
            return [ink, ink]
        }
        let colors = tints.map { tint in
            let brightness = dark ? max(0.82, tint.brightness) : min(0.76, max(0.58, tint.brightness))
            return SpaceColorWheel.hex(hue: tint.hue, saturation: max(0.45, tint.saturation), brightness: brightness)
        }
        return colors.count > 1 && colors.first == colors.last ? colors : colors + [colors[0]]
    }
}
