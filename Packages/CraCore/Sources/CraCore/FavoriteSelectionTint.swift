import Foundation

/// Extends the favicon's spatial color palette around the selected favorite's outline.
public enum FavoriteSelectionTint {
    /// Clockwise stops from the top of premultiplied RGBA pixels. White backgrounds and
    /// transparent margins do not wash out a multicolor logo such as Gmail's.
    public static func sample(rgba: [UInt8], width: Int, height: Int) -> [String] {
        guard width > 0, height > 0, rgba.count / 4 / width == height,
              rgba.count == width * height * 4 else { return [] }
        var pixels: [(x: Double, y: Double, weight: Double, color: String)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let a = Double(rgba[i + 3])
                guard a >= 128 else { continue }
                let r = min(1, Double(rgba[i]) / a)
                let g = min(1, Double(rgba[i + 1]) / a)
                let b = min(1, Double(rgba[i + 2]) / a)
                let brightness = max(r, g, b)
                let saturation = brightness == 0 ? 0 : (brightness - min(r, g, b)) / brightness
                guard saturation > 0.18, brightness > 0.15 else { continue }
                let hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()),
                                 Int((g * 255).rounded()), Int((b * 255).rounded()))
                pixels.append(((Double(x) + 0.5) / Double(width), (Double(y) + 0.5) / Double(height),
                               a / 255 * saturation * brightness, hex))
            }
        }
        guard !pixels.isEmpty else { return [] }
        let stops = (0..<16).map { index -> String in
            let angle = Double(index) * .pi / 8 - .pi / 2
            let x = 0.5 + 0.7 * cos(angle), y = 0.5 + 0.7 * sin(angle)
            func score(_ pixel: (x: Double, y: Double, weight: Double, color: String)) -> Double {
                let distance = pow(pixel.x - x, 2) + pow(pixel.y - y, 2) + 0.02
                return pixel.weight / (distance * distance)
            }
            return pixels.max { score($0) < score($1) }!.color
        }
        return stops + [stops[0]]
    }

    public static func colors(iconColors: [String]?, dark: Bool) -> [String] {
        let fallback = "#579AFF"
        let source = (iconColors ?? []).filter { HexColor.components($0) != nil }
        let colors = (source.isEmpty ? [fallback] : source).map { hex in
            var tint = SpaceColorWheel.hsb(hex)
            if tint.saturation < 0.12 || tint.brightness < 0.15 {
                tint = SpaceColorWheel.hsb(fallback)
            }
            let brightness = dark ? max(0.82, tint.brightness) : min(0.76, max(0.58, tint.brightness))
            return SpaceColorWheel.hex(hue: tint.hue, saturation: max(0.45, tint.saturation), brightness: brightness)
        }
        return colors.count > 1 && colors.first == colors.last ? colors : colors + [colors[0]]
    }
}
