import AppKit

@main
enum NativeWindowDragTests {
    @MainActor
    static func main() {
        // These windows stay offscreen; no event is posted or native drag started.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let main = RecordingWindow(contentRect: NSRect(x: 300, y: 300, width: 800, height: 600),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        let child = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 300, height: 600),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        let panel = NSPanel(contentRect: child.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        for window in [main, child, panel] { window.isReleasedWhenClosed = false }

        expect(NativeWindowDrag.target(for: main) === main, "the attached sidebar can drag its main window")
        main.addChildWindow(child, ordered: .above)
        expect(NativeWindowDrag.target(for: child) == nil, "a child window must never be dragged away from its owner")
        main.addChildWindow(panel, ordered: .above)
        panel.isMovable = false
        expect(NativeWindowDrag.target(for: panel) == nil, "the nonmovable floating sidebar panel is rejected")
        main.removeChildWindow(panel)
        panel.isMovable = true
        expect(NativeWindowDrag.target(for: panel) == nil, "a detached panel still must not become a browser drag target")
        main.isMovable = false
        expect(NativeWindowDrag.target(for: main) == nil, "nonmovable owner windows are respected")
        expect(NativeWindowDrag.target(for: nil) == nil, "views not attached to a window cannot start a drag")

        main.isMovable = true
        let panelPress = event(.leftMouseDown, windowNumber: panel.windowNumber)
        NativeWindowDrag.start(with: panelPress, in: main)
        expect(main.dragEvents.isEmpty, "a reattached view must not drag its owner with an old panel event")
        NativeWindowDrag.start(with: event(.leftMouseDragged, windowNumber: main.windowNumber), in: main)
        expect(main.dragEvents.isEmpty, "native dragging requires the original mouse-down, not a drag update")
        let mainPress = event(.leftMouseDown, windowNumber: main.windowNumber)
        NativeWindowDrag.start(with: mainPress, in: main)
        expect(main.dragEvents.count == 1 && main.dragEvents[0] === mainPress,
               "a main-window press reaches native dragging unchanged")

        main.removeChildWindow(child)
        for window in [panel, child, main] { window.close() }
        print("Native window drag ownership: 9 checks passed")
    }

    private static func event(_ type: NSEvent.EventType, windowNumber: Int) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 60), modifierFlags: [],
                          timestamp: 0, windowNumber: windowNumber, context: nil,
                          eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}

/// Records the handoff without starting an actual window-server gesture.
@MainActor
private final class RecordingWindow: NSWindow {
    var dragEvents: [NSEvent] = []
    override func performDrag(with event: NSEvent) { dragEvents.append(event) }
}
