import AppKit
import CraCEF

/// What the hover controls do; set by BrowserManager for the tab whose video is out.
struct PictureInPictureActions {
    var backToTab: () -> Void
    var togglePlayback: () -> Void
    var skip: (Double) -> Void = { _ in }
    /// Go to this many seconds from the video's start (the scrubber).
    var seek: (Double) -> Void = { _ in }
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
/// instead on hover: back-to-tab, the page's address and close at the top,
/// play/pause with ±15 s skips in the middle (Arc's tooltips: "closes the pip window",
/// "returns to the original tab", "Skip back/ahead 15 seconds"). The overlay
/// also owns dragging and aspect-locked edge resizing.
@MainActor
final class PictureInPictureChrome {
    static let shared = PictureInPictureChrome()

    var actions: PictureInPictureActions?
    var isPlaying = false {
        didSet { for o in overlays.values { o.controls.isPlaying = isPlaying } }
    }
    /// Where the video is and how long it is, in seconds, for the scrubber (0 long: no scrubber).
    var time: (position: Double, duration: Double) = (0, 0) {
        didSet { for o in overlays.values { o.controls.setTime(position: time.position, duration: time.duration) } }
    }
    /// The page's host, centred in the top bar (Arc's; Chrome's own strip stays hidden, #246).
    var address = "" {
        didSet { for o in overlays.values { o.controls.address = address } }
    }

    static let cornerRadius: CGFloat = 6
    static let edgeMargin = PictureInPictureLayout.edgeMargin
    private static let frameKey = "CraPictureInPictureFrame"
    /// The display the frame was left on and that display's frame then (#316).
    private static let displayKey = "CraPictureInPictureDisplay"
    private static let displayFrameKey = "CraPictureInPictureDisplayFrame"

