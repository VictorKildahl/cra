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
    /// `modifiers`: keys held through the click (an Option-click on a link, #298). `right`: the
    /// right button (Back's history menu, #416).
    static func click(at point: NSPoint, in window: NSWindow, clicks: Int = 1, modifiers: NSEvent.ModifierFlags = [], right: Bool = false) {
        let (down, up): (NSEvent.EventType, NSEvent.EventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        // A double-click is two presses, the second with clickCount 2, as AppKit counts them.
        for count in 1...max(clicks, 1) {
            for (type, pressure) in [(down, Float(1)), (up, 0)] {
                guard let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count,
                                                 pressure: pressure) else { return }
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    /// A left-button press at a point of the window, moved by `delta` in `steps` drags and released
    /// there, through the app's event queue as `click`'s are: the view under the press gets the
    /// drags, as the pointer's would (a drag on the sidebar's empty space, #547).
    static func drag(from point: NSPoint, by delta: NSPoint, steps: Int = 4, in window: NSWindow) {
        let steps = max(steps, 1)
        var events: [(NSEvent.EventType, NSPoint, Float)] = [(.leftMouseDown, point, 1)]
        for i in 1...steps {
            let f = CGFloat(i) / CGFloat(steps)
            events.append((.leftMouseDragged, NSPoint(x: point.x + delta.x * f, y: point.y + delta.y * f), 1))
        }
        events.append((.leftMouseUp, NSPoint(x: point.x + delta.x, y: point.y + delta.y), 0))
        for (type, at, pressure) in events {
            guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                             pressure: pressure) else { return }
            NSApp.postEvent(e, atStart: false)
        }
    }

    /// A middle click (button 2) at a point of the window, through the app's event queue: the window's
    /// event monitors and the view under it get it as they get the mouse's.
    static func middleClick(at point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.otherMouseDown, .otherMouseUp] {
            guard let cg = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                              pressure: type == .otherMouseDown ? 1 : 0)?.cgEvent else { continue }
            cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            guard let e = NSEvent(cgEvent: cg) else { continue }
            // Where the event goes once it is a CGEvent and back: Nightly's runner opened no link with it while this Mac
            // does (split-middle-click-pane), so the readout says which window and point AppKit routes it to.
            if type == .otherMouseDown {
                let target = NSApp.window(withWindowNumber: e.windowNumber)
                let hit = target?.contentView?.superview?.hitTest(e.locationInWindow).map { String(describing: Swift.type(of: $0)) } ?? "nothing"
                CraLog.note("middle click event: window \(e.windowNumber) (asked \(window.windowNumber)) at \(Int(e.locationInWindow.x)),\(Int(e.locationInWindow.y)) (asked \(Int(point.x)),\(Int(point.y))) button \(e.buttonNumber), hits \(hit); screen point \(Int(cg.location.x)),\(Int(cg.location.y))")
            }
            NSApp.postEvent(e, atStart: false)
        }
    }

    /// An other-button release at a point of the window, as the window's event monitors see it
    /// (its button number is AppKit's, not the one a test means).
    static func otherMouseUp(at point: NSPoint, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: .otherMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    }

    /// A key press through the app's event queue, routed as the keyboard's are (key equivalents,
    /// the page, then Cra's own keys), with the characters a layout gives: the test picks the
    /// layout's characters while the menu bar's key equivalents follow the selected one.
    /// Modifier keys now held (empty: all let go), as the flagsChanged event a key press or release
    /// posts, through the app's event queue so local monitors see it (#689).
    static func flags(_ modifiers: NSEvent.ModifierFlags, in window: NSWindow) {
        guard let e = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers,
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                       keyCode: 56) else { return }
        NSApp.postEvent(e, atStart: false)
    }

    /// A modifier key let go or pressed: the flagsChanged event the window server sends then, through the app's
    /// event queue (its local monitors see it), with `flags` the modifiers still down.
    static func flagsChanged(_ flags: CGEventFlags) {
        guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: flags.contains(.maskCommand)) else { return }
        cg.type = .flagsChanged
        cg.flags = flags
        guard let e = NSEvent(cgEvent: cg) else { return }
        NSApp.postEvent(e, atStart: false)
    }

    /// `fromKeyboard`: the event says the keyboard typed it (source process 0, as the window server's are), not that
    /// an app posted it, as a mouse driver does (#714). Otherwise it carries Cra's own process.
    static func asTyped(_ e: NSEvent, fromKeyboard: Bool) -> NSEvent {
        guard fromKeyboard, let c = e.cgEvent?.copy() else { return e }
        c.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        return NSEvent(cgEvent: c) ?? e
    }

    static func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in window: NSWindow, fromKeyboard: Bool = false) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { return }
            NSApp.postEvent(asTyped(e, fromKeyboard: fromKeyboard), atStart: false)
        }
    }

    /// A key press handed to a page's view as CraApplication.sendEvent forwards one to the page that has
    /// the keyboard, for a background test copy, whose windows are never key: CEF's OnPreKeyEvent, the
    /// page's own handlers and OnKeyEvent see it as they see a typed one (who gets a shortcut, #374).
    /// The page's view is found under `roots` (Chromium's own window when Chrome hosts the page), else
    /// it is `window`'s first responder (an embedded page that has the keyboard).
    static func pageKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in roots: [NSView], window: NSWindow?,
                        fromKeyboard: Bool = false) {
        func isPage(_ v: NSView) -> Bool { NSStringFromClass(type(of: v)) == "RenderWidgetHostViewCocoa" }
        func pageView(_ v: NSView) -> NSView? { isPage(v) ? v : v.subviews.lazy.compactMap(pageView).first }
        let focused = (window?.firstResponder as? NSView).flatMap { isPage($0) ? $0 : nil }
        guard let view = roots.lazy.compactMap(pageView).first ?? focused, let target = view.window else {
            NSLog("Cra TestGesture: no page view")
            return
        }
        target.makeFirstResponder(view)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: target.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { return }
            target.sendEvent(asTyped(e, fromKeyboard: fromKeyboard))
        }
    }

    /// A trackpad gesture's phase, as the window server numbers it (CGGesturePhase, CGScrollPhase).
    enum TrackpadPhase: Int64 {
        case began = 1, changed = 2, ended = 4, cancelled = 8, mayBegin = 128
    }

    /// A trackpad pinch on a window, its events made the way the window server makes them and
    /// routed as a trackpad's were in a probe (19 Nov 2026): the scrolls of the fingers to the view
    /// under `point` (the window's `sendEvent`), the magnify events addressed to the window through
    /// the app (`NSApp.sendEvent`, its event monitors first). The order is one a trackpad can send:
    /// two fingers touch down (a scroll and a magnify that may begin), then one magnify per step of
    /// `steps` (0.1 is 10 % apart) between its beginning and its end, and only as the fingers lift
    /// is the touch-down's scroll cancelled (#573). AppKit hands events only to a window that is
    /// ordered in.
    static func pinch(_ steps: [CGFloat], at point: NSPoint, in window: NSWindow) {
        let magnify = { (phase: TrackpadPhase, m: Double) in
            if let e = trackpadMagnify(phase, by: m, at: point, to: window) { NSApp.sendEvent(e) }
        }
        trackpadScroll(.mayBegin, at: point).map(window.sendEvent)
        magnify(.mayBegin, 0)
        magnify(.began, 0)
        for m in steps { magnify(.changed, Double(m)) }
        magnify(.ended, 0)
        trackpadScroll(.cancelled, at: point).map(window.sendEvent)
    }

    /// A trackpad magnify at a point of a window: a gesture event (type 29) of the zoom kind
    /// (IOHIDEventType 8), which AppKit reads as `.magnify`. Made here it has no window, and AppKit
    /// keeps its location as is, so it is placed where `point` is in the window's coordinates.
    /// `to`: addressed to that window as the window server addresses it (the event's window).
    static func trackpadMagnify(_ phase: TrackpadPhase, by magnification: Double = 0, at point: NSPoint, to window: NSWindow? = nil) -> NSEvent? {
        guard let e = CGEvent(source: nil), let gesture = CGEventType(rawValue: 29) else { return nil }
        e.type = gesture
        e.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)                    // the gesture's kind: zoom
        e.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase.rawValue)       // its phase
        e.setDoubleValueField(CGEventField(rawValue: 113)!, value: magnification)         // its magnification
        if let window { e.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(window.windowNumber)) }   // its window
        return event(e, at: point)
    }

    /// Two fingers on the trackpad that don't move: a continuous scroll with no deltas.
    static func trackpadScroll(_ phase: TrackpadPhase, at point: NSPoint) -> NSEvent? {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else { return nil }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        return event(e, at: point)
    }

    private static func event(_ e: CGEvent, at point: NSPoint) -> NSEvent? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        e.location = CGPoint(x: point.x, y: top - point.y)
        return NSEvent(cgEvent: e)
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
