import Foundation

/// The space a Little Window's "Open in <space>" (⌘O) names.
///
/// Until a space is picked it is the focused space of the browser window used last, as in Arc's
/// Little Arc (Arc 1.171, #92). A space picked in the Little Window (its command bar's "Switch
/// to <space>") stays, whatever the browser window switches to (#316). The pick is that window's
/// only: the next Little Window follows the window used last again, so a link from another app
/// doesn't open in a space, and with that space's sign-ins, picked earlier. Air Traffic Control
/// sets a Little Window's space for good. A Little Window that names its space when it opens
/// (cra://open, an Air Traffic Control route, #168 #258) keeps that one.
public struct LittleWindowTarget: Equatable, Sendable {
    /// This window's own space: the one it opened on or the one picked in it; nil follows.
    public private(set) var picked: UUID?

    public init(requested: UUID? = nil) { picked = requested }

    /// A space picked in this Little Window: it stays here.
    public mutating func pick(_ id: UUID) { picked = id }

    /// Drops the pick when its space is gone, so the window follows again.
    public mutating func forget(exists: (UUID) -> Bool) {
        if let p = picked, !exists(p) { picked = nil }
    }

    public func space(lastUsed: UUID) -> UUID { picked ?? lastUsed }
}
