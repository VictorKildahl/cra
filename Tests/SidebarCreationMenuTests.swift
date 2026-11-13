import AppKit

@main
enum SidebarCreationMenuTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let mark = CAShapeLayer()
        mark.bounds = CGRect(origin: .zero, size: SidebarPlusMark.size)
        mark.path = SidebarPlusMark.path
        mark.lineWidth = SidebarPlusMark.lineWidth
        mark.lineCap = .round
        let inked = SidebarPlusMark.path.copy(strokingWithWidth: SidebarPlusMark.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10).boundingBox
        expect(inked.size == CGSize(width: 14, height: 14), "Arc's visible plus occupies 14 by 14 points")
        expect(abs(inked.midX - 7) < 0.001 && abs(inked.midY - 7) < 0.001, "the plus turns about its own centre")
        SidebarPlusMark.turn(mark, open: true, animated: true)
        let turn = mark.animation(forKey: "turn") as? CASpringAnimation
        expect(abs(mark.transform.m12 - sin(.pi / 4)) < 0.0001 && abs(mark.transform.m11 - cos(.pi / 4)) < 0.0001,
               "an open menu leaves the plus turned 45° into an ×")
        expect(turn.map { abs($0.stiffness - pow(2 * .pi / 0.2, 2)) < 0.01 && abs($0.damping - 4 * .pi * 0.5 / 0.2) < 0.01
                          && ($0.toValue as? CGFloat) == .pi / 4 } == true, "the plus springs open")
        SidebarPlusMark.turn(mark, open: false, animated: false)
        expect(mark.transform.m12 == 0 && mark.animation(forKey: "turn") == nil, "closing without animation puts the plus straight back")
        let entries = [
            ("New Space", "plus.rectangle.on.rectangle", "", true),
            ("New Folder", "folder", "", true),
            ("New Easel", "scribble.variable", "⌃⇧E", true),
            ("New Boost", "paintbrush.pointed", "", false),
            ("New Split", "rectangle.split.2x1", "⌃⇧=", false),
            ("New Tab", "plus.rectangle", "⌘T", true),
        ]
        var actions: [Int] = []
        let items = entries.enumerated().map { index, entry in
            SidebarCreationMenuItem(title: entry.0, symbol: entry.1, shortcut: entry.2, enabled: entry.3) { actions.append(index) }
        }
        var picks: [Int?] = []
        let menu = SidebarCreationMenuView(items: items) { picks.append($0) }
        expect(menu.selected == 5, "Arc opens the menu with New Tab picked")
        expect(menu.handleKey(key(36)) && picks == [5], "Return on a fresh menu makes a new tab")
        for _ in 0..<4 { _ = menu.handleKey(key(125)) }
        _ = menu.handleKey(key(36))
        expect(picks == [5, 5], "Down skips disabled Boost and Split rows")
        _ = menu.handleKey(key(125))
        _ = menu.handleKey(key(36))
        expect(picks.last == 0, "Down wraps from the last row to the first")
        _ = menu.handleKey(key(126))
        _ = menu.handleKey(key(36))
        expect(picks.last == 5, "Up wraps from the first row to the last")
        _ = menu.handleKey(key(53))
        expect(picks.count == 5 && picks[4] == nil, "Escape dismisses without choosing a row")
        expect(SidebarCreationMenuView.shortcutText("⌃⇧=") == "⌃+" && SidebarCreationMenuView.shortcutText("⌃⇧E") == "⌃⇧E",
               "Arc shows Add Split View's ⌃⇧= as ⌃+")
        expect(!menu.handleKey(key(0, characters: "a")), "unhandled keys can reach the browser's shortcuts")
        let buttons = menu.subviews.compactMap { $0 as? NSButton }
        buttons[2].performClick(nil)
        expect(picks.last == 2, "accessibility buttons select their own action")
        let pickCount = picks.count
        buttons[3].performClick(nil)
        expect(picks.count == pickCount, "disabled accessibility buttons cannot invoke an action")

        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.contentView = menu
        let point = menu.convert(NSPoint(x: 80, y: 165), to: nil)
        menu.mouseDown(with: mouse(.leftMouseDown, point: point, window: parent))
        menu.mouseUp(with: mouse(.leftMouseUp, point: point, window: parent))
        expect(picks.count == pickCount, "clicking a disabled row does not pick it")
        let folder = menu.convert(NSPoint(x: 80, y: 68), to: nil)
        menu.mouseDown(with: mouse(.leftMouseDown, point: folder, window: parent))
        menu.mouseUp(with: mouse(.leftMouseUp, point: folder, window: parent))
        expect(picks.last == 1, "a complete click chooses the folder row")

        let anchor = NSView(frame: NSRect(x: 180, y: 12, width: 28, height: 28))
        parent.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        parent.contentView?.addSubview(anchor)
        let controller = SidebarCreationMenuController()
        var openStates: [Bool] = []
        controller.toggle(from: anchor, items: items) { openStates.append($0) }
        expect(parent.childWindows?.count == 1, "the menu belongs to the source browser window")
        let popup = parent.childWindows!.first!
        expect(!(popup is NSPanel) && popup.styleMask == .borderless && popup.animationBehavior == .default,
               "ArcMenu uses a borderless NSWindow with AppKit's default presentation")
        let popupMenu = popup.contentView as! SidebarCreationMenuView
        guard let layer = popupMenu.layer,
              let openingScale = layer.animation(forKey: "creationMenuTransform") as? CABasicAnimation,
              let openingFade = layer.animation(forKey: "creationMenuOpacity") as? CABasicAnimation else {
            fatalError("the menu must animate its scale and opacity when it opens")
        }
        expect(openingScale.duration == 0.1 && openingFade.duration == 0.05,
               "Arc opens with a 100 ms scale and a 50 ms fade")
        let small = (openingScale.fromValue as! NSValue).caTransform3DValue
        expect(abs(small.m11 - 0.95) < 0.00001 && abs(small.m22 - 0.95) < 0.00001,
               "the menu grows from 95 percent of its resting size")
        let tip = CGPoint(x: popupMenu.arrowX - layer.bounds.width * layer.anchorPoint.x,
                          y: popupMenu.bounds.height - layer.bounds.height * layer.anchorPoint.y)
        expect(abs(tip.x * small.m11 + small.m41 - tip.x) < 0.00001
               && abs(tip.y * small.m22 + small.m42 - tip.y) < 0.00001,
               "the disclosure tip stays fixed while the menu grows")
        expect((openingFade.fromValue as? NSNumber)?.doubleValue == 0
               && (openingFade.toValue as? NSNumber)?.doubleValue == 1,
               "the menu fades in rather than showing its first frame fully opaque")
        let folderButton = popupMenu.subviews[1] as! NSButton
        NSApp.sendAction(folderButton.action!, to: folderButton.target, from: folderButton)
        expect(actions == [1] && popup.ignoresMouseEvents,
               "choosing an action disables pointer input while the menu fades away")
        let closingScale = layer.animation(forKey: "creationMenuTransform") as! CABasicAnimation
        let closingFade = layer.animation(forKey: "creationMenuOpacity") as! CABasicAnimation
        expect(closingScale.duration == 0.07 && closingFade.duration == 0.07
               && (closingFade.toValue as? NSNumber)?.doubleValue == 0,
               "Arc closes with a 70 ms shrink and fade")
        closingFade.delegate?.animationDidStop?(closingFade, finished: true)
        expect(parent.childWindows?.isEmpty != false && !popup.isVisible,
               "the animation's completion detaches and hides the old menu")
        expect(openStates == [true, false], "choosing resets the plus button's open state")
        controller.toggle(from: anchor, items: items) { openStates.append($0) }
        let toggledPopup = parent.childWindows!.first!
        controller.toggle(from: anchor, items: items) { openStates.append($0) }
        let toggleFade = toggledPopup.contentView!.layer!.animation(forKey: "creationMenuOpacity")!
        toggleFade.delegate?.animationDidStop?(toggleFade, finished: true)
        expect(parent.childWindows?.isEmpty != false && openStates.suffix(2) == [true, false], "the plus button toggles the menu closed")
        controller.toggle(from: anchor, items: items) { openStates.append($0) }
        let fadingPopup = parent.childWindows!.first!
        controller.close()
        let oldFade = fadingPopup.contentView!.layer!.animation(forKey: "creationMenuOpacity")!
        controller.toggle(from: anchor, items: items) { openStates.append($0) }
        let reopenedPopup = parent.childWindows!.first { $0 !== fadingPopup }!
        oldFade.delegate?.animationDidStop?(oldFade, finished: true)
        expect(!reopenedPopup.ignoresMouseEvents && parent.childWindows?.contains(reopenedPopup) == true && openStates.last == true,
               "finishing an old dismissal cannot close a newly reopened menu")
        controller.close(animated: false)
        controller.toggle(from: anchor, items: items) { openStates.append($0) }
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: parent)
        expect(parent.childWindows?.isEmpty != false && openStates.last == false, "moving the parent dismisses its menu")
        controller.close()

        try historyList(parent: parent)

        if let path = ProcessInfo.processInfo.environment["CRA_CREATION_MENU_SNAPSHOT"] {
            let preview = SidebarCreationMenuView(items: items) { _ in }
            try snapshot(preview, in: parent, to: path)
        }
        parent.close()
        print("Sidebar creation menu: \(checks) checks passed")
    }

    // promise: #416
    /// Back and Forward's right-click list (GitHub #416): Arc's menu in one group of favicon rows, hung
    /// under the button with its tail on top (Arc 1.172.1, 2x capture, 13 Nov 2026).
    @MainActor
    private static func historyList(parent: NSWindow) throws {
        let favicon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.orange.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        var picked: [Int] = []
        let titles = ["Example C", "A page title long enough that Arc cuts it short", "Example A"]
        let items = titles.enumerated().map { index, title in
            SidebarCreationMenuItem(title: title, symbol: "", shortcut: "", enabled: true, favicon: favicon) { picked.append(index) }
        }
        let layout = ArcMenuLayout(groups: [items.count], tail: .top)
        var picks: [Int?] = []
        let list = SidebarCreationMenuView(items: items, layout: layout, width: SidebarCreationMenuView.listWidth, picksLastRow: false) { picks.append($0) }
        expect(list.frame.size == NSSize(width: 220, height: 142), "three entries make a 220 × 136 pt fill under a 6 pt tail")
        expect(list.selected == nil, "the list opens with no row picked: the pointer is on the button")
        expect(list.handleKey(key(36)) && picks.isEmpty, "Return with no row picked chooses nothing")
        _ = list.handleKey(key(125))
        _ = list.handleKey(key(36))
        expect(picks == [0], "Down picks the nearest entry first")
        let rows = list.subviews.compactMap { $0 as? NSButton }
        expect(rows.map(\.frame.minY) == [14, 54, 94] && rows.allSatisfy { $0.frame.height == 40 && $0.frame.minX == 8 && $0.frame.width == 204 },
               "rows are 40 pt, 8 pt inside the fill, which starts under the tail")
        let icon = rows[0].subviews.compactMap { $0 as? NSImageView }.first
        expect(icon?.frame == NSRect(x: 8, y: 12, width: 16, height: 16) && icon?.image === favicon && icon?.contentTintColor == .white,
               "a 16 pt favicon 16 pt into the fill; a template globe is drawn white")
        expect(rows[1].accessibilityLabel() == titles[1], "a row reads its page's full title, however it is cut short")
        list.arrowX = 110
        let drawn = list.bitmapImageRepForCachingDisplay(in: list.bounds)!
        list.cacheDisplay(in: list.bounds, to: drawn)
        let scale = CGFloat(drawn.pixelsWide) / list.bounds.width
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat { drawn.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 0 }
        expect(alpha(110, 2) > 0.9 && alpha(30, 2) < 0.1, "the tail is drawn above the fill, at the button")
        expect(alpha(110, 141) > 0.9, "the fill runs to the bottom, with no tail under it")

        let anchor = NSView(frame: NSRect(x: 120, y: 440, width: 32, height: 32))
        parent.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        parent.contentView?.addSubview(anchor)
        let controller = SidebarCreationMenuController()
        controller.toggle(from: anchor, items: items, layout: layout, width: SidebarCreationMenuView.listWidth,
                          picksLastRow: false, anchorToggles: false) { _ in }
        let popup = parent.childWindows!.first!
        let button = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        expect(popup.frame.maxY == button.minY - 8 && popup.frame.midX == button.midX,
               "the list hangs centred under its button, the tail's tip 8 pt below it, 27 pt under the arrow as in Arc")
        let shown = popup.contentView as! SidebarCreationMenuView
        expect(shown.arrowX == 110, "the tail points at the button's centre")
        let layer = shown.layer!
        let small = ((layer.animation(forKey: "creationMenuTransform") as! CABasicAnimation).fromValue as! NSValue).caTransform3DValue
        let tip = CGPoint(x: shown.arrowX - layer.bounds.width * layer.anchorPoint.x, y: -layer.bounds.height * layer.anchorPoint.y)
        expect(abs(tip.x * small.m11 + small.m41 - tip.x) < 0.00001 && abs(tip.y * small.m22 + small.m42 - tip.y) < 0.00001,
               "the tail's tip on top stays fixed while the list grows")
        let row = shown.subviews[2] as! NSButton
        NSApp.sendAction(row.action!, to: row.target, from: row)
        expect(picked == [2], "picking a row goes to its entry")
        controller.close(animated: false)

        if let path = ProcessInfo.processInfo.environment["CRA_HISTORY_MENU_SNAPSHOT"] {
            let preview = SidebarCreationMenuView(items: items, layout: layout, width: SidebarCreationMenuView.listWidth, picksLastRow: false) { _ in }
            preview.arrowX = 110
            try snapshot(preview, in: parent, to: path)
        }
    }

    @MainActor
    private static func snapshot(_ view: NSView, in window: NSWindow, to path: String) throws {
        window.setContentSize(view.frame.size)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    private static func key(_ code: UInt16, characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func mouse(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError(message) }
    }
}
