import AppKit
import CraCEF

@main
enum CaptureOverlayTests {
    private static var checks = 0
    private static var failures = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        CaptureSound.enabled = false
        for childHosted in [false, true] {
            checkPeekCapture(childHosted: childHosted)
        }
        checkEscape()
        checkCapturedPixels()
        checkLateScreenshots()
        checkCancelledScreenshot()
        checkCancelledImageLookup()
        checkFailureRecovery()
        checkMainWindow()
        checkLittleWindow()
        print("Capture overlay: \(checks) checks, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    private static func checkPeekCapture(childHosted: Bool) {
        let fixture = Fixture(childHosted: childHosted)
        defer { fixture.close() }
        pressCapture(fixture)
        fixture.answerScreenshots()
        let panel = fixture.peekPanel()
        expect(panel.parent === fixture.peekWindow, "capture belongs to Peek")
        expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "capture must not cover the main page behind Peek")
        expect(panel.frame == fixture.pageRect, "capture covers Peek's actual page viewport")
        expect(panel.contentView?.bounds.size == fixture.pageRect.size, "the capture view matches Peek's viewport")
        expect(panel.isVisible && fixture.peekWindow.isVisible, "Peek stays visible while capture is open")
        guard let contents = panel.contentView?.layer?.sublayers?.first?.contents,
              CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
            fatalError("The capture's page image is missing")
        }
        expectRed(contents as! CGImage)

        let event = captureKey(in: panel)
        expect(panel.contentView?.performKeyEquivalent(with: event) == false, "the capture shortcut reaches the command handler")
        pressCapture(fixture)
        expect(panel.parent == nil && !panel.isVisible, "the second capture command detaches and hides its panel")
        expect(fixture.peekWindow.isVisible, "ending capture keeps Peek visible")
    }

    @MainActor
    private static func checkEscape() {
        let fixture = Fixture()
        defer { fixture.close() }
        pressCapture(fixture)
        fixture.answerScreenshots()
        let panel = fixture.peekPanel()
        panel.contentView?.keyDown(with: key("\u{1b}", code: 53, in: panel))
        expect(panel.parent == nil && !panel.isVisible, "Escape dismisses the real capture panel")
        expect(fixture.peekWindow.isVisible, "Escape from capture keeps Peek open")
    }

    @MainActor
    private static func checkCapturedPixels() {
        let fixture = Fixture()
        defer { fixture.close() }
        var captured: Data?
        fixture.main.onCaptureFinished = { action, png in
            if action == .copy { captured = png }
        }
        pressCapture(fixture)
        fixture.answerScreenshots()
        let panel = fixture.peekPanel()
        let view = panel.contentView!
        let start = NSPoint(x: 30, y: 30), end = NSPoint(x: 190, y: 150)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let event = NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                                          timestamp: 1, windowNumber: panel.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 0)!
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        let copy = key("c", code: 8, modifiers: .command, in: panel)
        expect(view.performKeyEquivalent(with: copy), "Command-C copies the selected capture")
        guard let captured, let image = NSBitmapImageRep(data: captured)?.cgImage else {
            fatalError("Copy did not produce a PNG")
        }
        expectRed(image)
        let expected = ContentCapture.pixelRect(for: NSRect(x: 30, y: 30, width: 160, height: 120),
                                               pageSize: view.bounds.size, imageSize: NSSize(width: 640, height: 480))
        expect(image.width == Int(expected.width) && image.height == Int(expected.height), "the PNG is cropped to the selected page area")
        expect(panel.parent == nil && !panel.isVisible && fixture.peekWindow.isVisible,
               "copy ends capture and leaves Peek open")
    }

    @MainActor
    private static func checkLateScreenshots() {
        for change in ["parked", "closing", "hidden", "replaced", "closed"] {
            let fixture = Fixture()
            defer { fixture.close() }
            pressCapture(fixture)
            switch change {
            case "parked": fixture.peek.isParked = true
            case "closing": fixture.peek.closingPeek = true
            case "hidden": fixture.peekBrowser.containerView.isHidden = true
            case "replaced": fixture.peek.browser = fixture.mainBrowser
            default: fixture.peekBrowser.isClosed = true
            }
            fixture.answerScreenshots()
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "a late screenshot must not open capture after Peek is \(change)")
            expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "an unavailable Peek must not fall back to capturing the main page")
        }
    }

    @MainActor
    private static func checkFailureRecovery() {
        let fixture = Fixture()
        defer { fixture.close() }
        pressCapture(fixture)
        fixture.peekBrowser.fail("Page.captureScreenshot", with: "capture failed")
        expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "a failed screenshot creates no panel")
        pressCapture(fixture)
        fixture.answerScreenshots()
        expect(fixture.peekPanel().isVisible, "capture can be started again after a screenshot failure")
        fixture.main.closeCapture(in: fixture.peek)
        expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "closing Peek's capture removes its panel")
    }

    @MainActor
    private static func checkCancelledScreenshot() {
        let fixture = Fixture()
        defer { fixture.close() }
        pressCapture(fixture)
        fixture.peek.isParked = true
        fixture.main.closeCapture(in: fixture.peek)
        fixture.peek.isParked = false
        fixture.answerScreenshots()
        expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "returning to Peek must not reopen a cancelled capture when its screenshot arrives")

        fixture.main.captureOverlay?.close()
        pressCapture(fixture)
        fixture.peek.isParked = true
        fixture.main.closeCapture(in: fixture.peek)
        fixture.peek.isParked = false
        fixture.main.capturePage()
        fixture.answerScreenshot(from: fixture.peekBrowser, color: .red)
        fixture.main.capturePage()
        fixture.answerScreenshot(from: fixture.mainBrowser, color: .blue)
        let panels = fixture.mainWindow.childWindows?.filter { $0 is CapturePanel } ?? []
        expect(panels.count == 1 && panels[0].isVisible,
               "cancelling Peek frees capture for the main window and stale replies leave the new request intact")
        expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "a cancelled Peek request never takes focus back from the main capture")
    }

    @MainActor
    private static func checkCancelledImageLookup() {
        let results: [String?] = [#"{"result":{"value":{"x":20,"y":20,"width":160,"height":120}}}"#, nil]
        for result in results {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.main.capturePage(liftImageAt: NSPoint(x: 30, y: 30), in: fixture.peek)
            fixture.peek.isParked = true
            fixture.main.closeCapture(in: fixture.peek)
            fixture.peek.isParked = false
            fixture.main.capturePage()
            fixture.peekBrowser.reply(to: "\(PageScript.world):Runtime.evaluate", with: result)
            fixture.answerScreenshots()
            let panels = fixture.mainWindow.childWindows?.filter { $0 is CapturePanel } ?? []
            expect(panels.count == 1 && panels[0].isVisible,
                   "a cancelled image lookup leaves the main window's new capture request intact")
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "a cancelled image lookup must not open capture when Peek returns")
        }
    }

    @MainActor
    private static func checkMainWindow() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.main.capturePage()
        fixture.answerScreenshots()
        guard let panel = fixture.mainWindow.childWindows?.first(where: { $0 is CapturePanel }) else {
            fatalError("The main window's capture panel is missing")
        }
        expect(panel.isVisible && panel.parent === fixture.mainWindow, "normal capture still belongs to the main window")
        fixture.main.closeCapture(in: fixture.peek)
        expect(panel.isVisible && panel.parent === fixture.mainWindow, "closing Peek's capture leaves another window's capture alone")
        fixture.main.capturePage()
        expect(panel.parent == nil && !panel.isVisible, "normal capture still toggles off")
    }

    @MainActor
    private static func checkLittleWindow() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.peek.isPeek = false
        pressCapture(fixture)
        fixture.answerScreenshots()
        expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "ordinary Little Windows keep their existing capture behaviour")
        expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
               "an ordinary Little Window does not send capture to the main page")
        expect(!fixture.peek.handleCapture(action: "reload"), "other commands remain with their existing handlers")
    }

    @MainActor
    private static func pressCapture(_ fixture: Fixture) {
        guard let action = KeyBindingRegistry.shared.action(for: captureKey(in: fixture.peekWindow)) else {
            fatalError("Command-Shift-2 has no binding")
        }
        expect(fixture.peek.handleCapture(action: action.id), "Peek handles its capture command")
    }

    @MainActor
    private static func captureKey(in window: NSWindow) -> NSEvent {
        key("2", code: 19, modifiers: [.command, .shift], in: window)
    }

    @MainActor
    private static func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 1,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func expectRed(_ image: CGImage) {
        guard let color = NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.deviceRGB) else {
            fatalError("The capture's pixels cannot be read")
        }
        expect(color.redComponent > 0.95 && color.blueComponent < 0.05, "capture contains Peek's red page, not the main page's blue pixels")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
}

