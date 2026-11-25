import AppKit
import CraCore
import ImageIO
import UniformTypeIdentifiers

/// Share Easel… and the site's Open in Cra for an easel. Arc kept a shared easel on arc.net; Cra's
/// link carries the easel itself after the # of crabrowser.app/easel#…, pictures shrunk to fit
/// (EaselShareLink), so nothing is stored anywhere. The site's page draws it for anyone, and its
/// Open in Cra button (`cra-easel:`) adds a copy here after asking, as a gallery boost does.
@MainActor
enum EaselShare {
    /// Share Easel… on an easel's sidebar row or its Library card: Arc's warning first (unless it was
    /// turned off), then the link, copied.
    static func share(_ id: UUID, over window: NSWindow?, toast: @escaping (String) -> Void) {
        let easel = EaselFiles.current(id)
        guard !easel.items.isEmpty else {
            toast("This Easel Is Empty")
            return
        }
        SidebarMenus.confirmShare(over: window, kind: "Easel") { copyLink(easel, toast: toast) }
    }

    /// The link for `easel`, made off the main thread (its pictures are shrunk), then copied.
    static func copyLink(_ easel: Easel, toast: @escaping (String) -> Void) {
        let folder = EaselFiles.pictures(easel.id)
        Task.detached(priority: .userInitiated) {
            let made = EaselShareLink.link(for: easel) { request in
                encode(folder.appendingPathComponent(request.file), side: request.side)
            }
            await MainActor.run {
                guard let made else {
                    CraLog.note("easel share: too big")
                    toast("This Easel Is Too Big to Share")
                    return
                }
                // The Mac's clipboard (a scenario's copy has one of its own, CRA_TEST_PASTEBOARD).
                let board = AppDelegate.pasteboard
                board.clearContents()
                board.setString(made.link, forType: .string)
                CraLog.note("easel share: \(easel.items.count) items, \(made.link.count) characters, pictures \(made.fit), \(made.link.prefix(29))")
                switch made.fit {
                case .full, .shrunk: toast("Copied Easel URL")
                case .dropped: toast("Copied Easel URL, Without Its Pictures")
                }
            }
        }
    }

    /// A picture at most `side` pixels on its longest side: JPEG, or PNG when it has transparency
    /// (a JPEG would paint that black).
    nonisolated static func encode(_ url: URL, side: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: side,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let alpha = image.alphaInfo
        let opaque = alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
        let out = NSMutableData()
        let type = (opaque ? UTType.jpeg : UTType.png).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, opaque ? [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    // MARK: Open in Cra

    /// Whether `url` is an easel to add. Then it is dealt with here and must not load or open.
    static func isEaselLink(_ url: String) -> Bool { EaselShareLink.isInstallLink(url) }

    /// Asks over `window` (the page's, or the front browser window) whether to add the easel; yes adds
    /// it to the window's space and opens it.
    static func offer(_ url: String, over window: NSWindow?, from page: String) {
        guard let app = NSApp.delegate as? AppDelegate, let window = window ?? app.main?.window else { return }
        guard window.attachedSheet == nil else {
            CraLog.note("easel link from \(page) while a sheet is up, ignored")
            return
        }
        guard let received = EaselShareLink.easel(from: url) else {
            CraLog.note("easel link from \(page) doesn't read")
            AppDialog(title: "This Easel Link Doesn’t Work",
                      message: "It may have been cut short when it was copied.").present(over: window) { _ in }
            return
        }
        let easel = received.easel
        let count = easel.items.count
        CraLog.note("easel link from \(page) offers \(count) items")
        let dialog = AppDialog(title: "Add the “\(easel.title)” Easel?",
                               message: "It opens as a new Easel in this space, with \(count) \(count == 1 ? "item" : "items"). Changes you make stay on this Mac.",
                               actions: [DialogAction("Add Easel"), .cancel])
        dialog.present(over: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let added = add(received) else {
                AppDialog(title: "Cra Couldn’t Add This Easel", message: "Nothing on it could be read.").present(over: window) { _ in }
                return
            }
            let controller = app.mainWindows.first { $0.window === window } ?? app.main
            _ = app.store.createTab(url: added.url, title: added.title, select: true, window: controller?.windowID)
            controller?.showToast("Easel Added")
            CraLog.note("easel added: \(added.items.count) items")
        }
    }

    /// Writes the easel and the pictures that read as pictures; an item whose picture doesn't is
    /// left out (a link card only loses its picture).
    static func add(_ received: EaselShareLink.Received) -> Easel? {
        var easel = received.easel
        let folder = EaselFiles.pictures(easel.id)
        var written = Set<String>()
        for (name, data) in received.pictures where Easel.isPlainFileName(name) && NSImage(data: data) != nil {
            if (try? data.write(to: folder.appendingPathComponent(name))) != nil { written.insert(name) }
        }
        easel.items = easel.items.compactMap { item in
            var item = item
            switch item.kind {
            case .image(let f): return written.contains(f) ? item : nil
            case .capture(let c): return written.contains(c.image) ? item : nil
            case .link(var l):
                if let i = l.image, !written.contains(i) { l.image = nil }
                if let i = l.icon, !written.contains(i) { l.icon = nil }
                item.kind = .link(l)
                return item
            default: return item
            }
        }
        guard !easel.items.isEmpty else {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        EaselFiles.store(easel.id).saveNow(easel)
        EaselFiles.listChanged()
        return easel
    }
}
