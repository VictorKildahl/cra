import CoreGraphics

/// Whether a mouse-entered or mouse-moved over a list counts as hover. A list that opens or
/// changes under a pointer that hasn't moved (⌘T's bar ordering in under it, rows arriving, the
/// panel growing to fit them) gets those events from AppKit too, and hover would take the
/// selection from the keyboard's top row (GitHub #382). Points are screen points.
public struct HoverGate: Equatable, Sendable {
    /// Where the pointer rested when the list last changed, until it moves from there.
    private var restingAt: CGPoint?

    public init() {}

    /// The list opened or its rows changed with the pointer at `point`.
    public mutating func listChanged(pointerAt point: CGPoint) {
        restingAt = point
    }

    /// A mouse-entered or mouse-moved with the pointer at `point`: true when it is hover.
    public mutating func isHover(pointerAt point: CGPoint) -> Bool {
        guard let restingAt else { return true }
        if point == restingAt { return false }
        self.restingAt = nil
        return true
    }
}
