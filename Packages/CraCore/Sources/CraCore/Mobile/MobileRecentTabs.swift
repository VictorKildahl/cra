import Foundation

/// The tabs used most recently, under Arc Search's empty search field without a header (#591):
/// the phone's open tabs and the Mac's synced tabs, newest first.
public enum MobileRecentTabs {
    public struct Row: Equatable {
        public enum Source: Equatable { case phone(UUID), mac }
        public var title: String
        public var url: String
        public var source: Source
    }

    /// Incognito tabs and the tab on screen are left out. The Mac's tabs are those its synced
    /// Spaces list (`MobileSpaces.tabs(in:)`): Arc Sync never brought favorites over (ATH3 in
    /// docs/arc-search-reference.md), so a Mac favorite isn't one. A page listed twice, whatever
    /// its scheme, "www.", trailing slash or fragment (`MobileSuggestions.pageKey`), shows once,
    /// as its phone tab when there is one, so a tap switches to it instead of opening a copy.
    public static func rows(phone: [MobileTab], selected: UUID?, mac: SidebarDocument?,
                            limit: Int = MobileSearchSheet.visibleRows) -> [Row] {
        let shown = phone.filter { !$0.isIncognito && !$0.url.isEmpty }
        let phoneKeys = Set(shown.map { MobileSuggestions.pageKey($0.url) })
        var dated = shown.filter { $0.id != selected }.map {
            (Row(title: $0.displayTitle, url: $0.url, source: .phone($0.id)), $0.lastActive)
        }
        for (item, tab) in mac.map(MobileSpaces.tabs(in:)) ?? [] {
            guard let date = tab.timeLastActiveAt, !tab.url.isEmpty,
                  !phoneKeys.contains(MobileSuggestions.pageKey(tab.url)) else { continue }
            dated.append((Row(title: MobileSpaces.tabTitle(item: item, tab: tab), url: tab.url, source: .mac), date))
        }
        dated.sort { $0.1 > $1.1 }
        var seen = Set<String>()
        return Array(dated.map(\.0).filter { seen.insert(MobileSuggestions.pageKey($0.url)).inserted }.prefix(max(0, limit)))
    }
}
