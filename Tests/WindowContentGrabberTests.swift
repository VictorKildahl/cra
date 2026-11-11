import AppKit
import ObjectiveC

@main
enum WindowContentGrabberTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let cursor = NSCursor.current
        defer { cursor.set() }
        checkClicksAndDrag()
        checkCursors()
        checkCursorChange()
        checkEligibility()
        checkResizeEdges()
        checkRoundedResizeCorners()
        checkRightInset()
        checkSystemDragRegion()
        checkCoveredPage()
        checkChildWindow()
        checkFlippedPage()
        checkReattachment()
        print("Window content grabber: \(checks) checks passed")
    }

    @MainActor
    private static func checkClicksAndDrag() {
        let f = Fixture()
        defer { f.close() }
        NSCursor.arrow.set()
        let down = f.mouse(.leftMouseDown)
        NSApp.sendEvent(down)
        expect(f.source.delivered.count == 1 && f.source.delivered[0] === down,
               "the page receives the original press immediately")
        let small = f.mouse(.leftMouseDragged, dx: 2, dy: 1)
        NSApp.sendEvent(small)
        let up = f.mouse(.leftMouseUp, dx: 2, dy: 1)
        NSApp.sendEvent(up)
        expect(f.source.delivered.count == 3 && f.source.delivered.last === up && f.owner.drags.isEmpty,
               "a click and movement within the slop stay with the page")

        f.source.delivered.removeAll()
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 12))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 12))
        expect(f.source.delivered.map(\.type) == [.leftMouseDown],
               "the local monitor consumes the window drag and its release")
        expect(f.owner.drags.count == 1 && f.owner.drags[0].type == .leftMouseDown,
               "the system drag starts from a mouse-down event")
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        let nextUp = f.mouse(.leftMouseUp)
        NSApp.sendEvent(nextUp)
        expect(f.source.delivered.last === nextUp && f.owner.drags.count == 1,
               "the next click is not swallowed after a window drag")
    }

    @MainActor
    private static func checkCursors() {
        let f = Fixture()
        defer { f.close() }
        for cursor in [NSCursor.iBeam, .pointingHand, .crosshair, .resizeLeftRight, .resizeUpDown] {
            cursor.set()
            f.source.delivered.removeAll()
            let events = [f.mouse(.leftMouseDown), f.mouse(.leftMouseDragged, dx: 15), f.mouse(.leftMouseUp, dx: 15)]
            for event in events { NSApp.sendEvent(event) }
            expect(f.source.delivered.count == events.count && zip(f.source.delivered, events).allSatisfy { $0 === $1 },
                   "text, link, custom and resize cursors keep the entire gesture for the page")
            expect(f.owner.drags.isEmpty, "a non-arrow cursor cannot start a window drag")
        }
    }

    @MainActor
    private static func checkCursorChange() {
        let f = Fixture()
        defer { f.close() }
        NSCursor.arrow.set()
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        NSCursor.iBeam.set()
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 12))
        NSCursor.arrow.set()
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 24))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 24))
        expect(f.source.delivered.count == 4 && f.owner.drags.isEmpty,
               "a cursor change cancels the candidate for the rest of that press")
    }

    @MainActor
    private static func checkEligibility() {
        let f = Fixture()
        defer { f.close() }
        NSCursor.arrow.set()
        for depth in [56.0, 58.0, 150.0] {
            f.source.delivered.removeAll()
            NSApp.sendEvent(f.mouse(.leftMouseDown, depth: depth))
            NSApp.sendEvent(f.mouse(.leftMouseDragged, depth: depth, dx: 15))
            NSApp.sendEvent(f.mouse(.leftMouseUp, depth: depth, dx: 15))
            expect(f.source.delivered.count == 3 && f.owner.drags.isEmpty,
                   "drags starting outside the top 56 points belong to the page")
        }
        for modifiers: NSEvent.ModifierFlags in [.command, .shift, .option, .control] {
            f.source.delivered.removeAll()
            NSApp.sendEvent(f.mouse(.leftMouseDown, modifiers: modifiers))
            NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15, modifiers: modifiers))
            NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15, modifiers: modifiers))
            expect(f.source.delivered.count == 3 && f.owner.drags.isEmpty,
                   "modified presses keep their page action")
        }
        NSApp.sendEvent(f.mouse(.leftMouseDown, clickCount: 2))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15, clickCount: 2))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15, clickCount: 2))
        expect(f.owner.drags.isEmpty, "double-click text selection is never a window drag")
        f.grabber.isEnabled = { false }
        f.source.delivered.removeAll()
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15))
        expect(f.source.delivered.count == 3 && f.owner.drags.isEmpty,
               "the setting, visible toolbar and content fullscreen can disable grabbing")
        f.grabber.isEnabled = { true }
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        f.grabber.isEnabled = { false }
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15))
        expect(f.owner.drags.isEmpty, "disabling grabbing also cancels a pending press")
    }

    @MainActor
    private static func checkResizeEdges() {
        let f = Fixture()
        defer { f.close() }
        NSCursor.arrow.set()
        for size in [NSSize(width: 1000, height: 700), NSSize(width: 700, height: 460)] {
            f.owner.setFrame(NSRect(origin: f.owner.frame.origin, size: size), display: false)
            for x in [1.0, Double(size.width / 2), Double(size.width - 1)] {
                for y in [1.0, Double(size.height / 2), Double(size.height - 1)] where x != Double(size.width / 2) || y != Double(size.height / 2) {
                    let point = NSPoint(x: x, y: y)
                    let event = f.event(.leftMouseDown, point: point)
                    expect(WindowDragRegion.allows(event, in: f.owner) == !nativeResizes(at: point, in: f.owner),
                           "the edge follows AppKit's resize hit test at \(point), size=\(size), even with a stale arrow cursor")
                }
            }
        }
        let middle = f.event(.leftMouseDown, point: NSPoint(x: f.owner.frame.width / 2, y: f.owner.frame.height / 2))
        expect(WindowDragRegion.allows(middle, in: f.owner), "the page interior can still move a resizable window")
        f.owner.isMovable = false
        expect(!WindowDragRegion.allows(middle, in: f.owner), "an immovable window cannot be dragged")
        f.owner.isMovable = true
        f.owner.reportsFullscreen = true
        expect(!WindowDragRegion.allows(middle, in: f.owner), "fullscreen windows stay in their Space")
        f.owner.reportsFullscreen = false
    }

    @MainActor
    private static func nativeResizes(at point: NSPoint, in window: NSWindow) -> Bool {
        let selector = NSSelectorFromString("_resizeDirectionForMouseLocation:")
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
            fatalError("the native resize hit test must be available")
        }
        typealias Direction = @convention(c) (NSWindow, Selector, NSPoint) -> Int64
        let direction = unsafeBitCast(method_getImplementation(method), to: Direction.self)
        return direction(window, selector, point) != -1
    }

    @MainActor
    private static func checkRoundedResizeCorners() {
        NSCursor.arrow.set()
        for child in [false, true] {
            let f = Fixture(child: child)
            defer { f.close() }
            for size in [NSSize(width: 1000, height: 700), NSSize(width: 700, height: 460)] {
                f.owner.setFrame(NSRect(origin: f.owner.frame.origin, size: size), display: false)
                for right in [false, true] {
                    for top in [false, true] {
                        for dx: CGFloat in [4, 8, 12, 20] {
                            for dy: CGFloat in [4, 8, 12, 20] {
                                let point = NSPoint(x: right ? size.width - dx : dx, y: top ? size.height - dy : dy)
                                let resizing = nativeResizes(at: point, in: f.owner)
                                let screenPoint = f.owner.convertPoint(toScreen: point)
                                let event = f.event(.leftMouseDown, point: f.source.convertPoint(fromScreen: screenPoint))
                                expect(WindowDragRegion.allows(event, in: f.owner) == !resizing,
                                       "the rounded corner follows AppKit beyond the 3 pt edge band at \(point), child=\(child)")
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private static func checkRightInset() {
        for (child, flipped) in [(false, false), (true, false), (false, true), (true, true)] {
            let f = Fixture(child: child, flipped: flipped)
            defer { f.close() }
            NSCursor.arrow.set()
            for distance: CGFloat in [0.1, 1, 7, 13.9, 14] {
                f.source.delivered.removeAll()
                let dx = f.page.bounds.width / 2 - distance
                let events = [f.mouse(.leftMouseDown, dx: dx),
                              f.mouse(.leftMouseDragged, dx: dx - 60),
                              f.mouse(.leftMouseUp, dx: dx - 60)]
                for event in events { NSApp.sendEvent(event) }
                expect(f.source.delivered.count == events.count && zip(f.source.delivered, events).allSatisfy { $0 === $1 },
                       "a press in Arc's right 14 pt strip keeps every scrollbar event, including after leaving the strip")
                expect(f.owner.drags.isEmpty, "a scrollbar drag with an arrow cursor cannot move the window")
            }
            f.source.delivered.removeAll()
            let dx = f.page.bounds.width / 2 - 14.1
            NSApp.sendEvent(f.mouse(.leftMouseDown, dx: dx))
            NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: dx - 16))
            NSApp.sendEvent(f.mouse(.leftMouseUp, dx: dx - 16))
            expect(f.owner.drags.count == 1 && f.source.delivered.count == 1,
                   "window dragging still works immediately to the left of Arc's reserved strip")
        }
    }

    @MainActor
    private static func checkCoveredPage() {
        let f = Fixture()
        defer { f.close() }
        NSCursor.arrow.set()
        let button = NSButton(frame: f.page.frame)
        f.page.superview!.addSubview(button)
        let point = f.mouse(.leftMouseDown).locationInWindow
        expect(f.source.contentView!.hitTest(point) === button, "the transparent grabber leaves native controls clickable")
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15))
        expect(f.source.delivered.count == 3 && f.owner.drags.isEmpty,
               "an overlaid control cannot accidentally arm the page's window drag")
        button.removeFromSuperview()
        f.page.isHidden = true
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        expect(f.owner.drags.isEmpty, "a hidden page cannot move its former owner")
    }

    @MainActor
    private static func checkChildWindow() {
        let f = Fixture(child: true)
        defer { f.close() }
        NSCursor.arrow.set()
        let down = f.mouse(.leftMouseDown)
        let screenPoint = f.source.convertPoint(toScreen: down.locationInWindow)
        NSApp.sendEvent(down)
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15))
        expect(f.source.delivered.count == 1 && f.source.delivered[0] === down,
               "a separate Chromium page window receives the original press")
        expect(f.owner.drags.count == 1 && f.source.drags.isEmpty, "dragging a child page moves its browser window")
        let drag = f.owner.drags[0]
        expect(drag.window === f.owner && drag.locationInWindow == f.owner.convertPoint(fromScreen: screenPoint),
               "the press is translated from the child page into the owner's coordinates")
    }

    @MainActor
    private static func checkFlippedPage() {
        let f = Fixture(flipped: true)
        defer { f.close() }
        NSCursor.arrow.set()
        NSApp.sendEvent(f.mouse(.leftMouseDown, depth: 55))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, depth: 55, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, depth: 55, dx: 15))
        expect(f.owner.drags.count == 1 && f.source.delivered.count == 1,
               "a flipped Chromium view still measures the band from the top")
    }

    @MainActor
    private static func checkReattachment() {
        let f = Fixture()
        defer { f.close() }
        NSCursor.arrow.set()
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        let other = NSView(frame: f.page.frame)
        f.page.superview!.addSubview(other)
        f.grabber.attach(to: other, owner: f.owner)
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15))
        expect(f.source.delivered.count == 3 && f.owner.drags.isEmpty,
               "a pending press does not survive a page replacement")
        f.grabber.removeFromSuperview()
        NSApp.sendEvent(f.mouse(.leftMouseDown))
        NSApp.sendEvent(f.mouse(.leftMouseDragged, dx: 15))
        NSApp.sendEvent(f.mouse(.leftMouseUp, dx: 15))
        expect(f.source.delivered.count == 6 && f.owner.drags.isEmpty,
               "detaching the grabber removes its event monitor")
    }

    @MainActor
    private static func checkSystemDragRegion() {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        defer { window.close() }
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        let host = NSView(frame: NSRect(x: 100, y: 10, width: 890, height: 680))
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)
        let page = NSView(frame: host.bounds)
        page.autoresizingMask = [.width, .height]
        host.addSubview(page)
        window.orderFront(nil)

        let selector = NSSelectorFromString("_shouldZoomInDragRegionAtLocation:")
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
            fatalError("AppKit's native drag-region query is unavailable")
        }
        typealias Contains = @convention(c) (NSWindow, Selector, NSPoint) -> Bool
        let contains = unsafeBitCast(method_getImplementation(method), to: Contains.self)
        func update() {
            window.displayIfNeeded()
            NSApp.updateWindows()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        func pagePoint(right: CGFloat, top: CGFloat) -> NSPoint {
            page.convert(NSPoint(x: page.bounds.maxX - right, y: page.bounds.maxY - top), to: nil)
        }
        update()
        let corner = pagePoint(right: 5, top: 5)
        expect(contains(window, selector, corner), "the control window reproduces server-side dragging over the page corner")
        let chrome = NSPoint(x: 50, y: window.frame.height - 15)
        expect(contains(window, selector, chrome), "the control window has draggable chrome outside the page")

        let grabber = WindowContentGrabber()
        grabber.isEnabled = { false }
        grabber.attach(to: page, owner: window)
        update()
        for point in [corner, pagePoint(right: 1, top: 15), pagePoint(right: 300, top: 5), pagePoint(right: 300, top: 200)] {
            expect(!contains(window, selector, point), "the page is excluded from WindowServer's drag region even with grabbing disabled")
        }
        expect(contains(window, selector, chrome) && window.isMovableByWindowBackground,
               "excluding the page preserves native dragging over the rest of the window")
        expect(root.hitTest(root.superview!.convert(corner, from: nil)) === page,
               "the server-side exclusion does not intercept the page's mouse events")

        window.setContentSize(NSSize(width: 1200, height: 800))
        update()
        expect(!contains(window, selector, pagePoint(right: 5, top: 5)), "the exclusion follows a resized page corner")
        grabber.removeFromSuperview()
        update()
        expect(contains(window, selector, pagePoint(right: 5, top: 5)), "detaching the grabber restores the control window's drag region")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    @MainActor
    private final class Fixture {
        let owner: EventWindow
        let source: EventWindow
        let page: NSView
        let grabber = WindowContentGrabber()

        init(child: Bool = false, flipped: Bool = false) {
            owner = EventWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                                styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            owner.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            if child {
                source = EventWindow(contentRect: owner.convertToScreen(NSRect(x: 100, y: 40, width: 700, height: 600)),
                                     styleMask: .borderless, backing: .buffered, defer: false)
                source.isReleasedWhenClosed = false
                owner.addChildWindow(source, ordered: .above)
            } else {
                source = owner
            }
            let root = NSView(frame: source.contentView!.bounds)
            source.contentView = root
            page = flipped ? FlippedPage(frame: .zero) : NSView()
            page.frame = child ? root.bounds : NSRect(x: 100, y: 40, width: 700, height: 600)
            root.addSubview(page)
            grabber.isEnabled = { true }
            grabber.attach(to: page, owner: owner)
            source.orderFront(nil)
        }

        func mouse(_ type: NSEvent.EventType, depth: Double = 20, dx: CGFloat = 0, dy: CGFloat = 0,
                   modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) -> NSEvent {
            let point = page.convert(NSPoint(x: page.bounds.midX, y: page.isFlipped ? depth : page.bounds.height - depth), to: nil)
            return event(type, point: NSPoint(x: point.x + dx, y: point.y + dy), modifiers: modifiers, clickCount: clickCount)
        }

        func event(_ type: NSEvent.EventType, point: NSPoint, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 1,
                               windowNumber: source.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clickCount, pressure: 1)!
        }

        func close() {
            grabber.removeFromSuperview()
            if source !== owner { owner.removeChildWindow(source); source.close() }
            owner.close()
        }
    }

    private final class EventWindow: NSWindow {
        var delivered: [NSEvent] = []
        var drags: [NSEvent] = []
        var reportsFullscreen = false
        override var styleMask: NSWindow.StyleMask {
            get { reportsFullscreen ? super.styleMask.union(.fullScreen) : super.styleMask }
            set { super.styleMask = newValue }
        }
        override func sendEvent(_ event: NSEvent) { delivered.append(event) }
        override func performDrag(with event: NSEvent) { drags.append(event) }
    }

    private final class FlippedPage: NSView {
        override var isFlipped: Bool { true }
    }
}
