import Foundation

/// A link dragged onto a space's tab list from a page or another app (Mail, Notes, Safari) opens
/// as a new tab where it is let go, as in Arc (#419). Arc's sidebar drag item is
/// `SidebarDragItem { item(Identifier), external(String) }`: an outside pasteboard item takes the
/// same `on` / `before` / `after` places a dragged row does. Arc opens it in the background, the
/// page you're on stays in front (1.172.1, by hand).
public enum SidebarLinkDrop {
    /// One pasteboard item, as the types a link comes in: `public.url`, the link's text
    /// (`public.url-name`, which Chromium and Safari write) and plain text.
    public struct Item: Equatable, Sendable {
        public var url: String?
        public var name: String?
        public var text: String?

        public init(url: String? = nil, name: String? = nil, text: String? = nil) {
            self.url = url
            self.name = name
            self.text = text
        }
    }

    public struct Tab: Equatable, Sendable {
        public var url: String
        /// "" leaves the title to the page.
        public var title: String

        public init(url: String, title: String) {
            self.url = url
            self.title = title
        }
    }

    /// The first item that holds a web page's address (http or https) becomes the tab: its URL,
    /// else its text. A title comes only with the URL it names, on one line.
    public static func tab(from items: [Item]) -> Tab? {
        for item in items {
            if let url = item.url.flatMap(Easel.webAddress) {
                let name = (item.name ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                return Tab(url: url, title: name == url ? "" : name)
            }
            if let url = item.text.flatMap(Easel.webAddress) { return Tab(url: url, title: "") }
        }
        return nil
    }
}
