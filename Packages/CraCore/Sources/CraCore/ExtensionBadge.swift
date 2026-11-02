import CoreGraphics
import Foundation

/// An extension's toolbar badge (chrome.action.setBadgeText) as Arc draws it: Chromium's
/// IconWithBadgeImageSource at half size, its 28 pt icon area centred on the 16 pt icon. Arc 1.171,
/// measured 2 Nov 2026 for #106: "42" is an 8 × 7 pt badge 1 pt in from the icon's bottom right,
/// with a 0.5 pt ring cut out of the icon around it.
public struct ExtensionBadge: Equatable, Sendable {
    public struct RGBA: Equatable, Sendable {
        public var r, g, b, a: Double
        public init(r: Double, g: Double, b: Double, a: Double = 1) { (self.r, self.g, self.b, self.a) = (r, g, b, a) }

        /// "#RRGGBBAA" (the action's colours) or "#RRGGBB".
        public init?(hex: String) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
            let rgba = s.count == 8 ? v : v << 8 | 0xff
            self.init(r: Double(rgba >> 24 & 0xff) / 255, g: Double(rgba >> 16 & 0xff) / 255,
                      b: Double(rgba >> 8 & 0xff) / 255, a: Double(rgba & 0xff) / 255)
        }

        /// WCAG relative luminance (Chromium's color_utils::GetRelativeLuminance).
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
    }

    /// Chromium measures and lays the badge out at full size, in this font (CONTEXT_BADGE: 9 pt bold).
    public static let measuringFontSize = 9.0
    /// What Arc draws: everything at half size.
    public static let scale = 0.5
    public static var fontSize: Double { measuringFontSize * scale }

    public let text: String
    public let background: RGBA
    public let textColor: RGBA
    /// In icon points, origin top left.
    public let frame: CGRect
    /// Cleared out of the icon under the badge.
    public let cutout: CGRect
    public let cornerRadius: Double
    public let cutoutCornerRadius: Double

    /// Nil without text. `textWidth` is the text's width in the measuring font. `defaultBackground`
    /// applies when the extension set no colour (or a transparent one).
    public init?(state: ExtensionActionState, iconSize: Double = 16, defaultBackground: RGBA,
                 textWidth: (String) -> Double) {
        guard !state.badgeText.isEmpty else { return nil }
        text = state.badgeText
        // Chromium makes the background opaque so the text reads (crbug.com/40472744).
        if let c = RGBA(hex: state.badgeColor), c.a > 0 {
            background = RGBA(r: c.r, g: c.g, b: c.b)
        } else {
            background = defaultBackground
        }
        if let c = RGBA(hex: state.badgeTextColor), c.a > 0 {
            textColor = c
        } else {
            // color_utils::GetColorWithMaxContrast: white on dark, Google Grey 900 on light.
            textColor = background.luminance < 0.211692036 ? RGBA(r: 1, g: 1, b: 1) : RGBA(hex: "#202124")!
        }
        // IconWithBadgeImageSource::SetBadge, in Chromium's units.
        let area = 28, height = 14
        var width = Int(min(23, textWidth(text).rounded(.up))) + 2 * 2
        if width % 2 != area % 2 { width += 1 }
        width = max(height, width)
        let x = width >= 20 ? (area - width) / 2 : area - width
        let full = CGRect(x: x, y: area - height, width: width, height: height)
        let s = Self.scale, origin = (iconSize - Double(area) * s) / 2
        func place(_ r: CGRect) -> CGRect {
            CGRect(x: origin + r.minX * s, y: origin + r.minY * s, width: r.width * s, height: r.height * s)
        }
        frame = place(full)
        cutout = place(full.insetBy(dx: -1, dy: -1))
        cornerRadius = 4 * s
        cutoutCornerRadius = 3 * s
    }
}
