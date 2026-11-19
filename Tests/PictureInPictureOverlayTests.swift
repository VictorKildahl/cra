import AppKit

/// The Picture in Picture overlay as the trackpad drives it: the real overlay window and view over
/// a stand-in for Chromium's window, handed events made the way the window server makes them (a
/// gesture CGEvent AppKit reads as a magnify, a continuous scroll with its phase) through the
/// window's own `sendEvent`, so AppKit routes them to the view as it routes a trackpad's
/// (`TestGesture`, which `cra://debug?pipPinch` uses too). No CEF: CraCEF and the rest of the
/// app are stubbed (Tests/PictureInPictureSupport).
@main
enum PictureInPictureOverlayTests {
    private static var checks = 0
    private typealias Phase = TestGesture.TrackpadPhase

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        aPinchOnItsOwnResizes()
        aPinchAfterRestingFingersResizes()
        aPinchTheAppIsHandedResizes()
        restingFingersThatDontPinchLeaveTheWindow()
        print("Picture in Picture overlay: \(checks) checks passed")
    }

    /// A pinch with no other event around it: the window grows in the video's shape and the size
    /// is kept for the next video (#534).
    @MainActor
    private static func aPinchOnItsOwnResizes() {
        let (target, overlay) = pip()
        let start = target.frame
        send(magnify(.began), to: overlay)
        for _ in 0..<3 { send(magnify(.changed, 0.1), to: overlay) }
        send(magnify(.ended), to: overlay)
        expect(target.frame.width == (start.width * 1.331).rounded(), "pinched open 1.331×: \(start.size) → \(target.frame.size)")
        expect(abs(target.frame.width / target.frame.height - 16.0 / 9) < 0.01, "kept 16:9: \(target.frame.size)")
        expect(remembered() == target.frame, "the size is kept for the next video")
        close(target, overlay)
    }

    // promise: #573
    /// A pinch as a trackpad can send it: two fingers touch down (a scroll that may begin, a magnify
    /// that may begin), the pinch, and only at the lift the scroll's cancel. 0.1.49 gave the window
    /// to a swipe at touch-down and the pinch never got it: the window kept its size. The old
    /// `cra://debug?pipPinch` called the pinch's code straight and never sent that scroll.
    @MainActor
    private static func aPinchAfterRestingFingersResizes() {
        let (target, overlay) = pip()
        let start = target.frame
        forget()
        send(scroll(.mayBegin), to: overlay)
        send(magnify(.mayBegin), to: overlay)
        send(magnify(.began), to: overlay)
        for _ in 0..<3 { send(magnify(.changed, 0.1), to: overlay) }
        expect(target.frame.width == (start.width * 1.331).rounded(), "follows the fingers while they pinch: \(start.size) → \(target.frame.size)")
        send(magnify(.ended), to: overlay)
        send(scroll(.cancelled), to: overlay)
        expect(target.frame.width == (start.width * 1.331).rounded(), "pinched open 1.331× after resting fingers: \(start.size) → \(target.frame.size)")
        expect(abs(target.frame.midX - start.midX) <= 1 && abs(target.frame.midY - start.midY) <= 1, "grew around its centre: \(start) → \(target.frame)")
        expect(remembered() == target.frame, "the pinched size is kept for the next video")
        // The debug hook's pinch, the same sequence: nothing was left holding the window.
        let open = target.frame
        TestGesture.pinch([-0.2], at: middle(of: overlay), in: overlay)
        expect(target.frame.width == (open.width * 0.8).rounded(), "cra://debug?pipPinch's pinch closes it: \(open.size) → \(target.frame.size)")
        close(target, overlay)
    }

    // promise: #573
    /// A pinch as the window server hands it to the app: the magnify events addressed to the
    /// overlay's window and sent through the app (`NSApp.sendEvent`), the fingers' scrolls to the
    /// view under them. In a probe the view's `magnify(with:)` never saw such events, the app's event
    /// monitors did; the overlay takes them there. This is the path `cra://debug?pipPinch` takes.
    @MainActor
    private static func aPinchTheAppIsHandedResizes() {
        let (target, overlay) = pip()
        let start = target.frame
        forget()
        TestGesture.pinch([0.1, 0.1, 0.1], at: middle(of: overlay), in: overlay)
        expect(target.frame.width == (start.width * 1.331).rounded(), "a pinch the app is handed opens it 1.331×: \(start.size) → \(target.frame.size)")
        expect(remembered() == target.frame, "and the size is kept")
        // A magnify addressed to another window is left to that window.
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let opened = target.frame
        for phase in [Phase.began, .changed, .ended] {
            TestGesture.trackpadMagnify(phase, by: 0.5, at: .zero, to: other).map(NSApp.sendEvent)
        }
        expect(target.frame == opened, "another window's pinch leaves it: \(target.frame)")
        other.close()
        close(target, overlay)
    }

    /// Fingers that touch down and lift without pinching or moving leave the window where and as
    /// it was, and keep nothing.
    @MainActor
    private static func restingFingersThatDontPinchLeaveTheWindow() {
        let (target, overlay) = pip()
        let start = target.frame
        forget()
        send(scroll(.mayBegin), to: overlay)
        send(magnify(.mayBegin), to: overlay)
        send(magnify(.cancelled), to: overlay)
        send(scroll(.cancelled), to: overlay)
        expect(target.frame == start, "resting fingers leave the window: \(start) → \(target.frame)")
        expect(remembered() == nil, "and keep nothing")
        close(target, overlay)
    }

    // MARK: Helpers

    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// Chromium's window's stand-in, 448 × 252 in the middle of the main display's visible frame
    /// (pinches keep it inside), with the overlay as its child as the app lays it. AppKit hands a
    /// magnify only to a window that is ordered in, so both are, but fully transparent and
    /// click-through: nothing shows and the pointer goes past them.
    @MainActor
    private static func pip() -> (NSWindow, PictureInPictureOverlay) {
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let frame = NSRect(x: (v.midX - 224).rounded(), y: (v.midY - 126).rounded(), width: 448, height: 252)
        let target = OffscreenWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        target.level = .floating
        let overlay = PictureInPictureOverlay(over: target)
        for w in [target, overlay] as [NSWindow] {
            w.alphaValue = 0
            w.ignoresMouseEvents = true
        }
        target.orderFrontRegardless()
        target.addChildWindow(overlay, ordered: .above)
        overlay.orderFrontRegardless()
        expect(overlay.isVisible && overlay.alphaValue == 0 && target.alphaValue == 0, "ordered in, invisible")
        return (target, overlay)
    }

    @MainActor
    private static func close(_ target: NSWindow, _ overlay: NSWindow) {
        target.removeChildWindow(overlay)
        overlay.close()
        target.close()
    }

    /// The frame the overlay kept for the next video (`PictureInPictureChrome.remember`), in the
    /// test's data folder.
    private static func remembered() -> NSRect? {
        (NSDictionary(contentsOf: AppPaths.file("pip-placement.plist"))?["CraPictureInPictureFrame"] as? String).map(NSRectFromString)
    }

    private static func forget() {
        try? FileManager.default.removeItem(at: AppPaths.file("pip-placement.plist"))
    }

    @MainActor
    private static func middle(of overlay: NSWindow) -> NSPoint {
        NSPoint(x: overlay.frame.width / 2, y: overlay.frame.height / 2)
    }

    @MainActor private static var at = NSPoint.zero
    @MainActor private static func magnify(_ phase: Phase, _ m: Double = 0) -> NSEvent? { TestGesture.trackpadMagnify(phase, by: m, at: at) }
    @MainActor private static func scroll(_ phase: Phase) -> NSEvent? { TestGesture.trackpadScroll(phase, at: at) }

    /// The event through the overlay window's `sendEvent`, at the overlay's middle.
    @MainActor
    private static func send(_ make: @autoclosure () -> NSEvent?, to overlay: NSWindow) {
        at = middle(of: overlay)
        guard let e = make() else { return expect(false, "AppKit reads the event") }
        expect(e.type == .magnify || e.type == .scrollWheel, "a trackpad event to AppKit: type \(e.type.rawValue)")
        let hit = overlay.contentView?.superview?.hitTest(e.locationInWindow)
        expect(hit.map { $0.isDescendant(of: overlay.contentView!) } == true, "the event lands on the overlay: \(e.locationInWindow)")
        overlay.sendEvent(e)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
