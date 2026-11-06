import Foundation

/// Which Peek the page behind is veiled for (faded, and smaller unless edge to edge:
/// `PeekLayout.backdrop`). Each call says whether the window has to change the page.
///
/// A Peek veils the page 30 ms into its open, fades it back as it starts closing, and ends when
/// its window goes. A Peek that ended before its open veiled the page (Expand, Add To Split or a
/// close in those 30 ms) never veils it, and a Peek ending after its close already fades the page
/// back leaves that fade running.
public struct PeekVeil: Sendable, Equatable {
    /// The Peek the page is veiled for, nil when it is (or is on its way back to) itself.
    public private(set) var owner: UUID?
    private var ended: Set<UUID> = []

    public init() {}

    public var isOn: Bool { owner != nil }

    /// `peek` veils the page: true when the window fades it (animated).
    public mutating func show(for peek: UUID) -> Bool {
        guard !ended.contains(peek), owner != peek else { return false }
        owner = peek
        return true
    }

    /// `peek` starts closing: true when the window fades the page back (animated).
    public mutating func hide(for peek: UUID) -> Bool {
        guard owner == peek else { return false }
        owner = nil
        return true
    }

    /// `peek`'s window is gone: true when the page is still veiled for it and snaps back.
    public mutating func end(for peek: UUID) -> Bool {
        ended.insert(peek)
        return hide(for: peek)
    }
}
