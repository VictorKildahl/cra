import AppKit

/// Right-click or hold Back or Forward (GitHub #416): the history menu's real view and window off
/// screen, and the button's hold. The rows and geometry are CraCore's BackForwardMenu (its own tests).
@main
enum BackForwardMenuViewTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try historyMenuCase()
        print("Back and Forward history menu: \(checks) checks passed")
    }

    /// The menu's rows, keys and clicks, its window under the button, and the button's hold.
    // promise: #416
    @MainActor
    private static func historyMenuCase() throws {
        let items = ["Playboi Carti", "There's really levels to this and I mean it", "Reddit - The heart of the internet"].map {
            BackForwardMenuItem(title: $0, icon: nil, flip: false)
        }
        var picks: [Int?] = []
        let menu = BackForwardMenuView(items: items) { picks.append($0) }
        expect(menu.frame.size == NSSize(width: 232, height: 154), "three rows: Arc's 220 × 136 pt fill under a 7 pt tail, 6 pt of shadow round it")
        expect(menu.selected == nil, "nothing is picked until the pointer or a key picks a row")
        _ = menu.handleKey(key(36))
        expect(picks.isEmpty, "Return with nothing picked goes nowhere")
        _ = menu.handleKey(key(125))
        expect(menu.selected == 0, "Down picks the nearest page first")
        _ = menu.handleKey(key(126))
        expect(menu.selected == 2, "Up wraps to the farthest page")
        _ = menu.handleKey(key(36))
        expect(picks == [2], "Return goes to the picked page")
        _ = menu.handleKey(key(53))
        expect(picks.count == 2 && picks[1] == nil, "Escape closes without going anywhere")
        expect(!menu.handleKey(key(0, characters: "a")), "other keys reach the browser")
        expect(BackForwardMenuView.fitted(items[1].title) == "There's really levels to t…"
               && BackForwardMenuView.fitted(items[2].title) == "Reddit - The heart of th…",
               "long titles are cut where Arc cuts them (13 pt medium in 160 pt)")
        expect(BackForwardMenuView.fitted(items[0].title) == "Playboi Carti", "a short title stays whole")
        let rows = menu.subviews.compactMap { $0 as? NSButton }
        expect(rows.count == 3 && rows[1].accessibilityLabel() == items[1].title && rows[1].accessibilityRole() == .menuItem,
               "each page is an accessibility menu item named by its title")
        rows[1].performClick(nil)
        expect(picks.last == 1, "an accessibility press goes to its page")

        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.contentView = menu
        let second = menu.convert(NSPoint(x: 100, y: 80), to: nil)
        menu.mouseMoved(with: mouse(.mouseMoved, point: second, window: parent))
        expect(menu.selected == 1, "the row under the pointer is picked: rows are 40 pt from 20 pt down")
        menu.mouseDown(with: mouse(.leftMouseDown, point: second, window: parent))
        menu.mouseUp(with: mouse(.leftMouseUp, point: second, window: parent))
        expect(picks.last == 1, "a click goes to that page")
        let count = picks.count
        let tail = menu.convert(NSPoint(x: 116, y: 3), to: nil)
        menu.mouseDown(with: mouse(.leftMouseDown, point: tail, window: parent))
        menu.mouseUp(with: mouse(.leftMouseUp, point: tail, window: parent))
        expect(picks.count == count, "a click outside the rows picks nothing")

        // The window: hung below its button, tail up, growing from the tail's tip.
        let anchor = RightClickCounter(frame: NSRect(x: 180, y: 400, width: 32, height: 32))
        parent.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        parent.contentView?.addSubview(anchor)
        let controller = SidebarCreationMenuController()
        let shown = BackForwardMenuView(items: items) { _ in }
        shown.arrowX = 116
        var opened: [Bool] = []
        controller.present(shown, frame: NSRect(x: 0, y: 0, width: 232, height: 154), from: anchor, systemShadow: false) { opened.append($0) }
        expect(parent.childWindows?.count == 1 && controller.isOpen && opened == [true], "the menu is a child of the button's window")
        guard let layer = shown.layer, let scale = layer.animation(forKey: "creationMenuTransform") as? CABasicAnimation,
              let fade = layer.animation(forKey: "creationMenuOpacity") as? CABasicAnimation else {
            fatalError("the menu must grow and fade in as Arc's + menu does")
        }
        expect(scale.duration == 0.1 && fade.duration == 0.05, "Arc's ArcMenu timings")
        let small = (scale.fromValue as! NSValue).caTransform3DValue
        let tip = CGPoint(x: shown.arrowX - layer.bounds.width * layer.anchorPoint.x, y: 6 - layer.bounds.height * layer.anchorPoint.y)
        expect(abs(tip.x * small.m11 + small.m41 - tip.x) < 0.00001 && abs(tip.y * small.m22 + small.m42 - tip.y) < 0.00001,
               "the menu grows from its tail's tip, at the top")
        let onAnchor = anchor.convert(NSPoint(x: 16, y: 16), to: nil)
        // Local monitors run in sendEvent; one that returns nil keeps the event from the window.
        NSApp.sendEvent(mouse(.rightMouseDown, point: onAnchor, window: parent))
        expect(!controller.isOpen && opened == [true, false], "a right-click on the button closes its menu")
        expect(anchor.rightClicks == 0, "and does nothing else: the button doesn't open the menu again")
        NSApp.sendEvent(mouse(.rightMouseDown, point: onAnchor, window: parent))
        expect(anchor.rightClicks == 1, "with the menu closed, the button has its right-click again")
        controller.close(animated: false)

        // The button: a held press opens the menu and its release doesn't go back.
        var pending: [(@MainActor () -> Void)] = []
        var cancelled = 0
        let hold = ButtonHold { delay, block in
            expect(delay == 0.75, "the menu opens after a 0.75 s hold, as Arc's does")
            pending.append(block)
            return { cancelled += 1 }
        }
        var menus = 0
        let press = mouse(.leftMouseDown, point: .zero, window: parent)
        expect(!hold.down(press, enabled: true, secondary: { menus += 1 }), "a press starts as the button's own")
        expect(!hold.up() && cancelled == 1 && menus == 0, "a quick click is a plain Back")
        _ = hold.down(press, enabled: true, secondary: { menus += 1 })
        pending.last?()
        expect(menus == 1, "held, the menu opens while the button is down")
        expect(hold.up(), "and the release does not also go back")
        expect(!hold.up(), "the next press starts afresh")
        let held = pending.count
        expect(!hold.down(press, enabled: false, secondary: { menus += 1 }) && pending.count == held, "a disabled button never opens it")
        expect(!hold.down(press, enabled: true, secondary: nil) && pending.count == held, "nor a button without a menu")
        let control = mouse(.leftMouseDown, point: .zero, window: parent, modifiers: .control)
        expect(!hold.down(control, enabled: true, secondary: { menus += 1 }) && menus == 1 && !hold.up(),
               "a quick ⌃-click is a plain Back, as on Arc's button")

        if let path = ProcessInfo.processInfo.environment["CRA_BACK_FORWARD_MENU_SNAPSHOT"] {
            let preview = BackForwardMenuView(items: items) { _ in }
            parent.setContentSize(preview.frame.size)
            parent.contentView = preview
            preview.layoutSubtreeIfNeeded()
            let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
            preview.cacheDisplay(in: preview.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        parent.close()
    }

    private static func key(_ code: UInt16, characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func mouse(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError(message) }
    }
}

private final class RightClickCounter: NSView {
    var rightClicks = 0
    override func rightMouseDown(with event: NSEvent) { rightClicks += 1 }
}
