import AppKit
import ObjectiveC

@MainActor
enum WindowDragRegion {
    private static let resizeInset: CGFloat = 3
    private static let resizeDirectionSelector = NSSelectorFromString("_resizeDirectionForMouseLocation:")
    private typealias ResizeDirection = @convention(c) (NSWindow, Selector, NSPoint) -> Int64

    static func allows(_ event: NSEvent, in owner: NSWindow) -> Bool {
        guard let target = event.window, owner.isMovable, !owner.styleMask.contains(.fullScreen),
              NSCursor.current == .arrow else { return false }
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
final class WindowContentGrabber: NSView {
    weak var owner: NSWindow?
    weak var pageView: NSView?
    var isEnabled: () -> Bool = { false }
    private var monitor: Any?
    private var press: NSEvent?
    private var dragging = false

    func attach(to page: NSView, owner: NSWindow) {
        guard let host = page.superview else { removeFromSuperview(); return }
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
            guard let owner, let page = pageView, event.window === page.window, isEnabled(),
                  WindowDragRegion.allows(event, in: owner), let content = window?.contentView,
                  let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
                  hit.isDescendant(of: page) else { return event }
            let depth = page.convert(page.bounds, to: nil).maxY - event.locationInWindow.y
            let distanceFromRight = page.bounds.maxX - page.convert(event.locationInWindow, from: nil).x
            let modifiers = !event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
            if PageTopDrag.holds(enabled: true, barAbovePage: false, depthIntoPage: depth,
                                 clickCount: event.clickCount, modifiers: modifiers,
                                 distanceFromRight: distanceFromRight) { press = event }
            return event
        }
        guard event.window === window else { return event }
        if event.type == .leftMouseUp {
            let consumed = dragging
            press = nil
            dragging = false
            return consumed ? nil : event
        }
        guard event.type == .leftMouseDragged, let down = press else { return event }
        guard let owner, let target = event.window, isEnabled(), WindowDragRegion.allows(event, in: owner) else {
            press = nil
            return event
        }
        guard PageTopDrag.isDrag(dx: event.locationInWindow.x - down.locationInWindow.x,
                                 dy: event.locationInWindow.y - down.locationInWindow.y) else { return event }
        let location = owner.convertPoint(fromScreen: target.convertPoint(toScreen: down.locationInWindow))
        guard let drag = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: down.modifierFlags,
                                            timestamp: down.timestamp, windowNumber: owner.windowNumber, context: nil,
                                            eventNumber: down.eventNumber, clickCount: down.clickCount, pressure: down.pressure) else { return event }
        press = nil
        dragging = true
        owner.performDrag(with: drag)
        return nil
    }
}
