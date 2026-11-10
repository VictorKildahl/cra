import Foundation

/// The space picked in a Little Window this session, which the next Little Window opens on
/// (#316). Kept in memory only: a new launch starts again from the window used last.
public struct LittleWindowSession: Equatable, Sendable {
    public var picked: UUID?

    public init() {}

    /// Drops the pick when its space is gone.
    public mutating func forget(exists: (UUID) -> Bool) {
        if let p = picked, !exists(p) { picked = nil }
    }
}

/// The space a Little Window's "Open in <space>" (⌘O) names.
///
/// Until a space is picked it is the focused space of the browser window used last, as in Arc's
/// Little Arc (Arc 1.171, #92). A space picked in the Little Window (its command bar's "Switch
/// to <space>") stays, whatever the browser window switches to, and the session's next Little
/// Window opens on it (#316). A Little Window that names its space when it opens (cra://open, an
/// Air Traffic Control route, #168 #258) keeps that one.
public struct LittleWindowTarget: Equatable, Sendable {
    /// This window's own space: the one it opened on or the one picked in it; nil follows.
    public private(set) var picked: UUID?

    public init(session: LittleWindowSession = .init(), requested: UUID? = nil) {
        picked = requested ?? session.picked
    }

    /// A space picked in this Little Window: it stays here and carries to the next one.
    public mutating func pick(_ id: UUID, session: inout LittleWindowSession) {
        picked = id
        session.picked = id
    }

    /// Drops the pick when its space is gone, so the window follows again.
    public mutating func forget(exists: (UUID) -> Bool) {
        if let p = picked, !exists(p) { picked = nil }
    }

    public func space(lastUsed: UUID) -> UUID { picked ?? lastUsed }
}
