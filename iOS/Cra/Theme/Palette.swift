import UIKit

/// The chrome's colours, sampled from Arc Search (docs/ios.md has the frames they came from).
enum Palette {
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// The search sheet's surface.
    static let sheet = dynamic(light: rgb(0xfcfcfc), dark: rgb(0x1c1c1e))
    /// The search field's fill runs from lavender on the left to pink on the right.
    static let fieldLeading = dynamic(light: rgb(0xede9f4), dark: rgb(0x2b2a33))
    static let fieldTrailing = dynamic(light: rgb(0xf5ecf0), dark: rgb(0x332a2f))
    static let fieldBorder = dynamic(light: rgb(0xd9d2dc), dark: rgb(0x3a3840))
    /// The caret and selection.
    static let accent = dynamic(light: rgb(0x4a5fe6), dark: rgb(0x7f8eff))
    static let primaryText = dynamic(light: .black, dark: .white)
    /// The typed part of a completion, and the placeholder.
    static let secondaryText = dynamic(light: rgb(0x6f6e73), dark: rgb(0x9a999f))
    static let placeholder = dynamic(light: rgb(0xa2a0a5), dark: rgb(0x6e6d73))
    static let glyph = dynamic(light: rgb(0x2e2e30), dark: rgb(0xe6e6ea))
    /// The round clear button in the field.
    static let clearFill = dynamic(light: rgb(0xc1b7bc), dark: rgb(0x5a565c))
    /// The incognito mask in the field while incognito is off: barely there.
    static let incognitoOff = dynamic(light: rgb(0xe4dce4), dark: rgb(0x4a464c))
    /// "Browse for Me" on a suggestion row.
    static let chipFill = dynamic(light: rgb(0xf5ebed), dark: rgb(0x332c2f))
    static let chipBorder = dynamic(light: rgb(0xdfd2d6), dark: rgb(0x403a3d))
    /// The pill and the round buttons of the bottom bar, over the bar's blur.
    static let barControlFill = dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.14))
    static let barControlBorder = dynamic(light: UIColor(white: 0, alpha: 0.06), dark: UIColor(white: 1, alpha: 0.08))
}
