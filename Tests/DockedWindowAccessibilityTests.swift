import AppKit

/// Cra's page, DevTools, floating sidebar and overlays are child windows docked over the main
/// window. Window managers find "the window" through accessibility: Moves takes the element
/// under the pointer and walks AXParent up to the first AXWindow; others read the element's
/// AXWindow, the app's AXWindows or its focused window. Each of those found the docked child,
/// so the page or sidebar was dragged off Cra's window (#391). These checks ask the same
/// questions the accessibility server asks, on real windows.
@main
enum DockedWindowAccessibilityTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        DockedWindowAccessibility.install()

        // Borderless keeps the test off screen (AppKit pulls a titled window onto the display).
        let browser = window(NSWindow.self, style: [.borderless, .resizable])
        let page = window(NSWindow.self, style: [.borderless])
        let sidebar = window(NSPanel.self, style: [.borderless, .nonactivatingPanel])
        let deep = NSButton(title: "link", target: nil, action: nil)
        page.contentView!.addSubview(deep)
        browser.addChildWindow(page, ordered: .above)
        browser.addChildWindow(sidebar, ordered: .above)
        let bubble = window(NSPanel.self, style: [.borderless])
        page.addChildWindow(bubble, ordered: .above)

        movesFindsTheBrowserWindow(from: deep, browser: browser, page: page, sidebar: sidebar, bubble: bubble)
        dockedWindowsStayInTheTree(browser: browser, page: page, sidebar: sidebar, bubble: bubble)
        appListsOnlyTheBrowserWindow(browser: browser, page: page, sidebar: sidebar, bubble: bubble)
        movingADockedWindowMovesTheBrowser(browser: browser, page: page)
        detachedWindowIsAWindowAgain(browser: browser, page: page, deep: deep)
        attachingNoWindowIsHarmless(browser: browser)

        print("Docked window accessibility: \(checks) checks passed")
    }

    // promise: #391
    @MainActor
    private static func movesFindsTheBrowserWindow(from deep: NSView, browser: NSWindow, page: NSWindow,
                                                   sidebar: NSWindow, bubble: NSWindow) {
        expect(movesPick(deep) === browser, "Moves' walk from an element in the page reaches the browser window")
        expect(movesPick(sidebar.contentView!) === browser, "Moves' walk from the floating sidebar reaches the browser window")
        expect(movesPick(bubble.contentView!) === browser, "a bubble on the page walks up through the page to the browser window")
        for docked in [page, sidebar, bubble] {
            expect(value(docked, .role) as? String == NSAccessibility.Role.group.rawValue,
                   "a docked \(type(of: docked)) is a group inside the browser window, not a window")
            expect(value(docked, .subrole) == nil, "a docked window keeps no window subrole")
            expect(value(docked, .window) as AnyObject? === browser, "a docked window's AXWindow is the browser window")
            expect(value(docked, .topLevelUIElement) as AnyObject? === browser,
                   "a docked window's AXTopLevelUIElement is the browser window")
        }
        // Views (and Chromium's web elements) name their own window as AXWindow; moving that
        // docked window moves the browser (movingADockedWindowMovesTheBrowser).
        let named = value(deep, .window) as AnyObject?
        expect(named === page || named === browser, "an element in the page names the page or the browser as its AXWindow")
        expect(value(browser, .role) as? String == NSAccessibility.Role.window.rawValue, "the browser window is still a window")
    }

    @MainActor
    private static func dockedWindowsStayInTheTree(browser: NSWindow, page: NSWindow, sidebar: NSWindow, bubble: NSWindow) {
        let children = (value(browser, .children) as? [AnyObject]) ?? []
        expect(children.contains { $0 === page } && children.contains { $0 === sidebar },
               "the browser window lists its docked windows as children (VoiceOver still reaches the page)")
        expect(children.filter { $0 === page }.count == 1, "each docked window is listed once")
        expect(((value(page, .children) as? [AnyObject]) ?? []).contains { $0 === bubble },
               "a docked page lists the bubble docked on it")
    }

    @MainActor
    private static func appListsOnlyTheBrowserWindow(browser: NSWindow, page: NSWindow, sidebar: NSWindow, bubble: NSWindow) {
        let windows = NSApp.accessibilityWindows() as? [AnyObject] ?? []
        expect(windows.contains { $0 === browser }, "AXWindows lists the browser window")
        expect(!windows.contains { $0 === page || $0 === sidebar || $0 === bubble },
               "AXWindows leaves docked windows out (Moves' keyboard moves take the first window)")
        expect(DockedWindowAccessibility.topLevel(page) === browser && DockedWindowAccessibility.topLevel(bubble) === browser,
               "the focused or main window a manager is handed is the browser window")
    }

    /// Tools that move whatever the hit element names as its AXWindow get the page window (Chromium
    /// answers that for web content); setting its position or size moves or sizes Cra's window.
    // promise: #391
    @MainActor
    private static func movingADockedWindowMovesTheBrowser(browser: NSWindow, page: NSWindow) {
        let offset = NSPoint(x: page.frame.minX - browser.frame.minX, y: page.frame.minY - browser.frame.minY)
        let before = browser.frame
        let browserPosition = (value(browser, .position) as! NSValue).pointValue
        let pagePosition = (value(page, .position) as! NSValue).pointValue
        page.accessibilitySetValue(NSValue(point: NSPoint(x: pagePosition.x + 30, y: pagePosition.y + 20)), forAttribute: .position)
        let moved = (value(browser, .position) as! NSValue).pointValue
        expect(moved.x == browserPosition.x + 30 && moved.y == browserPosition.y + 20,
               "moving the page by accessibility moves the browser window by as much")
        expect(page.frame.minX - browser.frame.minX == offset.x && page.frame.minY - browser.frame.minY == offset.y,
               "and the page stays docked where it was")
        let pageSize = (value(page, .size) as! NSValue).sizeValue
        let browserSize = browser.frame.size
        page.accessibilitySetValue(NSValue(size: NSSize(width: pageSize.width + 40, height: pageSize.height + 10)), forAttribute: .size)
        expect(browser.frame.width == browserSize.width + 40 && browser.frame.height == browserSize.height + 10,
               "resizing the page by accessibility resizes the browser window by as much")
        browser.setFrame(before, display: false)
    }

    @MainActor
    private static func detachedWindowIsAWindowAgain(browser: NSWindow, page: NSWindow, deep: NSView) {
        browser.removeChildWindow(page)
        expect(value(page, .role) as? String == NSAccessibility.Role.window.rawValue, "a window taken off its parent is a window again")
        expect(movesPick(deep) === page, "and Moves moves it on its own")
        expect(((value(browser, .children) as? [AnyObject]) ?? []).allSatisfy { $0 !== page },
               "the old parent no longer lists it")
        browser.addChildWindow(page, ordered: .above)
    }

    // promise: #391
    /// Safari's AutoFill list (SafariPlatformSupport's _updateWindowVisibility:inWindow:, loaded
    /// into every app through the PressAndHold input method) calls addChildWindow:ordered: with a
    /// nil window. The patched method took the child as non-optional and crashed on it.
    @MainActor
    private static func attachingNoWindowIsHarmless(browser: NSWindow) {
        typealias Attach = @convention(c) (NSWindow, Selector, NSWindow?, Int) -> Void
        let sel = #selector(NSWindow.addChildWindow(_:ordered:))
        let attach = unsafeBitCast(browser.method(for: sel), to: Attach.self)
        let before = browser.childWindows?.count ?? 0
        attach(browser, sel, nil, NSWindow.OrderingMode.above.rawValue)
        expect((browser.childWindows?.count ?? 0) == before, "attaching no window leaves the children as they were")
    }

    // MARK: - The questions the accessibility server asks

    /// The element under the pointer, then AXParent until the first AXWindow: Moves'
    /// AccessibilityElement.findWindow.
    @MainActor
    private static func movesPick(_ start: AnyObject) -> AnyObject? {
        var element: AnyObject? = start
        var steps = 0
        while let e = element, steps < 50 {
            if value(e, .role) as? String == NSAccessibility.Role.window.rawValue { return e }
            element = value(e, .parent) as AnyObject?
            steps += 1
        }
        return nil
    }

    /// The accessibility server reads attributes through the attribute-name entry point, which
    /// AppKit answers from the element's accessibility getters.
    @MainActor
    private static func value(_ element: AnyObject, _ attribute: NSAccessibility.Attribute) -> Any? {
        guard let object = element as? NSObject else { return nil }
        let value = object.accessibilityAttributeValue(attribute)
        if let element = value as? NSObject, attribute == .parent || attribute == .window || attribute == .topLevelUIElement {
            return unignored(element)
        }
        return value
    }

    /// AXParent skips ignored elements (a view that is only layout), as the server does.
    @MainActor
    private static func unignored(_ element: NSObject) -> NSObject {
        var e = element
        while e.accessibilityIsIgnored(), let parent = e.accessibilityAttributeValue(.parent) as? NSObject { e = parent }
        return e
    }

    @MainActor
    private static func window<W: NSWindow>(_ type: W.Type, style: NSWindow.StyleMask) -> W {
        let w = W(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 400), styleMask: style,
                  backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.orderFront(nil)
        return w
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
