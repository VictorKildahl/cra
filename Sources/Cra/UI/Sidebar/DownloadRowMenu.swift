import AppKit
import UniformTypeIdentifiers

/// A download row's context menu, in the tray over the Library button and on Library ▸ Downloads
/// alike (#272). Which items show is CraCore's `DownloadMenu`; this performs them.
@MainActor
enum DownloadRowMenu {
    static func fill(_ menu: NSMenu, for row: DownloadHistory.Listed) {
        let history = DownloadHistory.shared
        let path: String
        switch row {
        case .finished(let e): path = e.path
        case .live(let l): path = l.path
        }
        let url = URL(fileURLWithPath: path)
        let kind = kind(of: row.name)
        let sections = DownloadMenu.sections(for: row, fileExists: { FileManager.default.fileExists(atPath: $0) })
        for (i, section) in sections.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            for action in section {
                MenuItems.add(menu, DownloadMenu.title(action, kind: kind, fileName: row.name)) {
                    switch (action, row) {
                    case (.open, _): NSWorkspace.shared.open(url)
                    case (.copy, _):
                        // The file itself, as Finder's Copy puts it: it pastes into Finder, Mail or a chat.
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([url as NSURL])
                    case (.showInFinder, _): NSWorkspace.shared.activateFileViewerSelecting([url])
                    case (.pause, .live(let l)): history.control(l.id, .pause)
                    case (.resume, .live(let l)): history.control(l.id, .resume)
                    case (.cancel, .live(let l)): history.control(l.id, .cancel)
                    case (.hide, _): history.hide(row)
                    case (.moveToTrash, .finished(let e)): history.moveToTrash(e)
                    default: break
                    }
                }
            }
        }
    }

    /// The kind Arc names a file by, from its extension's type.
    static func kind(of name: String) -> DownloadMenu.Kind? {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return nil }
        return DownloadMenu.Kind.first { k in
            let t: UTType = switch k {
            case .image: .image
            case .diskImage: .diskImage
            case .pdf: .pdf
            case .movie: .movie
            case .audio: .audio
            case .zip: .zip
            case .archive: .archive
            }
            return type.conforms(to: t)
        }
    }
}
