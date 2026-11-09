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
        expect(window.frame.maxY - bubble.frame.maxY >= ExtensionPopupWindow.titleBarHeight,
               "Chrome's transparent top margin leaves the full title bar available for clicks and drags")

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
        print("Extension popup window: \(checks) checks passed")
    }

    @MainActor
    private static func event(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 1,
                           windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 0)!
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
