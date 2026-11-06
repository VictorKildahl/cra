import AppKit

@main
enum PeekDimPanelTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        var dismissed = 0
        let panel = PeekDimPanel(covering: parent) { dismissed += 1 }
        parent.addChildWindow(panel, ordered: .above)
        checkResizeEdges(parent, panel)
        expect(!panel.canBecomeKey && !panel.canBecomeMain, "the dismiss panel must not take focus")

        for size in [NSSize(width: 640, height: 420), NSSize(width: 1500, height: 1000)] {
            parent.setFrame(NSRect(origin: parent.frame.origin, size: size), display: false)
            panel.reposition(covering: parent)
            checkResizeEdges(parent, panel)
            expect(panel.contentView?.frame.size == panel.frame.size, "the click catcher follows the resized panel")
        }
        parent.setFrameOrigin(NSPoint(x: -12000, y: -9000))
        checkResizeEdges(parent, panel)
        expect(dismissed == 0, "resizing and moving the parent keep Peek open")

        let view = panel.contentView!
        let point = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let hit = view.hitTest(point)!
        expect(hit.acceptsFirstMouse(for: nil), "a background click dismisses Peek on the first click")
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
                                          windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                          clickCount: 1, pressure: 0)!
            if type == .leftMouseDown { hit.mouseDown(with: event) } else { hit.rightMouseDown(with: event) }
        }
        expect(dismissed == 2, "both left and right background clicks dismiss Peek")
        checkPageFocus(parent)
        parent.removeChildWindow(panel)
        panel.close()
        parent.close()
        print("Peek dismiss panel: \(checks) checks passed")
    }

    @MainActor
    private static func checkPageFocus(_ parent: NSWindow) {
        let peek = NSPanel(contentRect: parent.frame.insetBy(dx: 100, dy: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        let page: NSWindow = FocusTestPage(contentRect: peek.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let other: NSWindow = FocusTestPage(contentRect: peek.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        for window in [peek, page, other] { window.isReleasedWhenClosed = false }
        parent.addChildWindow(peek, ordered: .above)
        peek.addChildWindow(page, ordered: .above)
        ChromiumChildFocus.attach(page)
        expect(page.canBecomeKey, "the page in Peek keeps keyboard focus")
        expect(!page.canBecomeMain, "the page in Peek must not take the parent's main-window status and shadow")
        expect(other.canBecomeMain, "unregistered Chromium windows keep their original focus rules")
        ChromiumChildFocus.attach(page)
        expect(!page.canBecomeMain, "reattaching keeps the page from becoming main")
        peek.removeChildWindow(page)
        expect(page.canBecomeMain, "a detached page regains its original main-window eligibility")
        parent.addChildWindow(page, ordered: .above)
        expect(!page.canBecomeMain, "a page promoted from Peek still belongs to its browser window")
        parent.removeChildWindow(page)
        parent.removeChildWindow(peek)
        for window in [page, other, peek] { window.close() }
    }

    @MainActor
    private static func checkResizeEdges(_ parent: NSWindow, _ panel: PeekDimPanel) {
        let frame = parent.frame
        let xs = [frame.minX + 1, frame.midX, frame.maxX - 1]
        let ys = [frame.minY + 1, frame.midY, frame.maxY - 1]
        for x in xs {
            for y in ys where x != frame.midX || y != frame.midY {
                expect(!panel.frame.contains(NSPoint(x: x, y: y)), "Peek must leave the parent's resize edges and corners uncovered")
            }
        }
        expect(panel.frame.contains(NSPoint(x: frame.midX, y: frame.midY)), "the panel still catches clicks inside the parent")
        // Arc: 4 pt in, a click closes the Peek.
        for p in [NSPoint(x: frame.maxX - 4, y: frame.midY), NSPoint(x: frame.minX + 4, y: frame.midY),
                  NSPoint(x: frame.midX, y: frame.maxY - 4), NSPoint(x: frame.midX, y: frame.minY + 4)] {
            expect(panel.frame.contains(p), "a click 4 pt inside an edge closes the Peek, as in Arc")
        }
        expect(frame.contains(panel.frame), "the dismiss panel stays inside the parent")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
}

enum LittleWindow {
    static func cornerRadius(of window: NSWindow) -> CGFloat { 16 }
}

final class FocusTestPage: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
