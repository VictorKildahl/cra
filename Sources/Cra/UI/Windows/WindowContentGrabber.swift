import AppKit
import ObjectiveC

@MainActor
enum WindowDragRegion {
    private static let resizeInset: CGFloat = 3
    private static let resizeDirectionSelector = NSSelectorFromString("_resizeDirectionForMouseLocation:")
    private typealias ResizeDirection = @convention(c) (NSWindow, Selector, NSPoint) -> Int64

    /// Whether Cra is the active app, and when it last became so (the system's uptime). Tests set both.
    static var appIsActive: () -> Bool = { NSApp.isActive }
    static var becameActiveAt: TimeInterval = 0
    private static var activationObserver: NSObjectProtocol?

    /// Notes each time Cra comes to the front, for `cursorIsCurrent(at:)`.
    static func watchActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { becameActiveAt = ProcessInfo.processInfo.systemUptime }
        }
    }

    /// Whether the cursor at this press says what is under the pointer (PageTopDrag.cursorIsCurrent):
    /// not on an inactive Cra, nor for the press that brought it to the front.
    static func cursorIsCurrent(at event: NSEvent) -> Bool {
        PageTopDrag.cursorIsCurrent(appActive: appIsActive(), becameActiveAt: becameActiveAt, pressedAt: event.timestamp)
    }

    /// `cursorIsCurrent`: what the gesture's press found; nil asks for this event.
    static func allows(_ event: NSEvent, in owner: NSWindow, cursorIsCurrent: Bool? = nil) -> Bool {
        guard let target = event.window, owner.isMovable, !owner.styleMask.contains(.fullScreen),
              !(cursorIsCurrent ?? Self.cursorIsCurrent(at: event)) || NSCursor.current == .arrow else { return false }
        let point = target.convertPoint(toScreen: event.locationInWindow)
        guard owner.styleMask.contains(.resizable) else { return true }
        // AppKit's corner targets reach farther inward than its straight edges. Chromium uses
        // this same hit test before starting a window drag; -1 means the point is not a resize.
        if let method = class_getInstanceMethod(type(of: owner), resizeDirectionSelector) {
            let direction = unsafeBitCast(method_getImplementation(method), to: ResizeDirection.self)
            return direction(owner, resizeDirectionSelector, owner.convertPoint(fromScreen: point)) == -1
        }
        return owner.frame.insetBy(dx: resizeInset, dy: resizeInset).contains(point)
    }
}

/// Arc's WindowContentGrabber leaves the press with the page and only takes a drag while the
/// cursor is the ordinary arrow. A text, link or resize cursor keeps the gesture for its target.
/// As in Arc (real drags, 11 Nov 2026, #363): the first drag event moves the window, however small,
/// from where that event is, and the release goes to the page, so a slipped click still clicks.
final class WindowContentGrabber: NSView {
    weak var owner: NSWindow?
    weak var pageView: NSView?
    var isEnabled: () -> Bool = { false }
    /// The height of the bar above the page in its card (0 with none): the band is what is left of 60 pt.
    var barHeight: () -> CGFloat = { 0 }
    private var monitor: Any?
    private var press: NSEvent?
    private var dragging = false
    /// Whether the press went by the cursor; its drag does the same.
    private var pressCursorIsCurrent = true

    func attach(to page: NSView, owner: NSWindow) {
        guard let host = page.superview else { removeFromSuperview(); return }
        WindowDragRegion.watchActivation()
        if pageView !== page { press = nil; dragging = false }
        pageView = page
        self.owner = owner
        if superview !== host || host.subviews.last !== self {
            host.addSubview(self, positioned: .above, relativeTo: nil)
        }
        frame = host.bounds
        autoresizingMask = [.width, .height]
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Embedded pages leave Chromium's BridgedContentView behind. Preserve its titlebar
    // exclusion so WindowServer cannot start a drag before the page handles the press.
    @objc(_opaqueRectForWindowMoveWhenInTitlebar)
    func titlebarDragExclusion() -> NSRect { bounds }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        press = nil
        dragging = false
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown {
            press = nil
            dragging = false
            pressCursorIsCurrent = WindowDragRegion.cursorIsCurrent(at: event)
            guard let owner, let page = pageView, event.window === page.window, isEnabled(),
                  WindowDragRegion.allows(event, in: owner, cursorIsCurrent: pressCursorIsCurrent), let content = window?.contentView,
                  let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
                  hit.isDescendant(of: page) else { return event }
            let depth = page.convert(page.bounds, to: nil).maxY - event.locationInWindow.y
            let distanceFromRight = page.bounds.maxX - page.convert(event.locationInWindow, from: nil).x
            let modifiers = !event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
            if PageTopDrag.holds(enabled: true, barHeight: Double(barHeight()), depthIntoPage: depth,
                                 clickCount: event.clickCount, modifiers: modifiers,
                                 distanceFromRight: distanceFromRight) { press = event }
            return event
        }
        guard event.window === window else { return event }
        if event.type == .leftMouseUp {
            // The page gets the release of a window drag, as Arc's does. Not one that brought Cra forward:
            // it ends with two releases 3 ms apart, and `dragging` lasts until the next press so both stay away.
            press = nil
            return dragging && !pressCursorIsCurrent ? nil : event
        }
        // The window drag's own drag events stay away from the page, as Arc's monitor keeps them.
        if event.type == .leftMouseDragged, dragging { return nil }
        guard event.type == .leftMouseDragged, let down = press else { return event }
        guard let owner, let target = event.window, isEnabled(),
              WindowDragRegion.allows(event, in: owner, cursorIsCurrent: pressCursorIsCurrent) else {
            press = nil
            return event
        }
        // From this drag event on, as Arc's performWindowDragWithEvent: its own movement doesn't move the window.
        let location = owner.convertPoint(fromScreen: target.convertPoint(toScreen: event.locationInWindow))
        guard let drag = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: down.modifierFlags,
                                            timestamp: down.timestamp, windowNumber: owner.windowNumber, context: nil,
                                            eventNumber: down.eventNumber, clickCount: down.clickCount, pressure: down.pressure) else { return event }
        press = nil
        dragging = true
        owner.performDrag(with: drag)
        return nil
    }
}
