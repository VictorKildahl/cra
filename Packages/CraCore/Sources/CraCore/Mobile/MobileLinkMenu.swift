import Foundation

/// The menu a long press on a link opens. Arc Search's help centre ("How Do I Open Links in New
/// Tabs Using Arc Search?") names two of its rows: "Open in New Tab", and on iOS only "Open in
/// Background Tab", which leaves the page on screen and puts the link's tab in the tab row for
/// later (#572). "Open in Incognito" is Victor's addition, in the word the search field uses for
/// the mode. The other rows and the order are Cra's: Arc Search's full list, its order and its
/// preview were not found (docs/arc-search-reference.md, item 33).
public enum MobileLinkMenu {
    public enum Item: String, CaseIterable {
        case open, openInNewTab, openInBackgroundTab, openInIncognito, copyLink, share

        public var title: String {
            switch self {
            case .open: return "Open"
            case .openInNewTab: return "Open in New Tab"
            case .openInBackgroundTab: return "Open in Background Tab"
            case .openInIncognito: return "Open in Incognito"
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
            case .openInIncognito: return "eyes"
            case .copyLink: return "link"
            case .share: return "square.and.arrow.up"
            }
        }
    }

    /// The rows for a link on a page. On an incognito page every tab a link opens is incognito
    /// already, so "Open in Incognito" is left out; its background tab waits in the private
    /// session (`MobileTabsDocument.addInBackground`).
    public static func items(incognito: Bool) -> [Item] {
        Item.allCases.filter { $0 != .openInIncognito || !incognito }
    }
}

/// Editing the page's address (#572): a tap on the address in the page menu opens the search
/// sheet with it, and what is typed then loads in the same tab. + still opens a new one.
public enum MobileAddressEdit {
    public enum Target: Equatable { case newTab, currentTab }

    /// What the field holds: the page's address, or the tab's while it hasn't loaded, or a
    /// Browse for Me page's question (it has no address of its own).
    public static func text(tabAddress: String, pageAddress: String?) -> String {
        if let query = MobileBrowseForMe.query(fromTabAddress: tabAddress) { return query }
        if let pageAddress, !pageAddress.isEmpty, pageAddress != "about:blank" { return pageAddress }
        return tabAddress == "about:blank" ? "" : tabAddress
    }

    /// Where a search from the sheet goes. A sheet switched to the other side of incognito than
    /// the tab it edits can't load there (a tab's private data store is fixed): a new tab.
    public static func target(editing: Bool, tabIsIncognito: Bool, sheetIsIncognito: Bool) -> Target {
        editing && tabIsIncognito == sheetIsIncognito ? .currentTab : .newTab
    }
}
