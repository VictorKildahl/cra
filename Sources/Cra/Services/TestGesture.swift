import AppKit

/// Scripted sidebar scrolls for background test instances (cra://debug?scroll=…): the scroll view
/// under a point of the window moves a step every frame, as under a trackpad's momentum, while
/// the pointer and the front app stay put.
@MainActor
enum TestGesture {
    static func scroll(by dy: CGFloat, steps: Int, at point: NSPoint, in window: NSWindow, interval: TimeInterval = 1.0 / 120) {
        guard let root = window.contentView?.superview,
              let sv = root.hitTest(point)?.enclosingScrollView else { NSLog("Cra TestGesture: no scroll view"); return }
        for i in 1...max(1, steps) {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                let clip = sv.contentView
                var origin = clip.bounds.origin
                origin.y += dy * (sv.documentView?.isFlipped ?? true ? 1 : -1)
                clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
                sv.reflectScrolledClipView(clip)
            }
        }
    }

    /// A click at a point of the window, through the app's event queue: AppKit routes it as it
    /// routes the pointer's (the window's sendEvent, first-click rules, hit testing), so a test
    /// sees what a real click there does, while the pointer and the front app stay put.
    static func click(at point: NSPoint, in window: NSWindow) {
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, 0)] {
            guard let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                             pressure: pressure) else { return }
            NSApp.postEvent(e, atStart: false)
        }
    }

    /// A key press through the app's event queue, routed as the keyboard's are (key equivalents,
    /// the page, then Cra's own keys), with the characters a layout gives: the test picks the
    /// layout's characters while the menu bar's key equivalents follow the selected one.
    static func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { return }
            NSApp.postEvent(e, atStart: false)
        }
    }

    /// Opens the menu a click (or a right-click) at a point of the window would open, without
    /// the pointer: the hit view gets the mouse-down, or the nearest view with a menu(for:)
    /// pops its menu. The menu tracks until Esc or a pick, so tests read it through AX.
    static func openMenu(at point: NSPoint, in window: NSWindow, right: Bool) {
        guard let root = window.contentView?.superview, let hit = root.hitTest(point) else { NSLog("Cra TestGesture: nothing at the point"); return }
        guard let event = NSEvent.mouseEvent(with: right ? .rightMouseDown : .leftMouseDown, location: point, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        // After this command returns: the menu's tracking loop would hold it.
        DispatchQueue.main.async {
            guard right else {
                // Buttons act on the mouse-up; the ⌄'s menu has already closed by then.
                hit.mouseDown(with: event)
                if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
                    hit.mouseUp(with: up)
                }
                return
            }
            var view: NSView? = hit
            while let v = view {
                if let menu = v.menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: v); return }
                view = v.superview
            }
            NSLog("Cra TestGesture: no menu at the point")
        }
    }
}
