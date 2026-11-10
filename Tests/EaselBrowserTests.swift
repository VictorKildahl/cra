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
        print("Easel browser: saved drawing, Peek and expanded page colours passed")
    }
}
