import AppKit
import CraCEF
import ImageIO

extension MainWindowController {
    /// Arc's Capture (⇧⌘2 again closes it): the page dims, a click takes the element under the
    /// pointer and a drag a rectangle, then a menu copies, saves or sends it (CaptureOverlay).
    /// Chromium draws the picture it works on (Page.captureScreenshot), so it holds the page
    /// whatever display the window is on and whatever is in front of it.
    /// `liftImageAt` (Capture Image… on an image, page points from its top left): the image there
    /// is taken at once and moves to the middle of the page with the menu beside it, as in Arc.
    func capturePage(liftImageAt point: NSPoint? = nil, in peek: LittleWindowController? = nil) {
        if let open = captureOverlay, open.isOpen {
            open.close()
            if point == nil { return }
        }
        guard captureRequest == nil, let source = captureSource(in: peek) else { return }
        let b = source.browser
        let request = UUID()
        captureRequest = (request, source.window)
        guard let point else { takeCapture(b, liftImageAt: nil, in: peek, request: request); return }
        // Where the image is first: the picture is taken with the menu already closed.
        let scale = source.window.backingScaleFactor
        let script = ContentCapture.imageRectScript(x: point.x * scale, y: point.y * scale)
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        b.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self, weak b] result, _ in
            MainActor.assumeIsolated {
                guard let self, self.captureRequest?.id == request else { return }
                guard let b else { self.captureRequest = nil; return }
                let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    .flatMap { ($0["result"] as? [String: Any])?["value"] as? [String: Any] }
                guard let value, let source = self.captureSource(in: peek), source.browser === b,
                      let rect = ContentCapture.elementRect(fromPicker: value, scale: scale, pageBounds: CGRect(origin: .zero, size: source.rect.size))
                else { self.captureRequest = nil; return }
                self.takeCapture(b, liftImageAt: rect, in: peek, request: request)
            }
        }
    }

    private func takeCapture(_ b: CraBrowser, liftImageAt image: CGRect?, in peek: LittleWindowController?, request: UUID) {
        let lift = image
        b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","captureBeyondViewport":false}"#) { [weak self, weak b] shot, error in
            MainActor.assumeIsolated {
                guard let self, self.captureRequest?.id == request else { return }
                self.captureRequest = nil
                guard let b, let source = self.captureSource(in: peek), source.browser === b else { return }
                guard let image = Self.screenshotImage(shot) else {
                    NSLog("Cra: capture failed: %@", error ?? "no data")
                    if let peek { peek.showToast("Capture Failed") } else { self.showToast("Capture Failed") }
                    return
                }
                let overlay = CaptureOverlay(over: source.window, pageRect: source.rect, shot: image, browser: b)
                overlay.onFinish = { [weak self, weak overlay, weak b] action, png in
                    let from = b.flatMap { b in overlay?.takenRect.map { (browser: b, rect: $0, page: overlay?.pageSize ?? .zero) } }
                    self?.captureFinished(action, png, in: peek, from: from)
                }
                self.captureOverlay = overlay
                if let lift { overlay.lift(lift) }
            }
        }
    }

    func closeCapture(in peek: LittleWindowController) {
        guard let window = peek.window else { return }
        if captureRequest?.window === window { captureRequest = nil }
        if captureOverlay?.parentWindow === window { captureOverlay?.close() }
    }

    /// The focused page on screen, whether its view is embedded in the card or in its own window.
    private func captureSource(in peek: LittleWindowController?) -> (browser: CraBrowser, window: NSWindow, rect: NSRect)? {
        let browser: CraBrowser
        let window: NSWindow
        let host: NSWindow?
        if let peek {
            guard peek.canCapturePage, let b = peek.browser, let w = peek.window else { return nil }
            browser = b
            window = w
            host = b.hostWindow
        } else {
            guard let rt = browsers.visibleRuntime, let w = self.window else { return nil }
            browser = rt.browser
            window = w
            host = rt.hostWindow
        }
        guard browser.isCreated, !browser.isClosed else { return nil }
        guard let rect = pageScreenRect(browser: browser, host: host) else { return nil }
        return (browser, window, rect)
    }

    func pageScreenRect(_ rt: TabRuntime) -> NSRect? {
        pageScreenRect(browser: rt.browser, host: rt.hostWindow)
    }

    private func pageScreenRect(browser: CraBrowser, host: NSWindow?) -> NSRect? {
        let view = host.flatMap { EmbeddedPages.pageViews(of: $0)?.last } ?? browser.containerView
        guard let w = view.window, !view.isHiddenOrHasHiddenAncestor, view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        return w.convertToScreen(view.convert(view.bounds, to: nil))
    }

    static func screenshotImage(_ shot: String?) -> CGImage? {
        guard let shot, let o = try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any],
              let b64 = o["data"] as? String, let png = Data(base64Encoded: b64),
              let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
