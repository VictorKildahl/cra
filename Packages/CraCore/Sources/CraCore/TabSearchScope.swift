import Foundation

/// The command bar scoped to the open tabs of the window's space (#49). Arc 1.171 scopes the bar
/// to a site or to its commands (`ScopedSearchType`: siteSearch, typeTravel) and has no tab scope;
/// this one is offered, entered and left the way Arc's are: "%" shows "Search Tabs  Tab" at the end
/// of the field, Tab puts the pill before it, Backspace on the empty field brings "%" back and
/// Escape returns the bar to how it opened.
public enum TabSearchScope {
    public static let name = "Tabs"
    public static let trigger = "%"
    /// A text score (0…100) below this matched only scattered letters ("gtb" in "GitHub"), which
    /// confuse a list this short more than they help.
    public static let minimumScore = 50.0

    /// Which open tabs ⌘T searches and lists (#307, not in Arc): Arc's bar finds a tab in any space,
    /// and Settings ▸ Advanced "Search only the current space’s tabs" narrows it to
    /// the window's space, as "%" Tab does for one search. `space` gives a tab's space (nil for
    /// one no space holds, which only the whole-profile search keeps).
    public static func commandBarTabs<Tab>(_ tabs: [Tab], space: (Tab) -> UUID?, windowSpace: UUID,
                                           currentSpaceOnly: Bool) -> [Tab] {
        guard currentSpaceOnly else { return tabs }
        return tabs.filter { space($0) == windowSpace }
    }

    /// The typed text offers the scope.
    public static func isOffered(by query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces) == trigger
    }

    public struct Candidate<ID: Hashable>: Equatable {
        public let id: ID
        /// How well the typed text matches the title or address, 0…100; ignored with nothing typed.
        public let score: Double
        /// nil for a tab not opened since launch.
        public let lastActive: Date?

        public init(id: ID, score: Double, lastActive: Date?) {
            self.id = id
            self.score = score
            self.lastActive = lastActive
        }
    }

    /// The rows, best first. With nothing typed every tab, the most recently used first and tabs
    /// not opened since launch last, in the order given (the sidebar's). Typed, only the tabs that
    /// match, the best match first and the more recently used of two equal ones.
    public static func rank<ID>(_ tabs: [Candidate<ID>], typed: Bool) -> [ID] {
        let kept = typed ? tabs.filter { $0.score >= minimumScore } : tabs
        return kept.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if typed, x.score != y.score { return x.score > y.score }
            switch (x.lastActive, y.lastActive) {
            case let (p?, q?) where p != q: return p > q
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element.id)
    }
}
