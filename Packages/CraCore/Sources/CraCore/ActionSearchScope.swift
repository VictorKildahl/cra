import Foundation

/// The command bar scoped to the browser's actions, Arc's `typeTravel` scope (#195): Tab on the
/// empty field puts an "Actions" pill before it (placeholder "Search…") and the rows become
/// commands, each with its shortcut; typing narrows them ("spl": Add Split View, Add Top Split…).
/// Arc 1.171 shows no "Search Actions  Tab" hint for it. Backspace on the empty field and Escape
/// leave it as they leave a site's scope.
public enum ActionSearchScope {
    public static let name = "Actions"

    /// Actions that only open the command bar the scope is already in (New Tab…, Open Command
    /// Bar): Arc lists neither, and run from here they'd just reopen the bar.
    public static let reopensTheBar: Set<String> = ["newTab", "editURL"]

    /// Whether the scope lists the action with this id.
    public static func lists(actionID: String) -> Bool { !reopensTheBar.contains(actionID) }

    public struct Candidate<ID: Hashable>: Equatable {
        public let id: ID
        /// How well the typed text names the action (0 = not at all); ignored with nothing typed.
        public let score: Double
        /// Times the action was run from the bar.
        public let uses: Int

        public init(id: ID, score: Double, uses: Int) {
            self.id = id
            self.score = score
            self.uses = uses
        }
    }

    /// The rows, best first. With nothing typed every action, the most used first and the rest in
    /// the order given (the menus'). Typed, only the actions the text names, the best match first,
    /// use counts nudging it (capped, so a habit can't bury a name typed out in full).
    public static func rank<ID>(_ actions: [Candidate<ID>], typed: Bool) -> [ID] {
        let kept = typed ? actions.filter { $0.score > 0 } : actions
        func value(_ c: Candidate<ID>) -> Double {
            typed ? c.score + Double(min(c.uses, 10)) * 2 : Double(c.uses)
        }
        return kept.enumerated().sorted { a, b in
            let x = value(a.element), y = value(b.element)
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element.id)
    }
}
