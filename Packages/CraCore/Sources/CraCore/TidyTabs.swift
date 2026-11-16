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
    /// One measured broom sweep; completion uses the store clock.
    public static let minimumRun: TimeInterval = 0.9
    static let maximumTitleLength = 80
    static let maximumNameLength = 32
    /// Conservative byte estimate on macOS 26.0–26.3; schema/output/framing reserve is separate.
    public static let fallbackPromptBytes = 2304
    public static let maximumPromptBytes = 8192
    public static let minimumResponseTokens = 768
    public static let fallbackSchemaTokens = 512
    public static let framingTokens = 256

    /// One loose Today tab as the model sees it: its place in the prompt is its id.
    public struct Tab: Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var host: String
        public init(id: UUID, title: String, host: String) {
            self.id = id
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

    /// Put unseen tabs first so a capped request eventually reaches the whole sidebar. Previously
    /// considered tabs remain optional context, with each part retaining its current Today order.
    public static func requestOrder<ID: Hashable>(looseTabs: [ID], tidied: Set<ID>?) -> [ID] {
        guard let tidied, !tidied.isEmpty else { return looseTabs }
        return looseTabs.filter { !tidied.contains($0) } + looseTabs.filter { tidied.contains($0) }
    }

    /// Arc's request ("Here are my tabs, in the format 'id: title':") and its example tabs, kept in
    /// Arc 1.173 next to `createUnpinnedTabGroups()`. Arc asked for "an array of group assignments";
    /// the answer here is one too, a group name per tab. Measured on the on-device model (16 Nov 2026,
    /// three tab sets with known groups), naming each tab's group in order put no tab in a wrong group,
    /// where listing each group's ids put up to 73 % of the grouped pairs in a wrong group.
    public static let instructions = """
    You sort a person's open browser tabs into groups, like tidying loose papers into labelled folders. \
    Go through the tabs in order and give each one a group name. Tabs about the same topic, task, trip or project \
    get exactly the same group name, even when they come from different websites. A tab that shares nothing with the \
    others gets a short name of its own, like "Calendar". Name groups by topic, not by website.

    For example, if these were my tabs:
    0: nitehawk cinema - Google Search
    1: Amazon: Amazing Deals on Home Goods, Gifts and More
    2: toaster reviews wirecutter
    3: What you should look for in buying a toaster
    4: June 25 | Weekly View
    5: Barbie Movie | Pavilion Theater
    You would answer:
    {"assignments":[{"tab":0,"group":"Movies"},{"tab":1,"group":"Toaster Shopping"},\
    {"tab":2,"group":"Toaster Shopping"},{"tab":3,"group":"Toaster Shopping"},\
    {"tab":4,"group":"Calendar"},{"tab":5,"group":"Movies"}]}
    """

    /// One fitted attempt owns both the text and its immutable prompt-ID → sidebar-ID mapping.
    public struct Request: Equatable, Sendable {
        public let tabs: [Tab]
        /// Today's groups when the run started. They stay out of the prompt (listed, the on-device
        /// model filed almost every tab into them); a name the model gives that matches one joins it.
        public let existingGroups: [ExistingGroup]
        public var tabIDs: [UUID] { tabs.map(\.id) }
        public var prompt: String { TidyTabs.prompt(tabs: tabs) }
        public var promptBytes: Int { TidyTabs.instructions.utf8.count + prompt.utf8.count }
        /// Room for one assignment per tab; a reserve and cap, not a promised tokenization.
        public var responseTokens: Int { max(TidyTabs.minimumResponseTokens, tabs.count * 32) }
        /// Older SDKs cannot count tokens. Treat each prompt byte as one token, plus fixed reserves.
        public var estimatedTokens: Int {
            promptBytes + responseTokens + TidyTabs.fallbackSchemaTokens + TidyTabs.framingTokens
        }
        public func fittingEstimatedContext(_ contextSize: Int) -> Request? {
            var request = self
            while request.estimatedTokens > contextSize {
                guard let reduced = request.reduced() else { return nil }
                request = reduced
            }
            return request
        }
        public func plan(_ proposals: [Proposal]) -> Plan {
            TidyTabs.plan(proposals, tabCount: tabs.count, existingGroups: existingGroups)
        }
        /// Always retain a prefix of unseen-first priority; sorting before shrinking can starve it.
        public func reduced() -> Request? {
            guard tabs.count > 1 else { return nil }
            return Request(tabs: Array(tabs.prefix(tabs.count / 2)), existingGroups: existingGroups)
        }
    }

    /// The tabs that fit the prompt's budget, in the order given (unseen first: `requestOrder`).
    public static func request(tabs: [Tab], existingGroups: [ExistingGroup],
                               maximumBytes: Int = fallbackPromptBytes) -> Request? {
        var fitted = Request(tabs: [], existingGroups: existingGroups)
        for tab in tabs.prefix(maximumTabs) {
            let host = bounded(tab.host, bytes: 160)
            let title = bounded(tab.title, bytes: 160)
            let safe = Tab(id: tab.id, title: clip(title.isEmpty ? host : title, maximumTitleLength), host: host)
            let next = Request(tabs: fitted.tabs + [safe], existingGroups: existingGroups)
            guard next.promptBytes <= maximumBytes else { break }
            fitted = next
        }
        return fitted.tabs.isEmpty ? nil : fitted
    }

    private static func prompt(tabs: [Tab]) -> String {
        (["Here are my tabs, in the format 'id: title':"] + tabs.enumerated().map { "\($0.offset): \($0.element.title)" })
            .joined(separator: "\n")
    }

    /// The model's answer, one group name per tab id, as one-tab proposals: `plan` merges the ones
    /// that share a name (any case) and joins the ones naming a group Today already has.
    public static func proposals(_ assignments: [(tab: Int, group: String)]) -> [Proposal] {
        assignments.map { Proposal(name: $0.group, tabs: [$0.tab]) }
    }

    /// Bound Unicode scalars before grapheme operations, including a single enormous combining run.
    private static func bounded(_ text: String, bytes limit: Int) -> String {
        var result = "", used = 0
        for scalar in text.unicodeScalars {
            let value = scalar.properties.generalCategory == .control ? " " : String(scalar)
            guard used + value.utf8.count <= limit else { break }
            result += value
            used += value.utf8.count
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The model's answer made safe: ids in range and used once (first group wins), names trimmed
    /// and capped, a name that matches an existing group (any case) adds to it, two new groups with
    /// one name merge, and empty groups are dropped. New groups keep the order of their first tab.
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
        newGroups = newGroups.map { Proposal(name: $0.name, tabs: $0.tabs.sorted()) }
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