@MainActor
private final class Fixture {
    let mainWindow: NSWindow
    let peekWindow: NSWindow
    let mainBrowser: CraBrowser
    let peekBrowser: CraBrowser
    let main: MainWindowController
    let peek: LittleWindowController
    let page: NSView
    private let host: NSWindow?

    var pageRect: NSRect { page.window!.convertToScreen(page.convert(page.bounds, to: nil)) }

    init(childHosted: Bool = false) {
        mainWindow = NSWindow(contentRect: NSRect(x: -12000, y: -10000, width: 1100, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        peekWindow = NSPanel(contentRect: NSRect(x: -11700, y: -9850, width: 700, height: 540),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        mainWindow.isReleasedWhenClosed = false
        peekWindow.isReleasedWhenClosed = false
        mainBrowser = CraBrowser(frame: NSRect(x: 180, y: 10, width: 900, height: 770), url: "https://main.test/", delegate: nil,
                                 incognito: false, profilePath: nil)
        peekBrowser = CraBrowser(frame: NSRect(x: 8, y: 8, width: 684, height: 490), url: "https://peek.test/", delegate: nil,
                                 incognito: false, profilePath: nil)
        main = MainWindowController(window: mainWindow)
        main.browsers.visibleRuntime = TabRuntime(browser: mainBrowser)
        peek = LittleWindowController(window: peekWindow)
        peek.browser = peekBrowser
        peek.peekParent = main
        mainWindow.contentView!.addSubview(mainBrowser.containerView)
        if childHosted {
            let frame = peekWindow.convertToScreen(peekBrowser.containerView.frame)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            page = NSView(frame: NSRect(x: 4, y: 6, width: 676, height: 474))
            window.contentView!.addSubview(page)
            peekWindow.addChildWindow(window, ordered: .above)
            peekBrowser.hostWindow = window
            host = window
        } else {
            page = peekBrowser.containerView
            peekWindow.contentView!.addSubview(page)
            host = nil
        }
        mainWindow.addChildWindow(peekWindow, ordered: .above)
        mainWindow.orderFront(nil)
        peekWindow.orderFront(nil)
        host?.orderFront(nil)
    }

    func peekPanel() -> NSWindow {
        guard let panel = peekWindow.childWindows?.first(where: { $0 is CapturePanel }) else {
            fatalError("Peek's capture panel is missing")
        }
        return panel
    }

    func answerScreenshots() {
        for (browser, color) in [(mainBrowser, NSColor.blue), (peekBrowser, NSColor.red)] {
            answerScreenshot(from: browser, color: color)
        }
    }

    func answerScreenshot(from browser: CraBrowser, color: NSColor) {
        while browser.replies.contains(where: { $0.method == "Page.captureScreenshot" }) {
            let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            let png = CaptureView.png(context.makeImage()!)!
            browser.reply(to: "Page.captureScreenshot", with: "{\"data\":\"\(png.base64EncodedString())\"}")
        }
    }

    func close() {
        main.captureOverlay?.close()
        if let host { peekWindow.removeChildWindow(host); host.close() }
        mainWindow.removeChildWindow(peekWindow)
        peekWindow.close()
        mainWindow.close()
    }
}
