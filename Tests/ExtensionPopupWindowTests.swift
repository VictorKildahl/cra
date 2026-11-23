import AppKit
import CraCEF

@main
enum ExtensionPopupWindowTests {
    private static var checks = 0

    @MainActor
    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let bubble = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 314, height: 214),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        bubble.isReleasedWhenClosed = false
        ExtensionPopupWindow.present(bubble, anchor: NSPoint(x: -10000, y: -10000))
        guard let window = bubble.parent as? ExtensionPopupWindow else { fatalError("Popup frame missing") }
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        expect(!window.canBecomeKey && !window.canBecomeMain, "the popup frame must not take Chrome's focus")
        expect(window.isMovable, "the rest of the titlebar remains draggable")
        let titleBarBottom = window.frame.minY + window.contentLayoutRect.maxY
        expect(bubble.frame.maxY - ExtensionPopupWindow.bubbleInset == titleBarBottom,
               "the page starts right under AppKit's title bar, whatever its height, with no gap")

        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind), let titlebar = button.superview,
                  let light = titlebar.subviews.first(where: { $0 !== button && $0.frame == button.frame && !($0 is NSButton) })
            else { fatalError("Custom traffic light missing for \(kind)") }
            expect(button.isHidden && !light.isHidden, "the custom light replaces its native button")
            expect(light.window === window, "the custom light belongs to the popup frame")
            let center = NSPoint(x: light.bounds.midX, y: light.bounds.midY)
            expect(titlebar.hitTest(light.convert(center, to: titlebar.superview)) === light, "the custom light owns its hit region")
            expect(!light.mouseDownCanMoveWindow, "a traffic light must not start a titlebar drag")
            expect(light.acceptsFirstMouse(for: nil), "the traffic light accepts clicks while its frame is not key")
            let onScreen = window.convertToScreen(light.convert(light.bounds, to: nil))
            expect(!NSIntersectsRect(bubble.frame, onScreen), "Chrome's child bubble leaves the entire traffic light clickable")

            let outside = NSPoint(x: light.bounds.maxX + 10, y: light.bounds.maxY + 10)
            light.mouseDown(with: event(.leftMouseDown, at: center, in: light))
            light.mouseUp(with: event(.leftMouseUp, at: outside, in: light))
            expect(bubble.parent === window && window.isVisible, "releasing outside a light does not dismiss the popup")
            if kind != .closeButton {
                light.mouseDown(with: event(.leftMouseDown, at: center, in: light))
                light.mouseUp(with: event(.leftMouseUp, at: center, in: light))
                expect(bubble.parent === window && window.isVisible, "disabled lights do not dismiss the popup")
            }
        }

        let close = window.standardWindowButton(.closeButton)!
        let light = close.superview!.subviews.first { $0 !== close && $0.frame == close.frame && !($0 is NSButton) }!
        let lowerEdge = NSPoint(x: light.bounds.midX, y: light.isFlipped ? light.bounds.maxY - 1.5 : light.bounds.minY + 1.5)
        bubble.orderFront(nil)
        expect(bubble.isVisible, "the stand-in Chrome bubble is visible before dismissal")
        window.sendEvent(event(.leftMouseDown, at: lowerEdge, in: light))
        expect(window.isVisible && bubble.parent === window, "mouse down alone does not close the popup")
        window.sendEvent(event(.leftMouseUp, at: lowerEdge, in: light))
        expect(!window.isVisible && bubble.parent == nil, "releasing the close light dismisses and detaches the popup")
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        expect(!bubble.isVisible, "dismissal closes the visible Chrome bubble asynchronously")

        closesOnAClickElsewhere()
        await staysOpenForItsDevTools()
        hangsUnderItsButtonUntilDragged()
        keepsADragWithARealMouse()
        print("Extension popup window: \(checks) checks passed")
    }

    @MainActor
    private static func event(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 1,
                           windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 0)!
    }

    // promise: #531
    /// A press in a window of Cra's that doesn't become key for it (the floating sidebar's panel takes
    /// focus only when a click needs it) closes the popup too. Chrome closes it only when it loses focus,
    /// so the popup stayed up over the sidebar. Presses in the popup itself keep it.
    @MainActor
    private static func closesOnAClickElsewhere() {
        let sidebar = NSPanel(contentRect: NSRect(x: -12000, y: -10000, width: 260, height: 600),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        sidebar.becomesKeyOnlyIfNeeded = true
        sidebar.isReleasedWhenClosed = false
        sidebar.orderFront(nil)
        defer { sidebar.orderOut(nil) }

        let anchor = NSPoint(x: -9800, y: -9700)
        let (page, frame) = presentPopup(anchor: anchor)
        expect(ExtensionPopupWindow.shownAnchor == anchor, "the popup on screen says where it hangs from")
        NSApp.sendEvent(click(at: NSPoint(x: 20, y: 20), in: page))
        expect(frame.isVisible && page.parent === frame, "a click in the popup's own page keeps it open")
        let titleBar = NSPoint(x: frame.frame.width / 2, y: frame.frame.height - 6)
        NSApp.sendEvent(click(at: titleBar, in: frame))
        expect(frame.isVisible && page.parent === frame, "a click on the popup's title bar keeps it open")
        // A window the popup's page opened (a <select>'s list, a permission bubble).
        let child = NSWindow(contentRect: NSRect(x: -9900, y: -9900, width: 120, height: 80),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false
        page.addChildWindow(child, ordered: .above)
        NSApp.sendEvent(click(at: NSPoint(x: 10, y: 10), in: child))
        expect(frame.isVisible && page.parent === frame, "a click in a window the popup opened keeps it open")
        page.removeChildWindow(child)
        child.orderOut(nil)

        NSApp.sendEvent(click(at: NSPoint(x: 120, y: 300), in: sidebar))
        expect(!frame.isVisible && page.parent == nil, "a click in the floating sidebar's panel closes the popup")
        expect(ExtensionPopupWindow.closed(by: click(at: NSPoint(x: 120, y: 300), in: sidebar)),
               "that click is the one that closed it, so it does nothing else (GitHub #87)")
        expect(ExtensionPopupWindow.shownAnchor == nil, "no popup hangs anywhere once it closed")

        // A right-click there closes it as well (Chrome closes a popup on any press outside it).
        let (second, secondFrame) = presentPopup(anchor: anchor)
        NSApp.sendEvent(click(at: NSPoint(x: 120, y: 300), in: sidebar, type: .rightMouseDown, timestamp: 3))
        expect(!secondFrame.isVisible && second.parent == nil, "a right-click in the sidebar closes the popup")
        expect(!ExtensionPopupWindow.closed(by: click(at: NSPoint(x: 120, y: 300), in: sidebar, timestamp: 3)),
               "a right-click isn't taken for the left click that closed it")

        // The closed popups' watches are gone: the next popup stays up for a click in its own page.
        let (third, thirdFrame) = presentPopup(anchor: anchor)
        NSApp.sendEvent(click(at: NSPoint(x: 20, y: 20), in: third))
        expect(thirdFrame.isVisible && third.parent === thirdFrame, "an earlier popup's watch doesn't close a later one")
        thirdFrame.performClose(nil)
        expect(ExtensionPopupWindow.shownAnchor == nil, "the close button ends it too")
    }

    // promise: #701
    /// Inspect in a popup's menu opens Chromium's own DevTools window ("DevTools - chrome-extension://…"), which
    /// takes focus: the popup stays open while it's inspected, as in Chrome, and clicks in DevTools keep it. Cra
    /// closed it as for any other window, so Inspect did nothing. Another window taking focus still closes it.
    @MainActor
    private static func staysOpenForItsDevTools() async {
        let anchor = NSPoint(x: -9800, y: -9700)
        let (page, frame) = presentPopup(anchor: anchor)
        // The observer leaves the first moments alone (the click that opened the popup can still be making its window key).
        try? await Task.sleep(nanoseconds: 400_000_000)
        let devtools = NSWindow(contentRect: NSRect(x: -11000, y: -10000, width: 600, height: 400),
                                styleMask: [.titled], backing: .buffered, defer: false)
        devtools.title = "DevTools - chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup.html"
        devtools.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: devtools)
        expect(frame.isVisible && page.parent === frame, "the popup's DevTools taking focus keep it open")
        NSApp.sendEvent(click(at: NSPoint(x: 100, y: 100), in: devtools))
        expect(frame.isVisible && page.parent === frame, "a click in its DevTools keeps it open")
        let other = NSWindow(contentRect: NSRect(x: -12000, y: -10000, width: 300, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.title = "Cra"
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        expect(!frame.isVisible && page.parent == nil, "another of Cra's windows taking focus closes it")
    }

    // promise: #634
    /// A popup hangs right under its button (the sidebar's sliders) unless the user dragged one away, and that
    /// place is kept across updates (Victor, 20 Nov). On 0.1.51 a move after the drop that was no drag (the
    /// frame carried along with its window) replaced it, so a popup opened from the sidebar in full screen
    /// could sit out on the page.
    @MainActor
    private static func hangsUnderItsButtonUntilDragged() {
        let defaults = UserDefaults.standard
        for key in ["extensionPopupWindowOffset", "extensionPopupWindowDragOffset"] { defaults.removeObject(forKey: key) }
        defer { for key in ["extensionPopupWindowOffset", "extensionPopupWindowDragOffset"] { defaults.removeObject(forKey: key) } }
        let anchor = NSPoint(x: -9800, y: -9700)
        func hangsUnder(_ why: String) {
            let topLeft = ExtensionPopupWindow.placement(anchor: anchor, width: 300)
            expect(topLeft == NSPoint(x: anchor.x - 300, y: anchor.y), why)
        }

        // A place dragged to on 0.1.51 stays where the user left it after the update.
        defaults.set("{107, -14}", forKey: "extensionPopupWindowOffset")
        let (first, firstFrame) = presentPopup(anchor: anchor)
        expect(ExtensionPopupWindow.placement(anchor: anchor, width: 300) == NSPoint(x: anchor.x - 300 + 107, y: anchor.y - 14),
               "a place the user dragged popups to on an earlier Cra is kept after the update")
        firstFrame.performClose(nil)
        _ = first
        // One saved under the key 0.1.52 used (01a099af) comes back too, unless there is an older one.
        defaults.removeObject(forKey: "extensionPopupWindowOffset")
        defaults.set("{-20, 30}", forKey: "extensionPopupWindowDragOffset")
        let (second, secondFrame) = presentPopup(anchor: anchor)
        expect(ExtensionPopupWindow.placement(anchor: anchor, width: 300) == NSPoint(x: anchor.x - 320, y: anchor.y + 30)
               && defaults.string(forKey: "extensionPopupWindowDragOffset") == nil,
               "a place saved under the interim key is moved back to the kept one")
        secondFrame.performClose(nil)
        _ = second
        defaults.removeObject(forKey: "extensionPopupWindowOffset")

        let (page, frame) = presentPopup(anchor: anchor)
        hangsUnder("with no place saved, the popup hangs under its button")

        // The frame carried along with its window: AppKit posts willMove and didMove, with no press on the frame.
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: frame)
        frame.setFrameOrigin(NSPoint(x: frame.frame.minX + 107, y: frame.frame.minY - 14))
        hangsUnder("a move that isn't a drag of the popup's title bar is not where the user wants popups")

        // A press on the title bar that never dragged, then the frame carried along: no drag either.
        let titleBar = NSPoint(x: frame.frame.width / 2, y: frame.frame.height - 6)
        makeCurrent(.leftMouseDown, at: titleBar, in: frame)
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: frame)
        frame.setFrameOrigin(NSPoint(x: frame.frame.minX + 200, y: frame.frame.minY))
        hangsUnder("a move after a press that never dragged is not where the user wants popups")

        // A real title-bar drag, as AppKit delivers one (measured on a test copy): willMove on the first
        // leftMouseDragged, then one didMove on the leftMouseUp, on the frame. That place is kept, as in Arc.
        let start = frame.frame.origin
        makeCurrent(.leftMouseDragged, at: titleBar, in: frame)
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: frame)
        makeCurrent(.leftMouseUp, at: titleBar, in: frame)
        let dropped = NSPoint(x: start.x + 120, y: start.y - 40), size = frame.frame.size
        frame.setFrameOrigin(dropped)
        let kept = ExtensionPopupWindow.placement(anchor: anchor, width: 300)
        // The top-left a 300 pt popup takes: moved by the same offset from hanging under the anchor.
        let wanted = NSPoint(x: anchor.x - 300 + (dropped.x - (anchor.x - size.width)), y: dropped.y + size.height)
        expect(kept == wanted, "a drag of the popup's title bar is where later popups hang")

        // After the drop the frame is carried along with its window: the place the user chose stays.
        frame.setFrameOrigin(NSPoint(x: frame.frame.minX + 300, y: frame.frame.minY + 50))
        expect(ExtensionPopupWindow.placement(anchor: anchor, width: 300) == kept,
               "a move after the drag ended doesn't replace where the user dropped it")
        frame.performClose(nil)
        _ = page
    }

    // promise: #664
    /// A drag of the title bar with a real mouse or trackpad stays where it was dropped. Measured on a test copy
    /// with events posted as the hardware's are (HID source, click state, deltas): willMove on the first
    /// leftMouseDragged, then a didMove for every step of the drag with an appKitDefined event current and the
    /// button held, while Chrome's bubble moving with the frame asks for a layout. On 0.1.52 (01a099af) the
    /// first of those ended the drag, the bubble's move put the frame back under its button, and it flashed
    /// back there on release (the same drag on a test copy: 1210,94 before and after). cliclick's drags,
    /// which #634 was checked with, give one didMove on the leftMouseUp instead. A carried move (the pointer
    /// still) stays no drag (#634).
    @MainActor
    private static func keepsADragWithARealMouse() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "extensionPopupWindowOffset")
        defer { defaults.removeObject(forKey: "extensionPopupWindowOffset") }
        var pointer = NSPoint(x: -9900, y: -9690), held = false
        ExtensionPopupWindow.pointer = { pointer }
        ExtensionPopupWindow.leftButtonDown = { held }
        defer {
            ExtensionPopupWindow.pointer = { NSEvent.mouseLocation }
            ExtensionPopupWindow.leftButtonDown = { NSEvent.pressedMouseButtons & 1 != 0 }
        }
        let anchor = NSPoint(x: -9800, y: -9700)
        let (page, frame) = presentPopup(anchor: anchor)
        let titleBar = NSPoint(x: frame.frame.width / 2, y: frame.frame.height - 6)
        let start = frame.frame.origin, size = frame.frame.size

        // The press and the first drag, then AppKit moves the frame with the pointer; the bubble comes along.
        held = true
        makeCurrent(.leftMouseDragged, at: titleBar, in: frame)
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: frame)
        makeCurrentAppKitDefined(in: frame)
        for step in 1...4 {
            let d = NSPoint(x: CGFloat(step) * -40, y: CGFloat(step) * -20)
            pointer = NSPoint(x: -9900 + d.x, y: -9690 + d.y)
            frame.setFrameOrigin(NSPoint(x: start.x + d.x, y: start.y + d.y))
            page.setFrameOrigin(NSPoint(x: page.frame.minX - 40, y: page.frame.minY - 20))
            expect(frame.frame.origin == NSPoint(x: start.x + d.x, y: start.y + d.y),
                   "the frame stays with the pointer while the title bar is dragged (step \(step))")
        }
        // The release: the button comes up, the current event still AppKit's own, and the bubble moves once more.
        held = false
        page.setFrameOrigin(NSPoint(x: page.frame.minX, y: page.frame.minY))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: page)
        // (Its frame is then placed by that offset, kept on a screen: this one is far off any.)
        let dropped = NSPoint(x: start.x - 160, y: start.y - 80)
        let wanted = NSPoint(x: anchor.x - 300 + (dropped.x - (anchor.x - size.width)), y: dropped.y + size.height)
        expect(ExtensionPopupWindow.placement(anchor: anchor, width: 300) == wanted, "later popups hang where it was dropped")

        // Afterwards the frame carried along with its window (the pointer still) doesn't replace that place.
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: frame)
        frame.setFrameOrigin(NSPoint(x: frame.frame.minX + 300, y: frame.frame.minY + 50))
        expect(ExtensionPopupWindow.placement(anchor: anchor, width: 300) == wanted, "a carried move after the drop changes nothing")
        frame.performClose(nil)
    }

    /// Makes an appKitDefined event in `window` NSApp.currentEvent, as it is while AppKit moves a dragged window.
    @MainActor
    private static func makeCurrentAppKitDefined(in window: NSWindow) {
        let event = NSEvent.otherEvent(with: .appKitDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0)!
        NSApp.postEvent(event, atStart: true)
        _ = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)
        expect(NSApp.currentEvent?.type == .appKitDefined, "AppKit's own event is current")
    }

    /// Makes a mouse event of `type` in `window`, timed now, NSApp.currentEvent (as AppKit's own are when it
    /// posts willMove and didMove).
    @MainActor
    private static func makeCurrent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        NSApp.postEvent(event, atStart: true)
        let current = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)
        expect(current?.type == type && NSApp.currentEvent?.window === window, "the \(type) is on the popup's frame")
    }

    /// A stand-in for Chrome's bubble, framed under `anchor`.
    @MainActor
    private static func presentPopup(anchor: NSPoint) -> (page: NSWindow, frame: ExtensionPopupWindow) {
        let page = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 314, height: 214),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        page.isReleasedWhenClosed = false
        ExtensionPopupWindow.present(page, anchor: anchor)
        guard let frame = page.parent as? ExtensionPopupWindow else { fatalError("Popup frame missing") }
        page.orderFront(nil)
        return (page, frame)
    }

    /// A mouse-down in `window` at a point of its content; `closed(by:)` matches clicks by their timestamp.
    @MainActor
    private static func click(at point: NSPoint, in window: NSWindow, type: NSEvent.EventType = .leftMouseDown,
                              timestamp: TimeInterval = 2) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: timestamp,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
}

@MainActor
final class AppDelegate {
    let store = PopupTestStore()
    let main = PopupTestMainWindow()
    func useNormalWindow() {}
    func handleReservedKey(_ event: NSEvent) -> Bool { false }
    func handleUnhandledKey(_ event: NSEvent) -> Bool { false }
}

final class PopupTestStore {
    func createTab(url: String, select: Bool) {}
}

final class PopupTestMainWindow {
    func showWindow(_ sender: Any?) {}
    func browserManager(download: CraDownloadInfo) {}
}

enum HitchMonitor {
    static func mark(_ message: String) {}
}

enum ChromiumWindowCorners {
    static func setSquare(_ square: Bool, for window: NSWindow) {}
}

enum ChromiumChildHover {
    static func setDocked(_ docked: Bool, for window: NSWindow) {}
}

extension CraBrowser {
    convenience init(frame: NSRect, url: String, delegate: CraBrowserDelegate) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: false, profilePath: nil)
    }
}
