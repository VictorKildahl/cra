import Foundation

/// The head of the menu bar's Tabs menu and its "Open in <space>" row, as Arc 1.172.2 has them
/// (read over Accessibility in Victor's Arc, with and without a Little Arc in front, plus a capture
/// of the open menu, 11 Nov 2026):
///
///     New Tab…  ⌘T
///     Pin Tab  ⌘D
///     🧑‍🌾 Open in Victor  ⌘O     ← only while a Little Arc or Peek is in front
///     New Folder…
///
/// Arc's MainMenu.nib names the row "Open Little Arc or Peek in" (`openTabIn`), which is also its
/// name in Settings ▸ Shortcuts. In the menu it reads "Open in" and the space the Little Arc's own
/// "Open in <space> ⌘O" button names, with that space's icon, and moves the page there straight
/// away (no space picker: that is ⇧⌘O). It is not in the Window menu, and with no Little Arc in
/// front it is gone from the menu altogether.
public enum TabsMenu {
    /// Rows are key-action identifiers.
    public static let head = ["newTab", "pinTab", openIn, "newFolder"]

    /// The "Open in <space>" row's action.
    public static let openIn = "promoteLittleWindow"

    /// Its name in Settings ▸ Shortcuts (Arc: "Open Little Arc or Peek in…").
    public static let openInName = "Open Little Window or Peek in…"

    /// Its title in the menu: the space the page would go to.
    public static func openInTitle(space: String) -> String { "Open in \(space)" }

    /// The row shows only while a Little Window or Peek with a page is in front.
    public static func showsOpenIn(littleWindowWithPage: Bool) -> Bool { littleWindowWithPage }
}
