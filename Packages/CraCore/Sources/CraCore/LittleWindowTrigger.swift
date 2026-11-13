import Foundation

/// Which clicked links open a Little Window because ⌥ and ⌘ were held (Arc's Settings ▸ Links "Open
/// Little Arc when clicking on links with ⌥⌘ held"). Chromium 156 calls a ⌘⌥-click its split view click
/// (CEF_WOD_NEW_SPLIT_VIEW) and reports it a moment after the click, so the keys are the click's own (the
/// page's last mouse-up or Return, as LinkSplitClick reads an Option-click's), not the ones held when
/// Chromium asks: by then they may be up, or be held for the next click.
public enum LittleWindowTrigger {
    private static let relevant: KeyChord.Modifiers = [.shift, .control, .option, .command]

    /// Whether a link to `url` opens in a Little Window: the switch is on (`enabled`, AppSettings'
    /// littleWindowOnOptionCommandClick), and the page's last click had
    /// ⌥⌘ and no ⇧ or ⌃ (`clickModifiers`, AppKit's flags; Caps Lock and Fn don't count) `clickAge`
    /// seconds ago (-1: none in this page). Only what a tab could show: a page's own address, not another
    /// app's (spotify:), a file or Cra's own scheme.
    public static func opens(_ url: String, clickModifiers: UInt, clickAge: TimeInterval, enabled: Bool) -> Bool {
        enabled
            && KeyChord.Modifiers(rawValue: clickModifiers).intersection(relevant) == [.option, .command]
            && clickAge >= 0 && clickAge <= LinkSplitClick.freshness
            && isPage(url)
    }

    private static func isPage(_ url: String) -> Bool {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), let host = u.host, !host.isEmpty else { return false }
        return scheme == "http" || scheme == "https"
    }
}
