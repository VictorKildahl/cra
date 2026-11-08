import AppKit
import SwiftUI

@main
enum SidebarCreationMenuTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let renderer = ImageRenderer(content: SidebarPlusMenuGlyph(tint: .white).frame(width: 32, height: 32))
        renderer.scale = 2
        let glyph = NSBitmapImageRep(cgImage: renderer.cgImage!)
        let ink = (0..<glyph.pixelsHigh).flatMap { y in
            (0..<glyph.pixelsWide).compactMap { x -> CGPoint? in
                (glyph.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 ? CGPoint(x: x, y: y) : nil
            }
        }
        expect(glyph.pixelsWide == 64 && glyph.pixelsHigh == 64, "the plus button occupies 32 by 32 points")
        expect(ink.map(\.x).max()! - ink.map(\.x).min()! + 1 == 28
               && ink.map(\.y).max()! - ink.map(\.y).min()! + 1 == 28,
               "Arc's visible plus occupies 14 by 14 points at Retina scale")
        expect(ink.filter { $0.x == 24 }.count == 4, "the plus arms are two points thick")
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
        expect(menu.handleKey(key(36)) && picks.isEmpty, "Return without a selection does not create anything")
        for _ in 0..<4 { _ = menu.handleKey(key(125)) }
        _ = menu.handleKey(key(36))
        expect(picks == [5], "Down skips disabled Boost and Split rows")
        _ = menu.handleKey(key(125))
        _ = menu.handleKey(key(36))
        expect(picks.last == 0, "Down wraps from the last row to the first")
        _ = menu.handleKey(key(126))
        _ = menu.handleKey(key(36))
        expect(picks.last == 5, "Up wraps from the first row to the last")
        _ = menu.handleKey(key(53))
        expect(picks.count == 4 && picks[3] == nil, "Escape dismisses without choosing a row")
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

        if let path = ProcessInfo.processInfo.environment["CRA_CREATION_MENU_SNAPSHOT"] {
            let preview = SidebarCreationMenuView(items: items) { _ in }
            parent.setContentSize(preview.frame.size)
            parent.contentView = preview
            for _ in 0..<3 { _ = preview.handleKey(key(125)) }
            preview.layoutSubtreeIfNeeded()
            let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
            preview.cacheDisplay(in: preview.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        parent.close()
        print("Sidebar creation menu: \(checks) checks passed")
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
