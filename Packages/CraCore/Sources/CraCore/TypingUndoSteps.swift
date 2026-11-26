import Foundation

/// How a text field that keeps its own undo history (the command bar's, #809) groups what the user types into undo
/// steps, as a Mac text field does: letters typed one after another are one step, deleting is the next, and a paste or
/// a typed letter over a selection is a step of its own. An undo, a redo, a row arrowed to or text the bar put in
/// itself ends the open step. The command bar keeps its own history because its inline completion and its previews
/// replace the field's text, which emptied the field editor's own: ⌘Z did nothing (Arc undoes the typing).
public struct TypingUndoSteps: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case inserting, deleting, replacing }

    private var open: Kind?

    public init() {}

    /// What an edit from `before` to `after` is.
    public static func kind(from before: String, to after: String) -> Kind {
        let b = before.count, a = after.count
        if a > b, after.hasPrefix(before) || after.hasSuffix(before) || Self.isInsertion(of: before, in: after) { return .inserting }
        if a < b, before.hasPrefix(after) || before.hasSuffix(after) || Self.isInsertion(of: after, in: before) { return .deleting }
        return .replacing
    }

    /// Whether this edit starts a new undo step (else it joins the open one). An edit that changes nothing starts none.
    public mutating func startsStep(from before: String, to after: String) -> Bool {
        guard before != after else { return false }
        let kind = Self.kind(from: before, to: after)
        defer { open = kind == .replacing ? nil : kind }
        return kind == .replacing || kind != open
    }

    /// The next edit starts a new step.
    public mutating func close() { open = nil }

    /// `short` is `long` with one run of characters taken out (typed or deleted in the middle).
    static func isInsertion(of short: String, in long: String) -> Bool {
        let s = Array(short), l = Array(long)
        var head = 0
        while head < s.count, s[head] == l[head] { head += 1 }
        var tail = 0
        while tail < s.count - head, s[s.count - 1 - tail] == l[l.count - 1 - tail] { tail += 1 }
        return head + tail == s.count
    }
}
