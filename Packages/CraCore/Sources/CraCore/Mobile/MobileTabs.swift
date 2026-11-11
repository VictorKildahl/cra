import Foundation

/// A tab in the iPhone app.
public struct MobileTab: Codable, Equatable, Identifiable {
    public var id: UUID
    public var url: String
    public var title: String
    /// When the tab was last on screen. Auto-archive counts from here.
    public var lastActive: Date
    public var isIncognito: Bool

    public init(id: UUID = UUID(), url: String, title: String = "", lastActive: Date, isIncognito: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.lastActive = lastActive
        self.isIncognito = isIncognito
    }

    private enum CodingKeys: String, CodingKey { case id, url, title, lastActive, isIncognito }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        lastActive = try c.decode(Date.self, forKey: .lastActive)
        isIncognito = try c.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
    }

    /// What a card or a row shows: the page's title, or its host until there is one.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        return URL(string: url)?.host ?? url
    }
}

/// How long a tab stays open without being looked at. Arc Search's choices.
public enum MobileArchiveAfter: String, Codable, CaseIterable, Identifiable {
    case twelveHours, oneDay, sevenDays, thirtyDays, never

    public var id: String { rawValue }

    public var interval: TimeInterval? {
        switch self {
        case .twelveHours: return 12 * 3600
        case .oneDay: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .thirtyDays: return 30 * 24 * 3600
        case .never: return nil
        }
    }

    public var label: String {
        switch self {
        case .twelveHours: return "12 Hours"
        case .oneDay: return "1 Day"
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        case .never: return "Never"
        }
    }
}

/// `tabs.json` in the iPhone app's data folder: the open tabs, oldest first, the one on screen,
/// and the tabs that were archived.
public struct MobileTabsDocument: Codable, Equatable {
    public var tabs: [MobileTab]
    public var selected: UUID?
    /// Newest first.
    public var archived: [MobileTab]

    public init(tabs: [MobileTab] = [], selected: UUID? = nil, archived: [MobileTab] = []) {
        self.tabs = tabs
        self.selected = selected
        self.archived = archived
    }

    private enum CodingKeys: String, CodingKey { case tabs, selected, archived }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try c.decodeIfPresent([MobileTab].self, forKey: .tabs) ?? []
        selected = try c.decodeIfPresent(UUID.self, forKey: .selected)
        archived = try c.decodeIfPresent([MobileTab].self, forKey: .archived) ?? []
        if let selected, !tabs.contains(where: { $0.id == selected }) { self.selected = nil }
    }

    public var selectedTab: MobileTab? { tabs.first { $0.id == selected } }

    /// Opens `tab` at the end and shows it.
    public mutating func open(_ tab: MobileTab) {
        tabs.append(tab)
        selected = tab.id
    }

    /// Shows a tab and restarts its archive clock.
    public mutating func select(_ id: UUID, now: Date) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lastActive = now
        selected = id
    }

    /// Closes a tab. When it was the one on screen, the tab after it takes its place, or the one
    /// before when it was last.
    public mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        guard selected == id else { return }
        selected = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    /// Moves the tabs nobody looked at for `after` into the archive, newest first, and returns
    /// how many went. The tab on screen stays, and incognito tabs are never kept in the archive:
    /// they close.
    @discardableResult
    public mutating func archiveStale(after: MobileArchiveAfter, now: Date, archiveLimit: Int = 500) -> Int {
        guard let interval = after.interval else { return 0 }
        let stale = tabs.filter { $0.id != selected && now.timeIntervalSince($0.lastActive) >= interval }
        guard !stale.isEmpty else { return 0 }
        let ids = Set(stale.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        let kept = stale.filter { !$0.isIncognito }.sorted { $0.lastActive > $1.lastActive }
        archived = Array((kept + archived).sorted { $0.lastActive > $1.lastActive }.prefix(archiveLimit))
        return stale.count
    }

    /// Brings an archived tab back as the tab on screen.
    public mutating func restore(_ id: UUID, now: Date) {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return }
        var tab = archived.remove(at: index)
        tab.lastActive = now
        open(tab)
    }
}
