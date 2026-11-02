import Foundation

/// A tab's toolbar colour (Arc 1.171, measured for GitHub #84): the colour its page reported,
/// else the one the tab showed last (TabData.themeColor), so a slept or restored tab keeps its
/// bar while the page loads again. Nil means Arc's white bar: a page Arc has never shown gets
/// it, over a black canvas in dark mode too, until the page finishes loading.
public enum ToolbarColor {
    /// "#RRGGBB", or nil for white. An empty, "none" or malformed value counts as unknown.
    public static func hex(reported: String?, remembered: String?) -> String? {
        [reported, remembered].lazy.compactMap { $0 }.first { HexColor.components($0) != nil }
    }
}
