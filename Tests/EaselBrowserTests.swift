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
    }
}
