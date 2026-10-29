import AppKit

/// A displayed URL is both a click target and a title-bar drag area. Keep the original
/// mouse-down for AppKit, and never turn the release after a drag into a URL-bar click.
struct WindowDragGesture {
    private var press: NSEvent?
    private var startedDragging = false

    mutating func begin(with event: NSEvent) {
        press = event
        startedDragging = false
    }

    mutating func dragEvent(for event: NSEvent) -> NSEvent? {
        guard let press, !startedDragging,
              hypot(event.locationInWindow.x - press.locationInWindow.x,
                    event.locationInWindow.y - press.locationInWindow.y) > 3 else { return nil }
        startedDragging = true
        return press
    }

    /// Native window dragging may consume mouse-up. The next mouse-down resets the
    /// gesture too, so a completed drag cannot swallow the following click.
    mutating func finish() -> Bool {
        defer { press = nil; startedDragging = false }
        return press != nil && !startedDragging
    }
}

/// The floating sidebar is a child panel, not an independently draggable browser window.
/// `performDrag` can move that panel even when `isMovable` is false. Do not hand AppKit a
/// child window, or retarget its mouse-down to a different window's coordinate system.
@MainActor
enum NativeWindowDrag {
    static func target(for window: NSWindow?) -> NSWindow? {
        guard let window, window.parent == nil, !(window is NSPanel), window.isMovable,
              !window.styleMask.contains(.fullScreen) else { return nil }
        return window
    }

    static func start(with event: NSEvent, in window: NSWindow?) {
        guard let target = target(for: window), event.type == .leftMouseDown,
              event.window === target else { return }
        // The sidebar can reattach to its owner while a gesture is in flight. Its old
        // panel's mouse-down is not a native drag event for the new window.
        target.performDrag(with: event)
    }
}
