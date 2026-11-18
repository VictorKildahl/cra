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
