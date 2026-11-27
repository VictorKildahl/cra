import Foundation

/// A link dragged onto a space's tab list from a page or another app (Mail, Notes, Safari) opens
/// as a new tab where it is let go, as in Arc (#419). Arc's sidebar drag item is
/// `SidebarDragItem { item(Identifier), external(String) }`: an outside pasteboard item takes the
/// same `on` / `before` / `after` places a dragged row does. Arc opens it in the background, the
/// page you're on stays in front (1.172.1, by hand).
public enum SidebarLinkDrop {
    /// One pasteboard item, as the types a link comes in: `public.url`, the link's text
    /// (`public.url-name`, which Chromium and Safari write), plain text, and a file's own
    /// `public.file-url` (the downloads tray, the Finder).
    public struct Item: Equatable, Sendable {
        public var url: String?
        public var name: String?
        public var text: String?
        public var file: String?

        public init(url: String? = nil, name: String? = nil, text: String? = nil, file: String? = nil) {
            self.url = url
            self.name = name
            self.text = text
            self.file = file
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
    /// else its text. A title comes only with the URL it names, on one line. A file dragged in
    /// itself (out of the downloads tray, or from the Finder) opens too when Chromium shows it in
    /// a tab, as in Arc; its title is left to the page. A page's link to a file never opens.
    public static func tab(from items: [Item]) -> Tab? {
        for item in items {
            if let file = item.file.flatMap(shownFile) { return Tab(url: file, title: "") }
            if let url = item.url.flatMap(Easel.webAddress) {
                let name = (item.name ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                return Tab(url: url, title: name == url ? "" : name)
            }
            if let url = item.text.flatMap(Easel.webAddress) { return Tab(url: url, title: "") }
        }
        return nil
    }

    /// What Chromium shows in a tab rather than downloading: images, PDFs, pages, text, audio
    /// and video. A disk image, an archive or an app would only be downloaded again.
    public static let shownExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico", "avif", "apng",
        "pdf",
        "html", "htm", "xhtml", "shtml", "txt", "text", "json", "xml",
        "mp4", "m4v", "webm", "ogv",
        "mp3", "m4a", "wav", "ogg", "oga", "opus", "flac", "aac",
    ]

    /// `address` when it is a file:// URL naming a file (not a folder) Chromium shows.
    static func shownFile(_ address: String) -> String? {
        guard let url = URL(string: address), url.isFileURL, !address.hasSuffix("/"),
              shownExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return address
    }
}
