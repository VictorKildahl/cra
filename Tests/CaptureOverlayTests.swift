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
        checkOptionPicksDeeper()
        checkFieldKeepsEditingKeys()
        checkArcsColours()
        checkEditRow()
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
        expect(fixture.main.capturedFrom?.rect == NSRect(x: 30, y: 30, width: 160, height: 120) && fixture.main.capturedFrom?.page == view.bounds.size,
               "the capture says where on the page it was, for an easel's live capture")
        expect(panel.parent == nil && !panel.isVisible && fixture.peekWindow.isVisible,
               "copy ends capture and leaves Peek open")
    }

    /// Capture looks as Arc's does on any page, dark ones included (#850 asked for more contrast there): the ring is
    /// Arc's dark navy #161C2F (ARC_Capture.bundle), and the page around the selection turns grey under a 25 % black
    /// veil (243 → 181, measured on Arc 1.171), so the selection is the one part in colour and at full brightness.
    // promise: #850
    @MainActor
    private static func checkArcsColours() {
        let ring = CaptureStyle.ring.usingColorSpace(.sRGB)!
        expect([ring.redComponent, ring.greenComponent, ring.blueComponent].map { Int(($0 * 255).rounded()) } == [22, 28, 47],
               "the ring is Arc's #161C2F")
        expect(CaptureStyle.dim == 0.75, "the page around the selection is dimmed as Arc dims it (243 → 181)")
        checkMenuFollowsTheAppearance()
    }

    /// #822: the menu beside a capture is white with black text in Light mode and Arc's navy with white text in Dark,
    /// as ARC_Capture.bundle's light and dark colours are. It was navy in Light mode too.
    // promise: #822
    @MainActor
    private static func checkMenuFollowsTheAppearance() {
        func bytes(_ c: NSColor) -> [Int] {
            let s = c.usingColorSpace(.sRGB)!
            return [s.redComponent, s.greenComponent, s.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        defer { SystemAppearance.shared.isDark = true }
        SystemAppearance.shared.isDark = false
        let light = CaptureMenu(easels: [], choose: { _ in }).debugColors
        expect(bytes(light.fill) == [255, 255, 255], "Light mode: the capture menu is white (\(bytes(light.fill)))")
        expect(bytes(light.ink) == [0, 0, 0], "Light mode: its text is black (\(bytes(light.ink)))")
        SystemAppearance.shared.isDark = true
        let dark = CaptureMenu(easels: [], choose: { _ in }).debugColors
        expect(bytes(dark.fill) == [18, 15, 46], "Dark mode: the capture menu is Arc's (18,15,46) (\(bytes(dark.fill)))")
        expect(bytes(dark.ink) == [255, 255, 255], "Dark mode: its text is white (\(bytes(dark.ink)))")
    }

    /// Arc's Edit row (#851): the capture opens in the image editor over the page, Escape and ⌘ keys stay in it
    /// rather than ending the capture, and once it closes the menu's rows take the edited capture. The editor here
    /// is a stand-in that paints the capture blue; the real one's drawing is checked in the easel canvas harness.
    // promise: #851
    @MainActor
    private static func checkEditRow() {
        let fixture = Fixture()
        weak var made: StandInEditor?
        CaptureEditors.make = { frame, image in
            let editor = StandInEditor(frame: frame, image: image)
            made = editor
            return editor
        }
        defer {
            fixture.close()
            CaptureEditors.make = { _, _ in nil }
        }
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
        guard let overlay = fixture.main.captureOverlay else { fatalError("no capture overlay") }
        expect(overlay.debugMenu(typed: "", run: "Edit").contains("Edit"), "the menu has Arc's Edit row")
        spin { overlay.editor != nil }
        expect(overlay.editor != nil && made?.superview === view, "Edit opens the editor over the capture")
        view.keyDown(with: key("\u{1b}", code: 53, in: panel))
        view.cancelOperation(nil)
        expect(overlay.isOpen && overlay.editor != nil, "Escape leaves the editor open, as in Arc")
        _ = view.performKeyEquivalent(with: key("z", code: 6, modifiers: .command, in: panel))
        expect(overlay.isOpen && overlay.editor != nil, "a ⌘ key in the editor doesn't end the capture")
        overlay.editor?.finish()
        expect(overlay.editor == nil && made?.superview == nil, "closing the editor brings the capture and its menu back")
        expect(view.performKeyEquivalent(with: key("c", code: 8, modifiers: .command, in: panel)), "Command-C copies the capture")
        guard let captured, let image = NSBitmapImageRep(data: captured)?.cgImage,
              let color = NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.deviceRGB)
        else { return expect(false, "Copy after Edit produced a PNG") }
        expect(color.blueComponent > 0.95 && color.redComponent < 0.05, "Copy takes the edited capture, not the page as taken")
        let expected = ContentCapture.pixelRect(for: NSRect(x: 30, y: 30, width: 160, height: 120),
                                               pageSize: view.bounds.size, imageSize: NSSize(width: 640, height: 480))
        expect(image.width == Int(expected.width) && image.height == Int(expected.height), "the edited capture keeps its size")
    }

    /// The "Send To…" field holding the keyboard keeps ⌘A ⌘V ⌘X ⌘Z for its text: they ended the capture,
    /// as any other ⌘ key does. ⌘C still copies the picture.
    @MainActor
    private static func checkFieldKeepsEditingKeys() {
        let fixture = Fixture()
        defer { fixture.close() }
        var finished: CaptureOverlay.Action??
        fixture.main.onCaptureFinished = { action, _ in finished = .some(action) }
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
        spin { panel.firstResponder is NSTextView }
        expect(panel.firstResponder is NSTextView, "the Send To field holds the keyboard once the menu shows")
        for (c, code) in [("a", UInt16(0)), ("v", 9), ("x", 7), ("z", 6)] {
            _ = view.performKeyEquivalent(with: key(c, code: code, modifiers: .command, in: panel))
            expect(finished == nil && panel.isVisible, "Command-\(c.uppercased()) in the field keeps the capture")
        }
        expect(view.performKeyEquivalent(with: key("c", code: 8, modifiers: .command, in: panel)), "Command-C still copies the capture")
        expect(finished == .some(.copy), "Command-C ends the capture with a copy")
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

    /// #835: Capture (⇧⌘2) works in an ordinary Little Window (not only Peek), attaching to the
    /// Little Window's own page, toggling off on a second press, staying idle on an empty ⌥⌘N card,
    /// and never leaking capture to the main browser window behind it.
    // promise: #835
    @MainActor
    private static func checkLittleWindow() {
        for childHosted in [false, true] {
            let fixture = Fixture(childHosted: childHosted)
            defer { fixture.close() }
            fixture.peek.isPeek = false
            fixture.peek.peekParent = nil
            pressCapture(fixture)
            fixture.answerScreenshots()
            let panel = fixture.peekWindow.childWindows?.first(where: { $0 is CapturePanel })
            expect(panel != nil && panel?.parent === fixture.peekWindow && panel?.isVisible == true,
                   "Capture (Command-Shift-2) opens over an ordinary Little Window")
            expect(panel?.frame == fixture.pageRect, "capture covers the Little Window's actual page viewport")
            expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "an ordinary Little Window does not send capture to the main page")
            if let contents = panel?.contentView?.layer?.sublayers?.first?.contents,
               CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                expectRed(contents as! CGImage)
            } else {
                expect(false, "the Little Window capture's page image is present")
            }
            pressCapture(fixture)
            expect(panel?.parent == nil && panel?.isVisible != true,
                   "the second capture command closes the Little Window's capture")
            expect(fixture.peekWindow.isVisible, "ending capture keeps the Little Window open")
        }

        // An empty Little Card (⌥⌘N) or a Little Window with no page yet stays quiet and never captures main.
        for empty in ["card", "noPage"] {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.peek.isPeek = false
            fixture.peek.peekParent = nil
            if empty == "card" { fixture.peek.isCard = true } else { fixture.peek.hasPage = false }
            pressCapture(fixture)
            fixture.answerScreenshots()
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "an empty Little Window (\(empty)) does not open capture")
            expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "an empty Little Window (\(empty)) does not fall back to capturing the main page")
        }

        // Starting capture while the main window already has an overlay open switches capture to the Little Window.
        do {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.peek.isPeek = false
            fixture.peek.peekParent = nil
            fixture.main.capturePage()
            fixture.answerScreenshots()
            expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) == true,
                   "main window capture is open first")
            pressCapture(fixture)
            fixture.answerScreenshots()
            expect(fixture.mainWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "capturing in a Little Window closes the main window's capture")
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) == true,
                   "capturing in a Little Window opens capture over the Little Window even if main had one open")
            fixture.peek.closeCapture()
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "closing the Little Window's capture removes its panel")
            expect(!fixture.peek.handleCapture(action: "reload"), "other commands remain with their existing handlers")
        }

        // Capture Image… from the context menu works on an ordinary Little Window too.
        do {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.peek.isPeek = false
            fixture.peek.peekParent = nil
            fixture.peek.captureImage(at: NSPoint(x: 30, y: 30))
            fixture.peekBrowser.reply(to: "\(PageScript.world):Runtime.evaluate",
                                      with: #"{"result":{"value":{"x":20,"y":20,"width":160,"height":120}}}"#)
            fixture.answerScreenshots()
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) == true,
                   "Capture Image opens over an ordinary Little Window")
            fixture.peek.closeCapture()
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "closing after Capture Image removes the Little Window's capture panel")
        }

        // Switching browser hosts while a Little Window capture request is still pending cancels
        // the original host's request so a late screenshot cannot reopen capture after closeCapture().
        for viaImage in [false, true] {
            let fixture = Fixture()
            defer { fixture.close() }
            let secondWindow = NSWindow(contentRect: NSRect(x: -12000, y: -10000, width: 1100, height: 800),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
            secondWindow.isReleasedWhenClosed = false
            defer { secondWindow.close() }
            let secondHost = MainWindowController(window: secondWindow)
            fixture.peek.isPeek = false
            fixture.peek.peekParent = nil
            pressCapture(fixture)
            fixture.peek.captureHost = secondHost
            if viaImage {
                fixture.peek.captureImage(at: NSPoint(x: 30, y: 30))
            } else {
                pressCapture(fixture)
            }
            fixture.peek.closeCapture()
            fixture.answerScreenshots()
            fixture.answerScreenshots()
            expect(fixture.peekWindow.childWindows?.contains(where: { $0 is CapturePanel }) != true,
                   "switching capture host while pending (\(viaImage ? "image" : "page")) cancels the first host's request")
        }

        // Sending a Little Window capture to an easel reveals a hidden host window, and capture
        // toasts (Messages unavailable, capture failed) surface on the Little Window itself.
        do {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.mainWindow.removeChildWindow(fixture.peekWindow)
            fixture.mainWindow.orderOut(nil)
            expect(!fixture.mainWindow.isVisible, "host window starts hidden")
            fixture.peek.isPeek = true
            fixture.main.revealForLittleWindowEasel(from: fixture.peek)
            expect(!fixture.mainWindow.isVisible, "Peek easel capture does not unexpectedly reveal a hidden host")
            fixture.peek.isPeek = false
            fixture.peek.peekParent = nil
            fixture.main.revealForLittleWindowEasel(from: fixture.peek)
            expect(fixture.mainWindow.isVisible, "ordinary Little Window easel capture reveals a hidden host window")

            fixture.main.showCaptureToast("Messages Isn't Available", in: fixture.peek)
            expect(fixture.peek.toasts == ["Messages Isn't Available"] && fixture.main.toasts.isEmpty,
                   "Messages unavailable toast surfaces on the Little Window when capture started there")
            fixture.main.showCaptureToast("Messages Isn't Available", in: nil)
            expect(fixture.main.toasts == ["Messages Isn't Available"],
                   "Messages unavailable toast surfaces on the main window for main-window capture")
            pressCapture(fixture)
            fixture.peekBrowser.fail("Page.captureScreenshot", with: "boom")
            expect(fixture.peek.toasts.last == "Capture Failed",
                   "a failed Little Window screenshot surfaces its toast on the Little Window")
        }
    }

    /// #451: the pointer on a title line lights Arc's choice, the card around it; holding ⌥ lights
    /// the line itself without asking the page again, letting go lights the card, and a click with
    /// ⌥ held takes the line.
    // promise: #451
    @MainActor
    private static func checkOptionPicksDeeper() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.main.capturePage()
        fixture.answerScreenshots()
        guard let overlay = fixture.main.captureOverlay, let panel = fixture.mainWindow.childWindows?.first(where: { $0 is CapturePanel }),
              let view = panel.contentView else { fatalError("The main window's capture panel is missing") }
        let isolated = "\(PageScript.world):Runtime.evaluate"
        fixture.mainBrowser.reply(to: isolated, with: #"{"result":{"value":2}}"#)  // devicePixelRatio
        let title = CGRect(x: 40, y: 221, width: 103, height: 19), card = CGRect(x: 40, y: 40, width: 300, height: 300)
        let at = view.convert(NSPoint(x: 60, y: 230), to: nil)
        func mouse(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags, timestamp: 1, windowNumber: panel.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        }
        func option(_ held: Bool) -> NSEvent {
            NSEvent.keyEvent(with: .flagsChanged, location: at, modifierFlags: held ? .option : [], timestamp: 1, windowNumber: panel.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!
        }
        view.mouseMoved(with: mouse(.mouseMoved, []))
        // The page's answer: the line, its heading and its card under the pointer, in device pixels.
        let k = Double(panel.backingScaleFactor)
        func row(_ tag: String, _ r: CGRect, inline: Bool = false) -> String {
            #"{"tag":"\#(tag)","inline":\#(inline),"shadow":false,"w":\#(r.width),"h":\#(r.height),"x":\#(r.minX * k),"y":\#(r.minY * k),"width":\#(r.width * k),"height":\#(r.height * k)}"#
        }
        let stack = [row("A", title, inline: true), row("H3", CGRect(x: 40, y: 220, width: 300, height: 20)), row("DIV", card)]
        fixture.mainBrowser.reply(to: isolated, with: #"{"result":{"value":{"view":{"w":900,"h":770},"stack":["# + stack.joined(separator: ",") + "]}}}")
        // The overlay takes the answer on the main queue.
        spin { overlay.pickedElement == card }
        expect(overlay.pickedElement == card, "the pointer on a title lights Arc's choice, its card")
        view.flagsChanged(with: option(true))
        expect(overlay.pickedElement == title, "holding Option lights the title line itself")
        expect(!fixture.mainBrowser.replies.contains(where: { $0.method == isolated }), "Option chooses again without asking the page")
        view.flagsChanged(with: option(false))
        expect(overlay.pickedElement == card, "letting go of Option lights the card again")
        view.flagsChanged(with: option(true))
        view.mouseDown(with: mouse(.leftMouseDown, .option))
        view.mouseUp(with: mouse(.leftMouseUp, .option))
        expect(overlay.takenRect == title, "a click with Option held captures the title line")
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

    /// Runs the main run loop until `condition` holds, for at most `timeout` seconds. A fixed 0.1 s was too short
    /// under Nightly's sanitizers (4-10 of these checks failed there, none on a Mac); the expect after it still fails
    /// when the condition never comes.
    @MainActor
    private static func spin(timeout: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
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
        peek.captureHost = main
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

/// Capture's editor in this harness: closing paints the capture blue, so the test can tell an edited capture.
@MainActor
private final class StandInEditor: NSView, CaptureEditing {
    var onDone: (CGImage) -> Void = { _ in }
    private let image: CGImage

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    func focus() {}

    func finish() {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        removeFromSuperview()
        onDone(ctx.makeImage()!)
    }
}
