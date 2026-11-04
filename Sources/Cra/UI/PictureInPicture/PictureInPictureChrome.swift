import AppKit

/// What the hover controls do; set by BrowserManager for the tab whose video is out.
struct PictureInPictureActions {
    var backToTab: () -> Void
    var togglePlayback: () -> Void
    var skip: (Double) -> Void = { _ in }
    var close: () -> Void
}

/// Arc's Picture in Picture window, reproduced over Chromium's.
///
/// Chromium renders the popped-out video in its own floating NSWindow and
/// draws Chrome's hover controls (title bar, ±10 s, scrubber…) inside it.
/// Cra keeps Chromium's window for the pixels and reshapes it the way Arc's
/// looks: a shadowed 16:9 window with 6 pt continuous corners, first shown in
/// the top-right corner, remembered where the user leaves it (measured on Arc
/// 1.168, see docs/arc-reverse-engineering.md). A transparent child window
/// over it keeps the pointer away from Chrome's controls and draws Arc's
/// instead on hover: close and back-to-tab at the top, play/pause with
/// ±15 s skips in the middle (Arc's tooltips: "closes the pip window",
/// "returns to the original tab", "Skip back/ahead 15 seconds"). The overlay
/// also owns dragging and aspect-locked edge resizing.
@MainActor
final class PictureInPictureChrome {
    static let shared = PictureInPictureChrome()

    var actions: PictureInPictureActions?
    var isPlaying = false {
        didSet { for o in overlays.values { o.controls.isPlaying = isPlaying } }
    }

    /// Arc on a 1728×1117 display: 782×440 for a 16:9 video, 10 pt from the
    /// top and right edges of the visible frame.
    static let cornerRadius: CGFloat = 6
    static let edgeMargin: CGFloat = 10
    static let defaultHeightFraction: CGFloat = 440.0 / 1084.0
    private static let frameKey = "CraPictureInPictureFrame"

    private var overlays: [ObjectIdentifier: PictureInPictureOverlay] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// A video entered Picture in Picture; Chromium's window exists or is about to.
    func videoEntered() { adopt(attempt: 0) }

    /// The video left; Chromium closes its window, the overlay follows it.
    func videoLeft() { prune() }

    private func adopt(attempt: Int) {
        guard let window = chromiumWindow() else {
            if attempt < 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.adopt(attempt: attempt + 1) }
            }
            return
        }
        style(window)
        let overlay = PictureInPictureOverlay(over: window)
        overlays[ObjectIdentifier(window)] = overlay
        overlay.controls.isPlaying = isPlaying
        window.addChildWindow(overlay, ordered: .above)
        overlay.orderFront(nil)
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak overlay, weak window] _ in
            Task { @MainActor in
                guard let overlay, let window else { return }
                overlay.setFrame(window.frame, display: false)
                PictureInPictureChrome.shared.remember(window.frame)
            }
        })
    }

    /// Chromium's PiP widget: a floating NativeWidgetMac window titled
    /// "Picture in Picture", neither one of ours nor CEF's CefNSWindow.
    private func chromiumWindow() -> NSWindow? {
        NSApp.windows.first { w in
            guard w.isVisible, w.level == .floating, overlays[ObjectIdentifier(w)] == nil, !(w is PictureInPictureOverlay) else { return false }
            let cls = NSStringFromClass(type(of: w))
            return cls.hasPrefix("NativeWidgetMac") || w.title == "Picture in Picture"
        }
    }

    private func style(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        // Only the overlay takes the pointer. Chrome's window keeps a 4 pt resize band outside
        // its frame (NativeWidgetMacNSWindow) that the overlay doesn't cover: a drag there
        // resized it natively and made it key, and a key PiP window shows Chrome's own controls
        // (±10 s) on every mouse move, under Arc's. It also must not become key when a click
        // on the overlay activates Cra.
        window.ignoresMouseEvents = true
        if window.responds(to: NSSelectorFromString("setPreventKeyWindow:")) {
            window.setValue(true, forKey: "preventKeyWindow")
        }
        if let cv = window.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = Self.cornerRadius
            cv.layer?.cornerCurve = .continuous
            cv.layer?.masksToBounds = true
        }
        let aspect = window.frame.width / max(window.frame.height, 1)
        window.setFrame(initialFrame(aspect: aspect, screen: window.screen ?? NSScreen.main), display: true)
        window.invalidateShadow()
        // Chrome still paints its title strip ("File on your device") for the
        // first seconds after the window appears; that lives inside Chromium's
        // compositor layer and is not reachable from here (neither resizing
        // nor focus changes affect it). After that the window is Arc's.
    }

    /// Last frame the user left the window at (Arc's "absolute" placement),
    /// else Arc's default: top-right corner of the visible frame.
    func initialFrame(aspect: CGFloat, screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1728, height: 1084)
        if let s = UserDefaults.standard.string(forKey: Self.frameKey) {
            let r = NSRectFromString(s)
            if !r.isEmpty, visible.intersects(r) {
                // Keep the remembered width, follow the video's aspect ratio.
                let h = (r.width / aspect).rounded()
                return NSRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
            }
        }
        let h = (visible.height * Self.defaultHeightFraction).rounded()
        let w = (h * aspect).rounded()
        return NSRect(x: visible.maxX - Self.edgeMargin - w, y: visible.maxY - Self.edgeMargin - h, width: w, height: h)
    }

    func remember(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    private func prune() {
        for (id, overlay) in overlays where overlay.parent == nil || overlay.parent?.isVisible != true {
            overlay.parent?.removeChildWindow(overlay)
            overlay.orderOut(nil)
            overlays[id] = nil
        }
    }
}

