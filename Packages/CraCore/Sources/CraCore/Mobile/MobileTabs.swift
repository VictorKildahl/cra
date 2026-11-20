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

/// How long a tab stays open without being looked at: Arc Search's "Archive Inactive Tabs"
/// choices, one day unless changed.
public enum MobileArchiveAfter: String, Codable, CaseIterable, Identifiable {
    case twelveHours, oneDay, threeDays, sevenDays, thirtyDays

    public var id: String { rawValue }

    public var interval: TimeInterval {
        switch self {
        case .twelveHours: return 12 * 3600
        case .oneDay: return 24 * 3600
        case .threeDays: return 3 * 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .thirtyDays: return 30 * 24 * 3600
        }
    }

    /// The choice as the menu words it.
    public var label: String {
        switch self {
        case .twelveHours: return "12 hours"
        case .oneDay: return "1 day"
        case .threeDays: return "3 days"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }

    /// The row's value in Settings: "After 1 day".
    public var settingValue: String { "After \(label)" }
}

/// `tabs.json` in the iPhone app's data folder: the open tabs, oldest first, the one on screen,
/// and the tabs that were archived.
public struct MobileTabsDocument: Codable, Equatable {
    public var tabs: [MobileTab]
    public var selected: UUID?
    /// Newest first.
    public var archived: [MobileTab]
    /// Incognito tabs opened in the background and not looked at yet (#572). Never written down,
    /// like the incognito tabs themselves.
    public private(set) var unseenIncognito: Set<UUID> = []

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

    /// Puts `tab` at the end of the row without showing it (a link saved from another app).
    public mutating func add(_ tab: MobileTab) {
        tabs.append(tab)
    }

    /// "Open in Background Tab" (#572): `tab` at the end of the row, not shown. An incognito one
    /// waits unseen for as long as the private session goes on (`closeIncognitoTabsLeftBehind`).
    public mutating func addInBackground(_ tab: MobileTab) {
        tabs.append(tab)
        if tab.isIncognito { unseenIncognito.insert(tab.id) }
    }

    /// Shows a tab and restarts its archive clock.
    public mutating func select(_ id: UUID, now: Date) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lastActive = now
        selected = id
        unseenIncognito.remove(id)
    }

    /// Shows a tab picked from the tab row (or the search sheet's recent tabs) and moves it to the
    /// row's newest end, as Arc Search's row keeps tabs from the least to the most recently picked,
    /// like the iPhone's app switcher (#647). A swipe along the bar only `select`s, so it walks the
    /// row without shuffling it.
    public mutating func bringToFront(_ id: UUID, now: Date) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.append(tabs.remove(at: index))
        select(id, now: now)
    }

    /// Closes a tab. When it was the one on screen, the tab after it takes its place, or the one
    /// before when it was last.
    public mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        unseenIncognito.remove(id)
        guard selected == id else { return }
        selected = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    /// Moves the tabs nobody looked at for `after` into the archive, newest first, and returns
    /// how many went. The tab on screen stays, and incognito tabs are never kept in the archive:
    /// they close.
    @discardableResult
    public mutating func archiveStale(after: MobileArchiveAfter, now: Date, archiveLimit: Int = 500) -> Int {
        let interval = after.interval
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

extension MobileTabsDocument {
    /// Closes a tab into the archive, as a swipe up on its card does. Incognito tabs just close.
    /// A popup on screen hands the screen back to `opener`, the tab that opened it, when that is
    /// still open, as closing it from the page does (#647).
    public mutating func archive(_ id: UUID, returningTo opener: UUID? = nil) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let wasSelected = selected == id
        close(id)
        if wasSelected, let opener, tabs.contains(where: { $0.id == opener }) { selected = opener }
        guard !tab.isIncognito else { return }
        archived.insert(tab, at: 0)
    }

    public mutating func removeArchived(_ ids: Set<UUID>) {
        archived.removeAll { ids.contains($0.id) }
    }

    /// Incognito tabs live only while they are on screen: Arc Search keeps them out of the tab
    /// row, so one that is left has no way back and closes. One opened in the background and not
    /// looked at yet waits while the private session goes on (an incognito tab is on screen), and
    /// closes with it (#572). Returns the tabs that closed.
    @discardableResult
    public mutating func closeIncognitoTabsLeftBehind(keeping liveOpeners: Set<UUID> = []) -> [UUID] {
        let privateSession = selectedTab?.isIncognito == true
        let left = tabs.filter {
            $0.isIncognito && $0.id != selected && !liveOpeners.contains($0.id)
                && !(privateSession && unseenIncognito.contains($0.id))
        }.map(\.id)
        tabs.removeAll { left.contains($0.id) }
        unseenIncognito.subtract(left)
        return left
    }

    /// The tab row's tabs: every open tab that is not incognito.
    public var rowTabs: [MobileTab] { tabs.filter { !$0.isIncognito } }

    /// What the tab switcher shows: the row, and while a private page is on screen, the private
    /// tabs waiting unseen after it, the only way to reach them (#572).
    public var switcherTabs: [MobileTab] {
        tabs.filter { !$0.isIncognito || ($0.id != selected && unseenIncognito.contains($0.id) && selectedTab?.isIncognito == true) }
    }

    /// Where a flick up on the tab button goes (#537): the row's tab looked at most recently
    /// before the one on screen, so a second flick comes back. Arc Search 1.0 toggled between
    /// the current and the previous page this way. Ties go to the newer tab in the row.
    public var previousTab: MobileTab? {
        rowTabs.filter { $0.id != selected }.reduce(nil) { best, tab in
            guard let best, best.lastActive > tab.lastActive else { return tab }
            return best
        }
    }

    /// Export Data: the open tabs as text, a title and an address each. Incognito tabs stay out.
    public var exportText: String {
        tabs.filter { !$0.isIncognito }.map { "\($0.displayTitle)\n\($0.url)" }.joined(separator: "\n\n")
    }

    /// Clear History: the archive goes, the open tabs stay.
    public mutating func clearArchive() {
        archived.removeAll()
    }
}
