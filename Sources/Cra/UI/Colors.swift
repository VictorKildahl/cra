import AppKit
import SwiftUI

extension Color {
    init(hex: String) {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1) }
}

extension NSColor {
    convenience init(hex: String) {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    convenience init(_ c: RGB, alpha: CGFloat = 1) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
}
