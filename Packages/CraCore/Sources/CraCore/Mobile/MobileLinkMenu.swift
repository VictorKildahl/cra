import Foundation

/// The menu a long press on a link opens. Arc Search's help centre ("How Do I Open Links in New
/// Tabs Using Arc Search?") names two of its rows: "Open in New Tab", and on iOS only "Open in
/// Background Tab", which leaves the page on screen and puts the link's tab in the tab row for
/// later (#572). The other rows are Cra's; Arc Search's full list and its preview were not seen.
public enum MobileLinkMenu {
    public enum Item: String, CaseIterable {
        case open, openInNewTab, openInBackgroundTab, copyLink, share

        public var title: String {
            switch self {
            case .open: return "Open"
            case .openInNewTab: return "Open in New Tab"
            case .openInBackgroundTab: return "Open in Background Tab"
            case .copyLink: return "Copy Link"
            case .share: return "Share..."
            }
        }

        /// The SF Symbol beside the title.
        public var symbol: String {
            switch self {
            case .open: return "arrow.up.right"
            case .openInNewTab: return "plus.square.on.square"
            case .openInBackgroundTab: return "square.on.square.dashed"
            case .copyLink: return "link"
            case .share: return "square.and.arrow.up"
            }
        }
    }

    /// The rows for a link on a page. A link on an incognito page opens incognito, and an incognito
    /// tab lives only while it is on screen (`MobileTabsDocument.closeIncognitoTabsLeftBehind`), so
    /// one opened in the background would close before it could be reached: incognito leaves the
    /// row out.
    public static func items(incognito: Bool) -> [Item] {
        Item.allCases.filter { $0 != .openInBackgroundTab || !incognito }
    }
}
