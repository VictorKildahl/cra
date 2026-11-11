import Foundation

/// View ▸ Developer ▸ View Source (⌥⌘U): the page's source in a new tab in front, at
/// `view-source:<address>`, as in Arc and Chrome (GitHub #348).
public enum ViewSource {
    /// Schemes whose pages have a source to show. An Easel (easel:), a new tab (about:blank) or a
    /// page that already is a source has none, and the command does nothing there, as in Arc.
    static let schemes: Set<String> = ["http", "https", "file"]

    /// The view-source: address for the page at `url`, or nil when it has no source to show.
    public static func address(for url: String) -> String? {
        guard let colon = url.firstIndex(of: ":"), schemes.contains(url[..<colon].lowercased()) else { return nil }
        return "view-source:" + url
    }
}
