import AppKit
import UniformTypeIdentifiers

/// Every space's favorites, pinned tabs and folders as a Netscape bookmark file: the
/// format Chrome, Safari, Firefox and Cra's Safari import all read,
/// and a plain nested list when opened in a browser. A space is a folder, its favorites
/// a "Favorites" folder inside it; split views give their panes to the folder they are in.
/// Today tabs are left out, as Arc archives them.
enum SidebarExport {
    @MainActor
    static func bookmarksHTML(_ store: SidebarStore, date: Date = Date()) -> String {
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- Spaces and pinned tabs exported from Cra on \(date.formatted(date: .long, time: .shortened)). -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Cra Spaces</TITLE>
        <H1>Cra Spaces</H1>
        <DL><p>

        """
        func line(_ depth: Int, _ s: String) { out += String(repeating: "    ", count: depth) + s + "\n" }
        func folder(_ name: String, created: Date, depth: Int, _ body: () -> Void) {
            line(depth, "<DT><H3 ADD_DATE=\"\(stamp(created))\">\(escape(name))</H3>")
            line(depth, "<DL><p>")
            body()
            line(depth, "</DL><p>")
        }
        func items(under id: UUID, depth: Int) {
            for item in store.children(of: id) {
                if let tab = item.tab {
                    guard !item.isEmptyTab else { continue }
                    let url = tab.savedURL.isEmpty ? tab.url : tab.savedURL
                    line(depth, "<DT><A HREF=\"\(escape(url))\" ADD_DATE=\"\(stamp(item.createdAt))\">\(escape(item.displayTitle))</A>")
                } else if item.isSplit {
                    items(under: item.id, depth: depth)
                } else if item.isFolder {
                    folder(item.displayTitle, created: item.createdAt, depth: depth) { items(under: item.id, depth: depth + 1) }
                }
            }
        }
        for space in store.orderedSpaces {
            let name = space.emoji.isEmpty ? space.title : "\(space.emoji) \(space.title)"
            folder(name, created: space.createdAt, depth: 1) {
                if !store.tabs(under: space.favoritesContainerID).isEmpty {
                    folder("Favorites", created: space.createdAt, depth: 2) { items(under: space.favoritesContainerID, depth: 3) }
                }
                items(under: space.pinnedContainerID, depth: 2)
            }
        }
        out += "</DL><p>\n"
        return out
    }

    /// Asks where to save, then writes the file. `window` hosts the panel as a sheet.
    @MainActor
    static func run(_ store: SidebarStore, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.title = "Export Spaces"
        panel.message = "Spaces, favorites and pinned tabs, as a bookmarks file any browser can import."
        panel.nameFieldStringValue = "Cra Spaces \(Date().formatted(.iso8601.year().month().day())).html"
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        let html = bookmarksHTML(store)
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: done) } else { done(panel.runModal()) }
    }

    private static func stamp(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