    private var overlays: [ObjectIdentifier: PictureInPictureOverlay] = [:]
    private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    private var appObservers: [NSObjectProtocol] = []

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
        overlay.controls.address = address
        overlay.controls.setTime(position: time.position, duration: time.duration)
        window.addChildWindow(overlay, ordered: .above)
        overlay.orderFront(nil)
        let center = NotificationCenter.default
        let id = ObjectIdentifier(window)
        observers[id].map { $0.forEach(center.removeObserver) }   // Chromium shows the same window again for the next video
        observers[id] = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.prune() }
            },
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak overlay, weak window] _ in
                Task { @MainActor in
                    guard let overlay, let window else { return }
                    overlay.setFrame(window.frame, display: false)
                    PictureInPictureChrome.keepFromKey(window)
                    PictureInPictureChrome.shared.remember(window.frame)
                }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak window] _ in
                Task { @MainActor in if let window { PictureInPictureChrome.shared.tookKey(window) } }
            },
        ]
        watchApp()
    }

    /// Only the overlay takes the pointer, and Chromium's window is never key: a key PiP window
    /// shows Chrome's own controls (title, ±10 s, scrubber) on every mouse move, under Arc's (#262).
    /// Chromium's window keeps a 4 pt resize band outside its frame that the overlay doesn't cover;
    /// a drag there resized it natively and made it key. `preventKeyWindow` is Chromium's own
    /// switch (NativeWidgetMacNSWindow), and Chromium writes it too: a window it orders in on
    /// another Space gets NO back once the Space changes (`orderFrontKeepWindowKeyState`). So this
    /// runs again whenever that can have happened, not once.
    static func keepFromKey(_ window: NSWindow) {
        window.ignoresMouseEvents = true
        if window.responds(to: NSSelectorFromString("setPreventKeyWindow:")) {
            window.setValue(true, forKey: "preventKeyWindow")
        }
    }

    private static func preventsKey(_ window: NSWindow) -> Bool {
        window.responds(to: NSSelectorFromString("preventKeyWindow")) && (window.value(forKey: "preventKeyWindow") as? Bool) == true
    }

    /// The moments Chromium's window can have been given the key back: Cra coming forward (AppKit
    /// picks a key window then) and a Space change (Chromium clears `preventKeyWindow` in its own
    /// observer of it, queued on the main queue like this one, so this goes after it).
    private func watchApp() {
        guard appObservers.isEmpty else { return }
        let reassert: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in PictureInPictureChrome.shared.reassert() }
        }
        let center = NotificationCenter.default
        appObservers = [
            center.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main, using: reassert),
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: reassert),
            // The task is queued behind Chromium's observer, which was queued when the post came.
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: reassert),
        ]
    }

    private func reassert() {
        for o in overlays.values { if let w = o.parent { Self.keepFromKey(w) } }
    }

    /// Chromium's window became key anyway: its controls are fading in. Say how, so a report can
    /// tell, and give the key to a Cra window (or to the app before Cra) so they go again.
    private func tookKey(_ window: NSWindow) {
        let prevented = Self.preventsKey(window)
        Self.keepFromKey(window)
        let other = NSApp.orderedWindows.first { $0 !== window && !($0 is PictureInPictureOverlay) && $0.isVisible && $0.canBecomeKey }
        CraLog.note("pip: Chromium's window became key (preventKeyWindow \(prevented ? 1 : 0), Cra \(NSApp.isActive ? "active" : "inactive")); key to \(other.map { NSStringFromClass(type(of: $0)) } ?? "the app before Cra")")
        if let other { other.makeKey() } else if NSApp.isActive { NSApp.deactivate() }
    }

    /// `cra://debug?pip=<label>`: Chromium's PiP window as Cra keeps it, and the centre controls'
    /// size for its width (#262).
    func readout() -> String {
        let shown = overlays.values.compactMap { o in o.parent.map { (o, $0) } }
        guard !shown.isEmpty else { return "windows=0" }
        return "windows=\(shown.count) " + shown.map { o, w in
            "key=\(w.isKeyWindow ? 1 : 0) appKey=\(NSApp.keyWindow === w ? 1 : 0) mouse=\(w.ignoresMouseEvents ? 0 : 1) preventKey=\(Self.preventsKey(w) ? 1 : 0) width=\(Int(w.frame.width)) \(o.controls.readout) frame=\(Int(w.frame.minX)),\(Int(w.frame.minY)),\(Int(w.frame.width)),\(Int(w.frame.height)) onScreen=\(PictureInPictureLayout.landing(afterDropping: w.frame, displays: NSScreen.screens.map(Self.display)) == nil ? 1 : 0)"
        }.joined(separator: " | ")
    }

    /// `cra://debug?pipDrop=left|right|top|bottom`: the window moved half past that edge of its
    /// display and let go there, as a mouse drag does (#332).
    func debugDrop(_ edge: String) {
        for o in overlays.values {
            guard let w = o.parent, let screen = w.screen?.frame, let view = o.contentView as? PictureInPictureOverlayView else { continue }
            var origin = w.frame.origin
            switch edge {
            case "left": origin.x = screen.minX - w.frame.width / 2
            case "top": origin.y = screen.maxY - w.frame.height / 2
            case "bottom": origin.y = screen.minY - w.frame.height / 2
            default: origin.x = screen.maxX - w.frame.width / 2
            }
            w.setFrameOrigin(origin)
            view.dropped()
        }
    }

    /// `cra://debug?pipSeek=<0…1>`: the scrubber pressed that far along and let go.
    func debugSeek(_ fraction: Double) {
        for o in overlays.values { o.controls.debugScrub(CGFloat(fraction)) }
    }

    /// `cra://debug?pipClick=<n>`: the overlay pressed and let go in its lower left quarter (clear
    /// of the buttons) as the last click of `n` quick ones, the way AppKit sends a double click.
    func debugClick(_ count: Int) {
        for o in overlays.values {
            guard let view = o.contentView as? PictureInPictureOverlayView else { continue }
            let at = NSPoint(x: o.frame.width / 4, y: o.frame.height / 4)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: o.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) else { continue }
                if type == .leftMouseDown { view.mouseDown(with: e) } else { view.mouseUp(with: e) }
            }
        }
    }

    /// `cra://debug?pipKey=space|force`: Chromium's window asked to become key the ways Chromium's
    /// own code can leave it open to that. `space`: `preventKeyWindow` back to NO by a Space change,
    /// as NativeWidgetMacNSWindow does after `orderFrontKeepWindowKeyState`; `force`: cleared and
    /// made key at once, standing in for a path not known yet.
    func debugTakeKey(_ how: String) {
        for o in overlays.values {
            guard let w = o.parent else { continue }
            w.setValue(false, forKey: "preventKeyWindow")
            if how == "space" {
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    w.makeKeyAndOrderFront(nil)
                }
            } else {
                w.makeKeyAndOrderFront(nil)
            }
        }
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
        Self.keepFromKey(window)
        // Over another app's full-screen Space too, like Arc's (#206). The overlay copies this below.
        CraCEFRuntime.floatOverFullScreenSpaces(window)
        if let cv = window.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = Self.cornerRadius
            cv.layer?.cornerCurve = .continuous
            cv.layer?.masksToBounds = true
        }
        let aspect = window.frame.width / max(window.frame.height, 1)
        window.setFrame(initialFrame(aspect: aspect, screen: window.screen ?? NSScreen.main), display: true)
        window.invalidateShadow()
        // Chrome's own title strip (favicon, host, top scrim) stays hidden because CraCEF starts
        // Chromium with every video PiP trusted (VideoPipForceTrustedForMediaPlaybackForTesting,
        // #246); without that it stayed until a click reached this window, which never happens.
    }

    /// Last frame the user left the window at, on the display it was left on (#316), else Arc's
    /// default on `screen` (PictureInPictureLayout).
    func initialFrame(aspect: CGFloat, screen: NSScreen?) -> NSRect {
        let current = screen.map(Self.display) ?? .init(id: nil, frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                                                         visible: NSRect(x: 0, y: 0, width: 1728, height: 1084))
        let defaults = UserDefaults.standard
        let remembered = defaults.string(forKey: Self.frameKey).map(NSRectFromString).map {
            PictureInPictureLayout.Placement(frame: $0, display: defaults.string(forKey: Self.displayKey),
                                             displayFrame: defaults.string(forKey: Self.displayFrameKey).map(NSRectFromString))
        }
        let displays = NSScreen.screens.map(Self.display)
        let frame = PictureInPictureLayout.initialFrame(aspect: aspect, displays: displays, current: current, remembered: remembered)
        let on = displays.firstIndex { $0.frame.intersects(frame) }.map { "display \($0 + 1)/\(displays.count)" } ?? "no display"
        CraLog.note("pip: opens at \(Int(frame.width))×\(Int(frame.height)) on \(on)\(remembered == nil ? "" : " (remembered)")")
        return frame
    }

    func remember(_ frame: NSRect) {
        let defaults = UserDefaults.standard
        defaults.set(NSStringFromRect(frame), forKey: Self.frameKey)
        // The display most of the window is on, as AppKit's `screen` picks it.
        let screen = NSScreen.screens.max { PictureInPictureChrome.overlap($0.frame, frame) < PictureInPictureChrome.overlap($1.frame, frame) }
        if let screen, let id = Self.display(screen).id {
            defaults.set(id, forKey: Self.displayKey)
            defaults.set(NSStringFromRect(screen.frame), forKey: Self.displayFrameKey)
        } else {
            defaults.removeObject(forKey: Self.displayKey)
            defaults.removeObject(forKey: Self.displayFrameKey)
        }
    }

    private static func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// A display by its UUID, which stays the same across launches, reconnects and rearranging.
    static func display(_ screen: NSScreen) -> PictureInPictureLayout.Display {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let id = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            .flatMap { CFUUIDCreateString(nil, $0) as String? }
        return .init(id: id, frame: screen.frame, visible: screen.visibleFrame)
    }

    private func prune() {
        for (id, overlay) in overlays where overlay.parent == nil || overlay.parent?.isVisible != true {
            overlay.parent?.removeChildWindow(overlay)
            overlay.orderOut(nil)
            overlays[id] = nil
            observers.removeValue(forKey: id)?.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

/// Transparent window over Chromium's PiP window: swallows the pointer so
/// Chrome's controls never show, and turns drags into moves and edge drags
/// into aspect-locked resizes of the window underneath.
///
/// A non-activating panel, like Arc's PiP: it stays on another app's full-screen
/// Space with Chromium's window (#206), and a click on it doesn't bring Cra
/// forward (which would leave that Space). Back to tab activates Cra itself.
final class PictureInPictureOverlay: NSPanel {
    init(over target: NSWindow) {
        super.init(contentRect: target.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        // Arc's limits (#246): 224 × 126 for a 16:9 video at least, 61.7 % of the screen's width and
        // the visible height less 20 at most.
        let screen = target.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? target.frame
        let limits = PictureInPictureLayout.sizeLimits(aspect: g.startFrame.width / max(g.startFrame.height, 1),
                                                       screen: screen?.frame ?? visible, visible: visible)
        let constraints = target.contentMaxSize
        let maxSize = NSSize(width: min(constraints.width, limits.max.width), height: min(constraints.height, limits.max.height))
        let minSize = NSSize(width: max(target.contentMinSize.width, limits.min.width), height: max(target.contentMinSize.height, limits.min.height))
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
        guard g.isDragging else {
            // A double click on the video goes back to its tab, as in Arc.
            if event.type == .leftMouseUp, g.returnsToTab(clickCount: event.clickCount) {
                CraLog.note("pip: double click, back to tab")
                PictureInPictureChrome.shared.actions?.backToTab()
            }
            return
        }
        if g.edge != .none {
            // Chromium owns the window's bounds; say so if it kept another size than the one asked.
            let asked = requested.map { $0.size == target.frame.size ? "" : " (asked \(Self.size($0)))" } ?? ""
            CraLog.note("pip: resized \(g.edge) \(Self.size(g.startFrame)) → \(Self.size(target.frame))\(asked)")
            requested = nil
            PictureInPictureChrome.shared.remember(target.frame)
        } else {
            dropped()
        }
    }

    /// The mouse let the moved window go. Partly past the screen's edge, it flies into the
    /// nearest corner on the swipe's spring, as Arc's does, and that corner is kept for the next
    /// video when it lands (#332); otherwise the spot it was let go at is.
    func dropped() {
        guard let target else { return }
        guard let landing = PictureInPictureLayout.landing(afterDropping: target.frame, displays: NSScreen.screens.map(PictureInPictureChrome.display)) else {
            return PictureInPictureChrome.shared.remember(target.frame)
        }
        CraLog.note("pip: dropped past the edge, to \(landing.corner.rawValue)")
        flight = PictureInPictureFlight(from: target.frame.origin, velocity: .zero, to: landing.frame.origin)
        startLink()
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
