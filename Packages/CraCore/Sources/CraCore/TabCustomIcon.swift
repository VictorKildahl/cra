import Foundation

/// A tab's own icon from Change Icon… (GitHub #640). Arc 1.17x opens the same Emoji | Icon picker over a
/// favorite (and a tab's row) as over a space (checked live 20 Nov 2026, offline Arc, a favorite's menu).
/// Cra keeps its picture choice in that picker too. Whatever is picked is drawn into a picture kept in the
/// favicon cache under a key of its own (`TabData.customIconKey`), so every place that shows a tab's icon
/// shows it.
public enum TabCustomIcon {
    /// The cache keys' prefixes: an emoji, a symbol, a picture (and an older custom icon).
    public static let emojiPrefix = "custom-emoji-"
    public static let symbolPrefix = "custom-symbol-"
    public static let imagePrefix = "custom-"

    /// Whether a custom icon turns light on a dark space, as a site's dark glyph does: only a picked
    /// symbol, which is drawn in black. An emoji and a picture keep their own colours.
    public static func followsTheme(key: String) -> Bool { key.hasPrefix(symbolPrefix) }
}
