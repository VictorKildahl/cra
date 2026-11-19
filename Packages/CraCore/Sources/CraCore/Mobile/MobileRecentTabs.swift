import Foundation

/// Open phone tabs and the Mac's synced tabs, most recently visited first.
public enum MobileRecentTabs {
    public struct Row: Equatable {
        public enum Source: Equatable { case phone(UUID), mac }
        public var title: String
        public var url: String
        public var source: Source
    }

    public static func rows(phone: [MobileTab], selected: UUID?, mac: SidebarDocument?,
                            limit: Int = MobileSearchSheet.visibleRows) -> [Row] {
        let phoneURLs = Set(phone.map(\.url))
        var dated = phone.filter { !$0.isIncognito && $0.id != selected }.map {
            (Row(title: $0.displayTitle, url: $0.url, source: .phone($0.id)), $0.lastActive)
        }
        for item in mac?.items ?? [] {
            guard case .tab(let tab) = item.data, let date = tab.timeLastActiveAt,
                  !tab.url.isEmpty, !phoneURLs.contains(tab.url) else { continue }
            dated.append((Row(title: MobileSpaces.tabTitle(item: item, tab: tab), url: tab.url, source: .mac), date))
        }
        dated.sort { $0.1 > $1.1 }
        var seen = Set<String>()
        return Array(dated.map(\.0).filter { seen.insert($0.url).inserted }.prefix(max(0, limit)))
    }
}
