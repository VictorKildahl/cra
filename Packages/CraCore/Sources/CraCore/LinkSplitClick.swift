import Foundation

/// Option-click on a link opens it in Split View, beside the page it was clicked in, as in Arc
/// ("Option + Click on any link or tab will open it in Split View", Arc's release notes of
/// 16 Dec 2021; GitHub #298). ⌘⌥-click does too: Chromium 156 calls that click split view
/// (`kNavigationPolicySplitView`, CEF_WOD_NEW_SPLIT_VIEW). ⇧ keeps its own meaning (Peek,
/// Chrome's new window) and ⌃-click is a right-click on a Mac.
///
/// Chromium itself treats an Option-click as "download the link" (Blink's
/// `NavigationPolicyFromEventModifiers`), so a CEF page reports it as a download it wants to
/// start, a moment after the click. That download opens the split instead when the page's last
/// click (or Return on a focused link) had Option alone and was just now.
public enum LinkSplitClick {
    /// How long after the click its download may ask. A test copy of Cra behind other windows
    /// asked half a second after the mouse-up (9 Nov 2026); two seconds leave room for a busy
    /// main thread, and the click counts for one download only.
    public static let freshness: TimeInterval = 2

    private static let relevant: KeyChord.Modifiers = [.shift, .control, .option, .command]

    /// Whether a link to `url` clicked with these modifiers (AppKit's flags) opens in Split View:
    /// ⌥ alone or ⌘⌥. Caps Lock, Fn and the numeric pad flag don't count.
    public static func opensSplit(_ url: String, modifiers: UInt) -> Bool {
        let keys = KeyChord.Modifiers(rawValue: modifiers).intersection(relevant)
        return (keys == .option || keys == [.option, .command]) && panes(url)
    }

    /// Whether a download a CEF page asks for is an Option-click on a link to `url`, to open in
    /// Split View instead: the page's last click had ⌥ alone (`clickModifiers`, AppKit's flags)
    /// `clickAge` seconds ago. A page's own blob: or data: file stays a download.
    public static func opensSplit(downloadOf url: String, clickModifiers: UInt, clickAge: TimeInterval) -> Bool {
        KeyChord.Modifiers(rawValue: clickModifiers).intersection(relevant) == .option
            && clickAge >= 0 && clickAge <= freshness && panes(url)
    }

    /// Web addresses only: a page never opens a local file (Chromium's rule), and an app's
    /// address (spotify:) asks "Open <app>?" as a plain click does.
    private static func panes(_ url: String) -> Bool {
        guard let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
