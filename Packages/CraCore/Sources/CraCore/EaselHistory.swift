import Foundation

/// Undo and Redo on an Easel (Arc's EaselEditManager: "Undo label for moving an object", "…for
/// updating an object", "…for single item deletion"). Each step keeps the whole easel as it was;
/// typing in one text box and a drag are one step each, however many changes they made.
public struct EaselHistory: Sendable {
    public private(set) var undos: [(easel: Easel, name: String)] = []
    public private(set) var redos: [(easel: Easel, name: String)] = []
    /// How many steps are kept.
    public static let limit = 100

    public init() {}

    /// Before a change named `name` (Move, Delete, Paste…): the easel as it is now.
    public mutating func record(_ before: Easel, _ name: String) {
        if let last = undos.last, last.easel == before, last.name == name { return }
        undos.append((before, name))
        if undos.count > Self.limit { undos.removeFirst(undos.count - Self.limit) }
        redos.removeAll()
    }

    public var canUndo: Bool { !undos.isEmpty }
    public var canRedo: Bool { !redos.isEmpty }
    public var undoName: String? { undos.last?.name }
    public var redoName: String? { redos.last?.name }

    /// The easel to go back to, given the one showing now.
    public mutating func undo(_ current: Easel) -> Easel? {
        guard let step = undos.popLast() else { return nil }
        redos.append((current, step.name))
        return step.easel
    }

    public mutating func redo(_ current: Easel) -> Easel? {
        guard let step = redos.popLast() else { return nil }
        undos.append((current, step.name))
        return step.easel
    }
}
