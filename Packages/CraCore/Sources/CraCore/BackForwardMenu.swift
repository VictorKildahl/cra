import Foundation

/// The list a right-click on Back or Forward opens, as Arc's BackForwardList does (GitHub #416):
/// the tab's entries on that side of the current one, nearest first, each picked by its entry id.
/// Read from the DevTools Protocol's Page.getNavigationHistory (Chromium's list, or the one
/// WebKitBrowser builds from WKWebView's backForwardList in the same shape), so no CEF patch is
/// needed; the pick goes back through Page.navigateToHistoryEntry.
public struct BackForwardMenu: Equatable, Sendable {
    public enum Direction: Sendable { case back, forward }

    public struct Entry: Codable, Equatable, Sendable {
        public var id: Int
        public var url: String
        public var title: String

        public init(id: Int, url: String, title: String) {
            (self.id, self.url, self.title) = (id, url, title)
        }
    }

    public struct Row: Equatable, Sendable {
        /// Page.navigateToHistoryEntry's `entryId`.
        public var entryID: Int
        public var title: String
        /// For the row's favicon.
        public var url: String

        public init(entryID: Int, title: String, url: String) {
            (self.entryID, self.title, self.url) = (entryID, title, url)
        }
    }

    public var entries: [Entry]
    public var currentIndex: Int

    /// Chromium's own back menu shows 12 entries (BackForwardMenuModel::kMaxHistoryItems). Arc's cap
    /// wasn't measured (a capture had three); a long history otherwise runs off the screen.
    public static let maxRows = 12

    /// Holding Back or Forward down this long opens the list too (Arc's `LongPressButton`, with its
    /// `longPressDuration` and `onLongPress`). Its value isn't in the stripped binary: 0.5 s is SwiftUI's
    /// LongPressGesture default, which ARCUI's button wraps. Not measured on Arc.
    public static let holdDelay: TimeInterval = 0.5

    public init(entries: [Entry], currentIndex: Int) {
        self.entries = entries
        self.currentIndex = currentIndex
    }

    /// Page.getNavigationHistory's result: {"currentIndex": n, "entries": [{"id", "url", "title", …}]}.
    public init?(navigationHistory json: Data) {
        struct Result: Decodable {
            var currentIndex: Int
            var entries: [Entry]
        }
        guard let r = try? JSONDecoder().decode(Result.self, from: json), r.entries.indices.contains(r.currentIndex) else { return nil }
        self.init(entries: r.entries, currentIndex: r.currentIndex)
    }

    /// The rows for `direction`, the entry Back (or Forward) would go to first. A page with no
    /// title shows its address, as Chromium's menu does.
    public func rows(_ direction: Direction) -> [Row] {
        guard entries.indices.contains(currentIndex) else { return [] }
        let side = direction == .back ? Array(entries[..<currentIndex].reversed()) : Array(entries[(currentIndex + 1)...])
        return side.prefix(Self.maxRows).map { e in
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(entryID: e.id, title: title.isEmpty ? e.url : title, url: e.url)
        }
    }
}
