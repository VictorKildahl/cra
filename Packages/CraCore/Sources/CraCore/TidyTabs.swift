import Foundation

/// Arc's Tidy Tabs (Arc Max, `createUnpinnedTabGroups()`), done with the Mac's own Apple Intelligence
/// model instead of Arc's server. The divider's Tidy button sorts a space's loose Today tabs under
/// named group headers (Arc's `SidebarItemData.tabGroup`): the model only proposes names and members;
/// everything here decides what the sidebar does with that answer. Arc 1.171, 4 Nov 2026.
public enum TidyTabs {
    /// Arc 1.171 (canAutoOrganizeTodayTabs, offline copy, 4 Nov 2026): Tidy shows once Today holds six
    /// tabs, grouped ones included (five loose tabs: only Clear; two loose and six grouped: Tidy).
    public static let minimumTabs = 6
    /// A model answer can't hold a sidebar's worth of tabs: the on-device model reads ~4K tokens.
    public static let maximumTabs = 60
    static let maximumTitleLength = 80
    static let maximumNameLength = 32

    /// One loose Today tab as the model sees it: its place in the prompt is its id.
    public struct Tab: Equatable, Sendable {
        public var title: String
        public var host: String
        public init(title: String, host: String) {
            self.title = title
            self.host = host
        }
    }

    /// One group of the model's answer: tab ids from the prompt.
    public struct Proposal: Equatable, Sendable {
        public var name: String
        public var tabs: [Int]
        public init(name: String, tabs: [Int]) {
            self.name = name
            self.tabs = tabs
        }
    }

    /// A destination captured before the model runs; its name may change while its identity stays.
    public struct ExistingGroup: Equatable, Sendable {
        public var id: UUID
        public var name: String
        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// What the sidebar does: new groups, in order, and tabs added to groups Today already has.
    public struct Plan: Equatable, Sendable {
        public var newGroups: [Proposal]
        /// Original group UUID → tab ids joining it.
        public var joins: [UUID: [Int]]
        public init(newGroups: [Proposal], joins: [UUID: [Int]]) {
            self.newGroups = newGroups
            self.joins = joins
        }
        public var isEmpty: Bool { newGroups.isEmpty && joins.isEmpty }
    }

    /// Whether the divider offers Tidy: Today holds enough tabs, one of them loose, and a loose tab
    /// came in since the last run (`tidied`: Today's tabs then). Arc hid the button after a run, even
    /// one that grouped nothing, and a second click on that spot did nothing.
    public static func offers<ID: Hashable>(todayTabs: Int, looseTabs: [ID], tidied: Set<ID>?) -> Bool {
        guard todayTabs >= minimumTabs, !looseTabs.isEmpty else { return false }
        guard let tidied else { return true }
        return looseTabs.contains { !tidied.contains($0) }
    }

    public static let instructions = """
    You sort a person's open browser tabs into groups, like tidying loose papers into labelled folders. \
    Put tabs about the same topic, task or project in one group, even when they come from different websites. \
    Make two to six groups and give each tab to exactly one group if it fits; a group needs at least two tabs. \
    Name each group with the topic, not the website.
    """

    /// The request: Arc's "Here are my tabs, in the format 'id: title':", plus the site, and the
    /// groups Today already has so new tabs can join them (CRA behavior; Arc joining is unverified).
    public static func prompt(tabs: [Tab], existingGroups: [String]) -> String {
        var lines = ["Here are my tabs, as 'id: title (site)':"]
        for (i, t) in tabs.prefix(maximumTabs).enumerated() {
            let title = clip(t.title.isEmpty ? t.host : t.title, maximumTitleLength)
            lines.append(t.host.isEmpty ? "\(i): \(title)" : "\(i): \(title) (\(t.host))")
        }
        if !existingGroups.isEmpty {
            lines.append("")
            lines.append("I already have these groups; reuse a name exactly to add tabs to it: "
                         + existingGroups.map { "\"\($0)\"" }.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// The model's answer made safe: ids in range and used once (first group wins), names trimmed
    /// and capped, a name that matches an existing group (any case) adds to it, two new groups with
    /// one name merge, and a new group needs two tabs. New groups keep the order of their first tab.
    public static func plan(_ proposals: [Proposal], tabCount: Int, existingGroups: [ExistingGroup]) -> Plan {
        var used = Set<Int>()
        var joins: [UUID: [Int]] = [:]
        var newGroups: [Proposal] = []
        let existing = existingGroups.map { key($0.name) }
        for p in proposals {
            let name = clip(p.name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)), maximumNameLength)
            guard !name.isEmpty else { continue }
            var ids: [Int] = []
            for id in p.tabs where id >= 0 && id < min(tabCount, maximumTabs) && !used.contains(id) {
                used.insert(id)
                ids.append(id)
            }
            guard !ids.isEmpty else { continue }
            if let e = existing.firstIndex(of: key(name)) {
                joins[existingGroups[e].id, default: []].append(contentsOf: ids)
            } else if let n = newGroups.firstIndex(where: { key($0.name) == key(name) }) {
                newGroups[n].tabs.append(contentsOf: ids)
            } else {
                newGroups.append(Proposal(name: name, tabs: ids))
            }
        }
        newGroups = newGroups.filter { $0.tabs.count >= 2 }.map { Proposal(name: $0.name, tabs: $0.tabs.sorted()) }
        newGroups.sort { ($0.tabs.first ?? 0) < ($1.tabs.first ?? 0) }
        return Plan(newGroups: newGroups, joins: joins.mapValues { $0.sorted() })
    }

    /// Today's top level after a tidy: loose tabs left over first, in their order (Arc keeps new
    /// tabs above the groups), then the groups Today had, then the new ones. `Item` is either a loose
    /// tab or a group; `isGroup` tells them apart.
    public static func order<ID: Hashable>(today: [ID], isGroup: (ID) -> Bool, grouped: Set<ID>, newGroups: [ID]) -> [ID] {
        let loose = today.filter { !isGroup($0) && !grouped.contains($0) }
        let groups = today.filter(isGroup)
        return loose + groups + newGroups
    }

    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let one = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        return one.count <= n ? one : String(one.prefix(n - 1)) + "…"
    }
}