/// Transparent window over Chromium's PiP window: swallows the pointer so
/// Chrome's controls never show, and turns drags into moves and edge drags
/// into aspect-locked resizes of the window underneath.
final class PictureInPictureOverlay: NSWindow {
    init(over target: NSWindow) {
        super.init(contentRect: target.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = target.level
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = target.collectionBehavior
        let root = PictureInPictureOverlayView(frame: NSRect(origin: .zero, size: target.frame.size))
        root.autoresizesSubviews = true
        controls.frame = root.bounds
        controls.autoresizingMask = [.width, .height]
        root.addSubview(controls)
        contentView = root
        acceptsMouseMovedEvents = true
    }

    let controls = PictureInPictureControlsView(frame: .zero)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PictureInPictureOverlayView: NSView {
    private typealias Edge = PictureInPictureGesture.Edge
    private var gesture: PictureInPictureGesture?
    private var requested: NSRect?

    private var target: NSWindow? { window?.parent }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The cursor follows the same edge zones as a press. Cursor rects don't do: AppKit applies
    // them to a key window, and this one never becomes key, so corners came and went (#134).
    // While the pointer is over the window Cra may set it from the background as well, so the
    // resize cursor shows with another app in front, as it does over any window's edge.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    private func updateCursor(_ event: NSEvent) {
        guard gesture == nil else { return }
        let edge = PictureInPictureGesture.edge(at: convert(event.locationInWindow, from: nil), in: bounds.size)
        (edge == .none ? NSCursor.arrow : Self.cursor(edge)).set()
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) {
        BackgroundCursor.allow(true)
        updateCursor(event)
    }
    override func mouseExited(with event: NSEvent) {
        guard gesture == nil else { return }
        NSCursor.arrow.set()
        BackgroundCursor.allow(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            BackgroundCursor.allow(false)
            stopLink()
            swipe = nil
            flight = nil
            releasePointer()
        }
    }

    /// The resize cursor for an edge or corner; AppKit has diagonal ones from macOS 15.
    private static func cursor(_ edge: Edge) -> NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch edge {
            case .left: .left
            case .right: .right
            case .top: .top
            case .bottom: .bottom
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight, .none: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        return edge == .top || edge == .bottom ? .resizeUpDown : .resizeLeftRight
    }

    override func mouseDown(with event: NSEvent) {
        guard let target else {
            CraLog.note("pip: overlay has no parent window")
            return
        }
        land()
        swipe = nil
        releasePointer()
        stopLink()
        gesture = PictureInPictureGesture(mouse: Self.screenLocation(of: event), frame: target.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let target, var g = gesture else { return }
        // The button was let go without a mouse-up reaching this window.
        if NSEvent.pressedMouseButtons & 1 == 0 { finish(event); return }
        let constraints = target.contentMaxSize
        let visible = target.screen?.visibleFrame.size ?? constraints
        let maxSize = NSSize(width: min(constraints.width, visible.width - 2 * PictureInPictureChrome.edgeMargin),
                             height: min(constraints.height, visible.height - 2 * PictureInPictureChrome.edgeMargin))
        let minSize = NSSize(width: max(target.contentMinSize.width, 160), height: max(target.contentMinSize.height, 90))
        let wasDragging = g.isDragging
        let frame = g.frame(mouse: Self.screenLocation(of: event), minSize: minSize, maxSize: maxSize)
        gesture = g
        guard let frame else { return }
        if !wasDragging { CraLog.note(g.edge == .none ? "pip: move" : "pip: resize \(g.edge) from \(Self.size(g.startFrame))") }
        if g.edge == .none {
            target.setFrameOrigin(frame.origin)
        } else {
            // Cursor rects only describe the pointer before the press; keep the resize cursor
            // for the whole drag, also when the pointer runs ahead of the edge.
            Self.cursor(g.edge).set()
            requested = frame
            target.setFrame(frame, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) { finish(event) }

    private func finish(_ event: NSEvent) {
        guard let target, let g = gesture else { return }
        gesture = nil
        if let window, !window.frame.contains(NSEvent.mouseLocation) {
            // Let go outside the window: its exit came during the drag.
            NSCursor.arrow.set()
            BackgroundCursor.allow(false)
        } else {
            updateCursor(event)
        }
        guard g.isDragging else { return }
        if g.edge != .none {
            // Chromium owns the window's bounds; say so if it kept another size than the one asked.
            let asked = requested.map { $0.size == target.frame.size ? "" : " (asked \(Self.size($0)))" } ?? ""
            CraLog.note("pip: resized \(g.edge) \(Self.size(g.startFrame)) → \(Self.size(target.frame))\(asked)")
            requested = nil
        }
        PictureInPictureChrome.shared.remember(target.frame)
    }

    /// Where on the screen the event happened. The window moves and resizes under the pointer, so
    /// not its window location, and not `NSEvent.mouseLocation`, which is wherever the pointer is
    /// by the time the event is handled.
    private static func screenLocation(of event: NSEvent) -> NSPoint {
        guard let p = event.cgEvent?.location, let primary = NSScreen.screens.first else { return NSEvent.mouseLocation }
        return NSPoint(x: p.x, y: primary.frame.maxY - p.y)
    }

    private static func size(_ r: NSRect) -> String { "\(Int(r.width))×\(Int(r.height))" }

    // The pointer never reaches Chromium (its own controls stay hidden); the
    // controls subview shows Arc's on hover.
    override func mouseMoved(with event: NSEvent) {
        if gesture != nil { finish(event) } else { updateCursor(event) }   // a move means no button is down: the mouse-up got lost
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}

    // MARK: Swipe to a corner (Arc)

    private var swipe: PictureInPictureThrow?
    private var flight: PictureInPictureFlight?
    /// Runs while the fingers are on the window and while it flies: the window moves once per
    /// screen refresh, never straight from a scroll event.
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    /// Where the pointer sits in the window while it rides along with the fingers.
    private var carried: CGVector?

    /// Two fingers on the trackpad (or a Magic Mouse) move the window with them, and when they
    /// lift it flies on into the corner of the screen it was heading for, as Arc's does. A wheel
    /// without phases (a plain mouse) moves nothing, and AppKit's own momentum after the lift is
    /// left out: the flight is the momentum. Scroll events only record where the fingers are;
    /// `tick` shows the window there, a frame at a time (see `PictureInPictureThrow.origin(at:)`).
    override func scrollWheel(with event: NSEvent) {
        guard gesture == nil, let target, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        let t = event.timestamp
        switch event.phase {
        case .mayBegin, .began:
            land()
            swipe = PictureInPictureThrow(frame: target.frame, at: t)
            startLink()
        case .changed:
            if swipe == nil {
                land()
                swipe = PictureInPictureThrow(frame: target.frame, at: t)
                startLink()
            }
            // The window goes where the fingers go: with natural scrolling the deltas already
            // follow them, without it they're the other way round.
            let toFingers: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            _ = swipe?.move(dx: toFingers * event.scrollingDeltaX, dy: -toFingers * event.scrollingDeltaY, at: t)
        case .ended, .cancelled:
            guard let s = swipe else { return }
            swipe = nil
            releasePointer()
            guard s.hasMoved else { return stopLink() }
            throwWindow(target, aim: s.frame, velocity: event.phase == .ended ? s.velocity(at: t) : .zero)
        default:
            break
        }
    }

    /// The fingers lifted with the window shown at its own frame and aimed at `aim` (where the
    /// fingers had it): it flies on from where it is shown, at their speed, so the hand-off is seamless.
    private func throwWindow(_ target: NSWindow, aim: NSRect, velocity: CGVector) {
        let rest = PictureInPictureThrow.restingCentre(of: aim, velocity: velocity)
        let screen = NSScreen.screens.first { $0.frame.contains(rest) } ?? target.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return stopLink() }
        let corner = PictureInPictureThrow.corner(for: aim, velocity: velocity, in: visible)
        let end = PictureInPictureThrow.frame(in: corner, size: aim.size, visible: visible, margin: PictureInPictureChrome.edgeMargin)
        CraLog.note("pip: swipe to \(corner.rawValue) at \(Int(hypot(velocity.dx, velocity.dy))) pt/s")
        flight = PictureInPictureFlight(from: target.frame.origin, velocity: velocity, to: end.origin)
        startLink()
    }

    /// Scroll events go to the window under the pointer, so once the window slid out from under
    /// it the fingers moved whatever was behind instead. As in Arc, the pointer hides when the
    /// window starts to move and rides along at its spot in the window until the fingers lift.
    private func carryPointer(from old: CGPoint, to origin: CGPoint) {
        if carried == nil {
            let m = NSEvent.mouseLocation
            carried = CGVector(dx: m.x - old.x, dy: m.y - old.y)
            NSCursor.hide()
        }
        guard let c = carried, let primary = NSScreen.screens.first else { return }
        CGWarpMouseCursorPosition(CGPoint(x: origin.x + c.dx, y: primary.frame.maxY - (origin.y + c.dy)))
        // A warp holds the pointer's own moves back for a quarter of a second; this lifts the hold.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func releasePointer() {
        guard carried != nil else { return }
        carried = nil
        NSCursor.unhide()
    }

    private func startLink() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTick = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTick == 0 ? link.targetTimestamp - link.timestamp : link.timestamp - lastTick
        lastTick = link.timestamp
        guard let target else { return stopLink() }
        if let s = swipe {
            let origin = s.origin(at: link.timestamp)
            guard origin != target.frame.origin else { return }
            carryPointer(from: target.frame.origin, to: origin)
            target.setFrameOrigin(origin)
            return
        }
        guard var f = flight else { return stopLink() }
        target.setFrameOrigin(f.step(max(dt, 1.0 / 240)))
        flight = f
        if f.isSettled { land() }
    }

    /// Ends a flight where the window is (a new swipe or press catches it mid-air) and keeps the
    /// spot for the next video.
    private func land() {
        guard flight != nil else { return }
        flight = nil
        if swipe == nil { stopLink() }
        if let target { PictureInPictureChrome.shared.remember(target.frame) }
    }
}

/// Lets Cra set the cursor while another app is in front. macOS only takes the frontmost app's
/// cursor, so without this the Picture in Picture window, which floats over every app, shows no
/// resize cursor unless Cra is active. On only while the pointer is over that window. Private
/// WindowServer API (`CGSSetConnectionProperty`, "SetsCursorInBackground"); a no-op if it's gone.
@MainActor
enum BackgroundCursor {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private static let calls: (MainConnection, SetProperty)? = {
        let any = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        guard let main = dlsym(any, "CGSMainConnectionID"), let set = dlsym(any, "CGSSetConnectionProperty") else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(set, to: SetProperty.self))
    }()
    private static var isAllowed = false

    static func allow(_ on: Bool) {
        guard on != isAllowed, let calls else { return }
        isAllowed = on
        let cid = calls.0()
        _ = calls.1(cid, cid, "SetsCursorInBackground" as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }
}
