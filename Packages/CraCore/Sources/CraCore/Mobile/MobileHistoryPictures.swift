import Foundation

/// The pictures of the pages behind Back and Forward, which the page swipe shows under the
/// page as it is dragged and over the web view until the page it went to has drawn, as Arc
/// Search does. WebKit keeps its own back-forward snapshots privately, so the app keeps its own.
public enum MobileHistoryPictures {
    /// Pictures kept in all, across every tab: each is a screen-sized image held in memory, and
    /// the swipe only ever needs the one or two next to the page on screen.
    public static let kept = 8

    /// A navigation to the same address apart from its fragment: the page doesn't change, so
    /// there is nothing new to keep a picture of. Going from `a#x` to `a`, with no fragment, loads
    /// the page again, as in any browser, so that one isn't a jump.
    public static func isFragmentJump(from current: String?, to target: String) -> Bool {
        guard let current, let hash = target.firstIndex(of: "#") else { return false }
        let base = current.firstIndex(of: "#").map { String(current[..<$0]) } ?? current
        return base == String(target[..<hash])
    }
}

/// Keys in the order they were last used, newest last, at most `limit` of them: what to drop
/// first when there are too many. The pictures behind the page swipe use it, keyed by the
/// history item.
public struct MobileRecentList<Key: Hashable> {
    public let limit: Int
    /// Oldest first.
    public private(set) var keys: [Key] = []

    public init(limit: Int) {
        self.limit = max(0, limit)
    }

    /// Makes `key` the newest, adding it if it is new, and returns the keys dropped to stay
    /// within the limit, oldest first.
    @discardableResult
    public mutating func touch(_ key: Key) -> [Key] {
        keys.removeAll { $0 == key }
        keys.append(key)
        let over = keys.count - limit
        guard over > 0 else { return [] }
        let dropped = Array(keys.prefix(over))
        keys.removeFirst(over)
        return dropped
    }

    public mutating func remove(_ key: Key) {
        keys.removeAll { $0 == key }
    }

    public mutating func removeAll() {
        keys.removeAll()
    }

    public func contains(_ key: Key) -> Bool {
        keys.contains(key)
    }
}
