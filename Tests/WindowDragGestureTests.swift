import AppKit

@main
enum WindowDragGestureTests {
    static func main() {
        var gesture = WindowDragGesture()
        let down = event(.leftMouseDown, x: 100, y: 60)

        gesture.begin(with: down)
        expect(gesture.dragEvent(for: event(.leftMouseDragged, x: 102, y: 61)) == nil,
               "trackpad jitter must still allow a URL click")
        expect(gesture.finish(), "a click opens the URL editor")
        expect(!gesture.finish(), "a stray mouse-up must not open the URL editor")

        gesture.begin(with: down)
        let handedOff = gesture.dragEvent(for: event(.leftMouseDragged, x: 120, y: 61))
        expect(handedOff === down, "native dragging receives the original mouse-down event")
        expect(gesture.dragEvent(for: event(.leftMouseDragged, x: 140, y: 61)) == nil,
               "a gesture starts the native window drag only once")
        expect(!gesture.finish(), "releasing a window drag must not open the URL editor")

        gesture.begin(with: down)
        _ = gesture.dragEvent(for: event(.leftMouseDragged, x: 120, y: 61))
        // AppKit can consume the drag's mouse-up. The next press must recover on its own.
        gesture.begin(with: event(.leftMouseDown, x: 110, y: 65))
        expect(gesture.finish(), "a new click works after a native drag consumed mouse-up")
        print("Window drag gesture: 7 checks passed")
    }

    private static func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                          timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                          clickCount: 1, pressure: 1)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
