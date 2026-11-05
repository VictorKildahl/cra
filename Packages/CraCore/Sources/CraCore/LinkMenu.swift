import Foundation

/// The two "open link" items at the top of a page's context menu (GitHub #183).
///
/// Arc's "Open Link in New Tab" switches to the tab it makes, and so does Cra's by default, with
/// "Open Link in Background Tab" below it. With Settings ▸ Tabs ▸ "Open links in new tabs in the
/// background" on, the first item stays behind the page, as in Chrome, and the second one is the
/// explicit way to switch. ⌘-click (background) and ⇧⌘-click (switch) say what they want and don't
/// follow the setting; neither does a target=_blank click, which the page asked for.
public enum LinkMenu {
    public struct Item: Equatable, Sendable {
        public let title: String
        public let opensInBackground: Bool
    }

    public static func items(openLinksInBackground: Bool) -> [Item] {
        openLinksInBackground
            ? [Item(title: "Open Link in New Tab", opensInBackground: true),
               Item(title: "Open Link in Foreground Tab", opensInBackground: false)]
            : [Item(title: "Open Link in New Tab", opensInBackground: false),
               Item(title: "Open Link in Background Tab", opensInBackground: true)]
    }
}
