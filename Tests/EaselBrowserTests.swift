import AppKit
import CraCEF

@main
enum EaselBrowserTests {
    @MainActor
    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let document = Easel(title: "Saved Easel", items: [.init(kind: .rectangle, frame: .init(x: 100, y: 180, width: 120, height: 80))])
        EaselFiles.store(document.id).saveNow(document)
        let peek = EaselColorObserver()
        let browser = EaselBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: document.url, delegate: peek)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let canvas = browser.containerView.subviews.first as! EaselCanvasView
        precondition(canvas.document == document, "opening a saved Easel keeps its contents")
        precondition(peek.background == "clear" && peek.theme == "#1E1E1E", "a newly opened Easel reports its colours")
        browser.usePeekLook()
        precondition(canvas.layer!.backgroundColor!.alpha == 1, "Peek keeps its opaque dark canvas")
        let page = EaselColorObserver()
        browser.usePageLook()
        browser.delegate = page
        browser.probeBackgroundColor()
        precondition(page.background == "clear", "the promoted Easel lets the space gradient through its page card")
        precondition(page.theme == "#1E1E1E", "the promoted Easel reports its toolbar colour to the new owner")
        precondition(canvas.layer!.backgroundColor!.alpha == 0.5, "the expanded canvas veils the space gradient")
        precondition(canvas.document == document, "promotion preserves the saved drawing")
        browser.usePeekLook()
        precondition(canvas.layer!.backgroundColor!.alpha == 1, "returning to Peek restores its opaque background")
        browser.close()

        // The capture menu's New Easel and Send To…: a capture that knows its page becomes a card
        // that can go live, as big as it was on the page (at most 640 pt); without it, a picture.
        let shot = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = shot.representation(using: .png, properties: [:])!
        let source = Easel.Capture(url: "https://example.com/", title: "Example", image: "", viewport: .init(1200, 800),
                                   scroll: .init(0, 100), area: .init(x: 10, y: 20, width: 400, height: 200))
        let made = EaselFiles.create(withPicture: png, source: source)!
        guard case .capture(let c) = made.items.first?.kind else { fatalError("a capture with its page is a capture card") }
        precondition(c.url == "https://example.com/" && c.canGoLive && !c.image.isEmpty && made.items[0].frame.width == 400,
                     "it keeps its page and is as big as the captured area")
        precondition(FileManager.default.fileExists(atPath: EaselFiles.pictures(made.id).appendingPathComponent(c.image).path), "its picture is saved")
        precondition(EaselFiles.add(picture: png, to: made.id), "Send To… adds to an easel")
        let sent = EaselFiles.load(made.id)
        guard sent.items.count == 2, case .image = sent.items[1].kind else { fatalError("without its page a capture is a plain picture") }
        precondition(sent.items[1].frame.y == made.items[0].frame.y + made.items[0].frame.height + 40 && sent.items[1].frame.width == 640,
                     "it lands under what the easel holds, at most 640 pt across")
        print("Easel browser: saved drawing, Peek and expanded page colours passed")

        await syncedEasels()
        print("Easel browser: synced easels on open canvases, their tabs and Library passed")

        await easelOpenTwice()
        print("Easel browser: an easel open on two canvases takes sync's change on both passed")

        deleteRemovesASaveThatLandsAfterIt()
        deleteLeavesAnEaselImportBroughtBack()
        print("Easel browser: the removal a second after Delete passed")
    }

    /// Deletes a new easel, runs `between`, then the removal that follows a second later; returns the easel's file.
    @MainActor
    static func deleteThenRemoveLater(_ title: String, between: (UUID) -> Void) -> URL {
        let given = EaselFiles.afterDelete
        defer { EaselFiles.afterDelete = given }
        var later: [@MainActor @Sendable () -> Void] = []
        EaselFiles.afterDelete = { later.append($0) }
        let easel = Easel(title: title)
        EaselFiles.store(easel.id).saveNow(easel)
        EaselFiles.delete(easel.id)
        between(easel.id)
        for work in later { work() }
        return EaselFiles.store(easel.id).url
    }

    /// An edit saved just after Delete (JSONStore.save waits 0.4 s): the removal a second later takes it away.
    @MainActor
    static func deleteRemovesASaveThatLandsAfterIt() {
        let file = deleteThenRemoveLater("Saved After Delete") { EaselFiles.store($0).saveNow(Easel(id: $0, title: "A Late Save")) }
        precondition(!FileManager.default.fileExists(atPath: file.path), "the removal after a delete takes the save that landed after it")
    }

    /// Deleted here, then Import brought it back within the second: the removal after the delete took Import's copy away
    /// (Greptile, PR #894).
    @MainActor
    static func deleteLeavesAnEaselImportBroughtBack() {
        let file = deleteThenRemoveLater("Brought Back by Import") { id in
            EaselFiles.store(id).saveNow(Easel(id: id, title: "From Import"))
            EaselFiles.synced()
        }
        precondition(FileManager.default.fileExists(atPath: file.path), "the removal after a delete leaves the easel Import brought back")
    }

    /// One easel open on two canvases (a tab and a Peek): sync's change, its deletion and Import's
    /// copy reach both, so neither writes an old copy back.
    @MainActor
    static func easelOpenTwice() async {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let shape = Easel.Item(kind: .ellipse, frame: .init(x: 300, y: 180, width: 80, height: 80))

        // Drawn on in the tab before the other Mac renamed it: each canvas merges from what it shows,
        // so the tab keeps its shape and takes the new title, and its close writes both.
        let easel = Easel(title: "Open Twice")
        EaselFiles.store(easel.id).saveNow(easel)
        let tab = EaselBrowser(frame: frame, url: easel.url, delegate: nil)
        let peek = EaselBrowser(frame: frame, url: easel.url, delegate: nil)
        tab.canvasView.sheetView.insert(shape)
        let renamed: (Easel) -> Easel? = { here in
            var merged = here
            merged.title = "Renamed on the Other Mac"
            return merged
        }
        var both = easel
        both.title = "Renamed on the Other Mac"
        both.items = [shape]
        precondition(EaselFiles.changeOpen(easel.id, renamed), "an easel open twice changes on its canvases")
        precondition(tab.canvasView.document.items == [shape], "the canvas drawn on before the sync keeps its shape")
        precondition(tab.canvasView.document.title == "Renamed on the Other Mac", "the canvas drawn on before the sync takes the other Mac's change")
        precondition(peek.canvasView.document.title == "Renamed on the Other Mac", "the other canvas takes the other Mac's change")
        peek.close()
        tab.close()
        precondition(EaselFiles.load(easel.id) == both, "the canvas drawn on before the sync writes its shape and the merge on close")

        // The canvas opened last closes first: the other one still takes sync's change.
        let second = Easel(title: "Peek Closes First")
        EaselFiles.store(second.id).saveNow(second)
        let kept = EaselBrowser(frame: frame, url: second.url, delegate: nil)
        let closing = EaselBrowser(frame: frame, url: second.url, delegate: nil)
        closing.close()
        var synced = second
        synced.title = "Synced After Close"
        precondition(EaselFiles.changeOpen(second.id) { _ in synced }, "an easel still open on a canvas changes on it")
        precondition(kept.canvasView.document == synced, "the canvas left open shows the merged easel")
        kept.canvasView.sheetView.insert(shape)
        precondition(EaselFiles.load(second.id).title == "Synced After Close", "an edit after the sync saves on top of the merge")
        kept.close()

        // Deleted on the other Mac while open twice: neither canvas writes it back.
        let gone = Easel(title: "Deleted While Open Twice")
        EaselFiles.store(gone.id).saveNow(gone)
        let goneTab = EaselBrowser(frame: frame, url: gone.url, delegate: nil)
        let gonePeek = EaselBrowser(frame: frame, url: gone.url, delegate: nil)
        goneTab.canvasView.sheetView.insert(shape)
        gonePeek.canvasView.sheetView.insert(shape)
        precondition(EaselFiles.changeOpen(gone.id) { _ in nil }, "an easel open twice and deleted on the other Mac is handled on its canvases")
        try? FileManager.default.removeItem(at: EaselFiles.store(gone.id).url)
        goneTab.close()
        precondition(!FileManager.default.fileExists(atPath: EaselFiles.store(gone.id).url.path), "the first canvas of a deleted easel writes nothing on close")
        gonePeek.close()
        precondition(!FileManager.default.fileExists(atPath: EaselFiles.store(gone.id).url.path), "the last canvas of a deleted easel writes nothing on close")

        // Deleted here, then Import brings it back: both canvases still loaded show Import's copy.
        let back = Easel(title: "Before Delete, Twice")
        EaselFiles.store(back.id).saveNow(back)
        let first = EaselBrowser(frame: frame, url: back.url, delegate: nil)
        let last = EaselBrowser(frame: frame, url: back.url, delegate: nil)
        EaselFiles.delete(back.id)
        let imported = Easel(id: back.id, title: "From Import, Twice")
        EaselFiles.store(back.id).saveNow(imported)
        EaselFiles.synced()
        precondition(first.canvasView.document == imported, "the canvas opened first shows the easel Import brought back")
        precondition(last.canvasView.document == imported, "the canvas opened last shows the easel Import brought back")
        first.close()
        last.close()
    }

    /// What sync does to easels here: an open canvas takes the merged easel, a deleted one's tabs close.
    @MainActor
    static func syncedEasels() async {
        let open = Easel(title: "Before Sync", items: [.init(kind: .rectangle, frame: .init(x: 100, y: 180, width: 120, height: 80))])
        EaselFiles.store(open.id).saveNow(open)
        let browser = EaselBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: open.url, delegate: nil)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let canvas = browser.canvasView
        var reported: String?
        canvas.onTitle = { reported = $0 }
        canvas.sheetView.insert(.init(kind: .ellipse, frame: .init(x: 300, y: 180, width: 80, height: 80)))
        var synced = open
        synced.title = "From the Other Mac"
        synced.items.append(.init(kind: .rectangle, frame: .init(x: 400, y: 400, width: 60, height: 60)))

        canvas.replace(with: synced)
        precondition(canvas.sheetView.document == synced, "a synced easel shows on its canvas")
        precondition(EaselFiles.load(open.id) == synced, "a synced easel on a canvas is saved")
        precondition(reported == "From the Other Mac", "a synced easel's title goes to its tab")
        precondition(!canvas.sheetView.history.canUndo, "⌘Z can't take back a synced change")

        var called = false
        precondition(!EaselFiles.changeOpen(UUID()) { _ in called = true; return nil }, "an easel no tab shows is not on a canvas")
        precondition(!called, "an easel no tab shows is left to the sync service")

        var merged = synced
        merged.title = "Merged"
        var given: Easel?
        precondition(EaselFiles.changeOpen(open.id) { given = $0; return merged }, "an easel a tab shows changes on its canvas")
        precondition(given == synced, "the merge starts from what the canvas shows")
        precondition(canvas.sheetView.document == merged, "the merged easel shows on its canvas")

        precondition(EaselFiles.changeOpen(open.id) { _ in nil }, "an easel deleted on the other Mac is handled on its canvas")
        precondition(EaselFiles.deleted.contains(open.id), "an easel deleted on the other Mac is deleted here")
        // Its canvas saves nothing now (a Favorite's or a Peek's stays loaded): Import's copy goes to the file.
        precondition(!EaselFiles.changeOpen(open.id) { $0 }, "an easel deleted here is left to the sync service, though a canvas shows it")
        browser.close()

        // Library ▸ Easels ▸ Delete, and an easel deleted on the other Mac: every tab showing it closes.
        let gone = UUID(), other = UUID()
        let store = SidebarStore()
        store.tabs = [SidebarItem(tab: TabData(url: Easel(id: gone).url)), SidebarItem(tab: TabData(url: Easel(id: other).url)),
                      SidebarItem(tab: TabData(url: Easel(id: gone).url))]
        var closed: [UUID] = []
        EaselFiles.closeTabs(of: gone, in: store) { closed.append($0) }
        precondition(closed == [store.tabs[0].id, store.tabs[2].id], "every tab showing a deleted easel closes, and no other")
        precondition(EaselFiles.deleted.contains(gone), "a closing tab of a deleted easel writes nothing back")

        // Import of a bundle that still holds an easel deleted here: it saves again.
        let back = Easel(title: "Imported Again")
        EaselFiles.deleted.insert(back.id)
        EaselFiles.store(back.id).saveNow(back)
        let before = EaselFiles.Changes.shared.count
        EaselFiles.synced()
        precondition(!EaselFiles.deleted.contains(back.id), "an easel a bundle brought back saves again")
        precondition(EaselFiles.deleted.contains(gone), "an easel still deleted stays deleted")
        precondition(EaselFiles.Changes.shared.count == before + 1, "Library ▸ Easels lists the synced easels again")

        // A row with no file (an archived Little Window after a relaunch, a pinned row): an empty canvas that
        // writes nothing until the user draws, so an easel deleted on the other Mac can't come back blank.
        let rowOnly = UUID()
        let unsaved = EaselBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: Easel(id: rowOnly).url, delegate: nil)
        precondition(!FileManager.default.fileExists(atPath: EaselFiles.store(rowOnly).url.path), "an easel with no file opens without writing one")
        unsaved.close()
        precondition(!FileManager.default.fileExists(atPath: EaselFiles.store(rowOnly).url.path), "an untouched easel with no file writes none on close")

        // File ▸ New Easel: on disk before its tab opens, so Library ▸ Easels lists it.
        let listed = EaselFiles.Changes.shared.count
        let made = EaselFiles.create()
        precondition(FileManager.default.fileExists(atPath: EaselFiles.store(made.id).url.path), "New Easel writes its file")
        precondition(EaselFiles.Changes.shared.count == listed + 1, "New Easel is listed in Library ▸ Easels")

        // A deleted easel reopened (⇧⌘T on its Peek): its close writes nothing back.
        let reopened = EaselBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: Easel(id: gone).url, delegate: nil)
        precondition(!FileManager.default.fileExists(atPath: EaselFiles.store(gone).url.path), "a deleted easel reopened writes no blank")
        reopened.close()
        precondition(!FileManager.default.fileExists(atPath: EaselFiles.store(gone).url.path), "a deleted easel's closing canvas writes nothing")

        // Drawn on, it is made again.
        let redrawn = EaselBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: Easel(id: gone).url, delegate: nil)
        redrawn.canvasView.sheetView.insert(.init(kind: .ellipse, frame: .init(x: 300, y: 180, width: 80, height: 80)))
        precondition(!EaselFiles.deleted.contains(gone), "drawing on a deleted easel makes it again")
        precondition(EaselFiles.load(gone).items.count == 1, "drawing on a deleted easel saves it")
        redrawn.close()

        // A Favorite keeps its canvas after Delete; Import then brings the easel back.
        let kept = Easel(title: "Before Delete")
        EaselFiles.store(kept.id).saveNow(kept)
        let favorite = EaselBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: kept.url, delegate: nil)
        EaselFiles.delete(kept.id)
        let imported = Easel(id: kept.id, title: "From Import")
        EaselFiles.store(kept.id).saveNow(imported)
        EaselFiles.synced()
        precondition(favorite.canvasView.document == imported, "a canvas still loaded shows the easel Import brought back")
        favorite.close()
        precondition(EaselFiles.load(kept.id) == imported, "a canvas still loaded never writes the deleted easel over Import's")
    }
}
