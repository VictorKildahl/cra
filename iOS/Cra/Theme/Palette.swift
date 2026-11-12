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

    /// The search sheet's surface. Light from TapSmart's March 2025 screenshot: #f3f3f4 under the
    /// field, warming to #f3e6e8 at the keyboard (`sheetBottom`). (The 2024 footage had #fcfcfc.)
    /// Dark is Arc Search's incognito sheet, which is also how the sheet looks in dark mode.
    static let sheet = dynamic(light: rgb(0xf3f3f4), dark: rgb(0x2e2930))
    static let sheetBottom = dynamic(light: rgb(0xf3e6e8), dark: rgb(0x2e2930))
    /// Dark mode's faint blue glow behind the rows (60fps.design's dark clip: #34394a at its middle).
    static let sheetGlow = dynamic(light: .clear, dark: rgb(0x343a4e))
    /// The search field: a flat grey in 2025 (#dbd9da, no edge); the 2024 footage had a
    /// lavender-to-pink gradient with a hairline.
    static let fieldLeading = dynamic(light: rgb(0xdbd9da), dark: rgb(0x433f44))
    static let fieldTrailing = dynamic(light: rgb(0xdbd9da), dark: rgb(0x433f44))
    static let fieldBorder = dynamic(light: rgb(0xdbd9da), dark: rgb(0x504f54))
    /// The caret and selection.
    static let accent = dynamic(light: rgb(0x4a5fe6), dark: rgb(0x7f8eff))
    static let primaryText = dynamic(light: .black, dark: .white)
    /// The typed part of a completion, and the placeholder.
    static let secondaryText = dynamic(light: rgb(0x6f6e73), dark: rgb(0x9a999f))
    static let placeholder = dynamic(light: rgb(0xa2a0a5), dark: rgb(0x97979e))
    static let glyph = dynamic(light: rgb(0x2e2e30), dark: rgb(0xe6e6ea))
    /// The round clear button in the field.
    static let clearFill = dynamic(light: rgb(0xafafaf), dark: rgb(0x5a565c))
    /// Its cross: cut out of the disc in 2025, so the field's grey shows through.
    static let clearCross = dynamic(light: rgb(0xdbd9da), dark: .white)
    /// The incognito mask in the field while incognito is off: barely there.
    static let incognitoOff = dynamic(light: rgb(0xe4dce4), dark: rgb(0x4a464c))
    /// "Browse for Me" on a suggestion row.
    static let chipFill = dynamic(light: rgb(0xdbd8d9), dark: rgb(0x332c2f))
    static let chipBorder = dynamic(light: rgb(0xdbd8d9), dark: rgb(0x403a3d))
    /// The pill and the round buttons of the bottom bar, over the bar's blur.
    static let barControlFill = dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.14))
    /// The same controls floating over the tab switcher's backdrop.
    static let switcherPillFill = dynamic(light: UIColor(red: 71 / 255, green: 58 / 255, blue: 190 / 255, alpha: 0.16), dark: UIColor(white: 1, alpha: 0.16))
    static let switcherButtonFill = dynamic(light: UIColor(red: 71 / 255, green: 58 / 255, blue: 190 / 255, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.10))
    static let barControlBorder = dynamic(light: UIColor(white: 0, alpha: 0.06), dark: UIColor(white: 1, alpha: 0.08))
}
