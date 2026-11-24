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
    /// Arc's Minimize: out of Picture in Picture with the video playing on in its tab, which
    /// stays where it is; the sidebar player then has it (#434).
    var minimize: () -> Void = {}
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

    static let cornerRadius = PictureInPictureLayout.cornerRadius
    static let edgeMargin = PictureInPictureLayout.edgeMargin
    private static let frameKey = "CraPictureInPictureFrame"
    /// The display the frame was left on and that display's frame then (#316).
    private static let displayKey = "CraPictureInPictureDisplay"
    private static let displayFrameKey = "CraPictureInPictureDisplayFrame"

    private var overlays: [ObjectIdentifier: PictureInPictureOverlay] = [:]

    // MARK: In front for the window (#741)

    /// macOS gives a trackpad pinch only to the app in front, and Arc's window resizes on a pinch once a click on it has
    /// brought Arc forward: a press on Cra's brings Cra forward too (PictureInPictureFront), its browser windows left
    /// where they were.
    private var front = PictureInPictureFront()
    /// A click or a key in another of Cra's windows while it is in front for the window: the user is using Cra.
    private var frontUseMonitor: Any?

    /// Cra is in front for the window only: a browser window that took the keyboard meanwhile (AppKit gives it back as
    /// Cra comes forward) isn't in use, and an automatic Picture in Picture's video stays out.
    var isInFrontForWindow: Bool { front.inFrontForWindow }

    /// The browser windows' part as Cra comes forward for the window, set by AppDelegate (scripts/test-pip-overlay.sh
    /// has none): called just before the activation, it returns what to call as the activation lands, `last` on the
    /// final call.
    var browserWindowsComingForward: (() -> (_ last: Bool) -> Void)?

    /// A press on `overlay` (its video or its controls), before the press does what it does.
    func pressed(on overlay: PictureInPictureOverlay) {
        guard front.pressed(craActive: NSApp.isActive) == .comeForward else { return }
        CraLog.note("pip: a press on the window brings Cra forward (#741)")
        // A test copy behind the user's apps never takes the front (HitchMonitor.background): it says it would.
        guard !HitchMonitor.background else { return front.craLeft() }
        // The overlay is made key only after the activation: a panel made key before made AppKit count Cra as active
        // while the window server didn't, and the activation did nothing.
        overlay.takesKeyForGesture = true
        let landed = browserWindowsComingForward?()
        NSApp.activate(ignoringOtherApps: true)
        for delay in [0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak overlay] in
                if let overlay, NSApp.isActive, PictureInPictureChrome.shared.isInFrontForWindow, !overlay.isKeyWindow { overlay.makeKey() }
                landed?(delay == 0.4)
            }
        }
        if frontUseMonitor == nil {
            frontUseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
                MainActor.assumeIsolated {
                    let w = event.window
                    if !(w is PictureInPictureOverlay), !(w.map { PictureInPictureChrome.shared.overlays[ObjectIdentifier($0)] != nil } ?? false) {
                        PictureInPictureChrome.shared.endFront { $0.craUsed() }
                    }
                }
                return event
            }
        }
    }

    /// Cra is no longer in front for the window only: the user is using it, or it went behind.
    private func endFront(_ change: (inout PictureInPictureFront) -> Void) {
        guard front.inFrontForWindow else { return }
        change(&front)
        for o in overlays.values { o.takesKeyForGesture = false }
        frontUseMonitor.map(NSEvent.removeMonitor)
        frontUseMonitor = nil
    }


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
        // The size style() gave the window is Cra's, for when Chromium cuts it down later.
        (overlay.contentView as? PictureInPictureOverlayView)?.undoChromiumCap()
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
                    if (overlay.contentView as? PictureInPictureOverlayView)?.undoChromiumCap() == true { return }
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
        // Chromium's view tracks the pointer over a floating window whatever is in front of it
        // (an always-active tracking area, crbug.com/1214013), and `ignoresMouseEvents` doesn't
        // take the area away. Its mouse-entered and -moved events fade Chrome's own controls in,
        // and on hover they showed behind Arc's (#535, macOS 27.3; on macOS 26 AppKit passes the
        // window the events but not that area). Without the area that view can't hear the
        // pointer at all. Chromium only adds it again when the window's level changes or its view
        // moves to another window; in between, the seal (#460) drops what still reaches the window.
        for area in hoverTracking(window) { area.view.removeTrackingArea(area.area) }
    }

    /// Chromium's tracking areas in its PiP window that hear the pointer come, move and go.
    private static func hoverTracking(_ window: NSWindow) -> [(view: NSView, area: NSTrackingArea)] {
        guard let content = window.contentView else { return [] }
        var found: [(view: NSView, area: NSTrackingArea)] = []
        var views = [content]
        while let view = views.popLast() {
            views += view.subviews
            found += view.trackingAreas.filter { PictureInPictureLayout.hearsPointer(trackingOptions: $0.options.rawValue) }.map { (view, $0) }
        }
        return found
    }

    /// Whether Chromium's view has the pointer over it by its own account (BaseView's `_mouseInside`,
    /// which its mouse-entered and -moved handlers set): 1 or 0, -1 when Chromium has no such field.
    private static func chromiumHearsPointer(_ window: NSWindow) -> Int {
        guard let view = window.contentView else { return -1 }
        var cls: AnyClass? = type(of: view)
        while let c = cls {
            if let ivar = class_getInstanceVariable(c, "_mouseInside") {
                return Unmanaged.passUnretained(view).toOpaque().load(fromByteOffset: ivar_getOffset(ivar), as: UInt8.self) == 0 ? 0 : 1
            }
            cls = class_getSuperclass(c)
        }
        return -1
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
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in PictureInPictureChrome.shared.endFront { $0.craLeft() } }
            },
            // The task is queued behind Chromium's observer, which was queued when the post came.
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: reassert),
            // A display was unplugged, added or resized: the window goes back onto one display.
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in PictureInPictureChrome.shared.settle() }
            },
        ]
    }

    /// Every window rests on one display again, inside its limits (`PictureInPictureLayout.rest`).
    private func settle() {
        for o in overlays.values { (o.contentView as? PictureInPictureOverlayView)?.dropped() }
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

    /// Whether `window` is the video's Picture in Picture window that Cra dresses as Arc's (not a
    /// Document Picture in Picture one, #702).
    func isVideoWindow(_ window: NSWindow) -> Bool {
        overlays[ObjectIdentifier(window)] != nil || window is PictureInPictureOverlay
    }

    /// `cra://debug?pip=<label>`: Chromium's PiP window as Cra keeps it, and the centre controls'
    /// size for its width (#262).
    func readout() -> String {
        let shown = overlays.values.compactMap { o in o.parent.map { (o, $0) } }
        guard !shown.isEmpty else { return "windows=0" }
        return "windows=\(shown.count) " + shown.map { o, w in
            "key=\(w.isKeyWindow ? 1 : 0) appKey=\(NSApp.keyWindow === w ? 1 : 0) mouse=\(w.ignoresMouseEvents ? 0 : 1) preventKey=\(Self.preventsKey(w) ? 1 : 0) chrome=\(Self.chromeButtonsShown(in: w)) hover=\(Self.hoverTracking(w).count) heard=\(Self.chromiumHearsPointer(w)) width=\(Int(w.frame.width)) share=\(Self.share(of: w)) \(o.controls.readout) frame=\(Int(w.frame.minX)),\(Int(w.frame.minY)),\(Int(w.frame.width)),\(Int(w.frame.height)) onScreen=\(PictureInPictureLayout.landing(afterDropping: w.frame, displays: NSScreen.screens.map(Self.display)) == nil ? 1 : 0)"
        }.joined(separator: " | ")
    }

    /// How many of Chrome's own PiP buttons (Back to Tab, ±10 s, play/pause, close…) show in its
    /// window: Chromium's accessibility tree leaves out the controls while they are hidden (#460).
    static func chromeButtonsShown(in window: NSWindow) -> Int {
        func count(_ element: Any, depth: Int) -> Int {
            guard depth < 40, let node = element as? NSAccessibilityProtocol else { return 0 }
            var n = node.accessibilityRole() == .button && !node.isAccessibilityHidden() ? 1 : 0
            for child in node.accessibilityChildren() ?? [] { n += count(child, depth: depth + 1) }
            return n
        }
        return window.contentView.map { count($0, depth: 0) } ?? 0
    }

    /// `cra://debug?pipPoke=key|focus`: Chromium's window handed what makes Chrome show its own
    /// controls (VideoOverlayWindowViews: a key, or the window becoming key), the way a stray event
    /// would reach it (#460).
    func debugPoke(_ what: String) {
        for o in overlays.values {
            guard let w = o.parent else { continue }
            if what == "focus" {
                w.setValue(false, forKey: "preventKeyWindow")
                w.makeKey()
            } else if let e = NSEvent.keyEvent(with: .keyDown, location: NSPoint(x: w.frame.width / 2, y: w.frame.height / 2), modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                                               characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0) {
                w.sendEvent(e)
            }
        }
    }

    /// `cra://debug?pipDrop=left|right|top|bottom`: the window moved half past that edge of the
    /// outermost display on that side and let go there, as a mouse drag does (#332). The outermost,
    /// so the window is past the edge of the screen whatever displays the Mac has; past an edge
    /// another display sits behind, it would be across two displays instead.
    func debugDrop(_ edge: String) {
        let screens = NSScreen.screens.map(\.frame)
        for o in overlays.values {
            guard let w = o.parent, let view = o.contentView as? PictureInPictureOverlayView else { continue }
            let outer: NSRect? = switch edge {
            case "left": screens.min { $0.minX < $1.minX }
            case "top": screens.max { $0.maxY < $1.maxY }
            case "bottom": screens.min { $0.minY < $1.minY }
            default: screens.max { $0.maxX < $1.maxX }
            }
            guard let screen = outer else { continue }
            // Inside that display along the edge, half past it across.
            var origin = NSPoint(x: min(max(w.frame.minX, screen.minX), screen.maxX - w.frame.width),
                                 y: min(max(w.frame.minY, screen.minY), screen.maxY - w.frame.height))
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

    /// `cra://debug?pipSize=<share>`: the window resized to that share of its display's visible
    /// width (inside the limits and the visible frame), as a finished resize leaves it.
    func debugSize(_ share: CGFloat) {
        guard share.isFinite, share > 0 else { return }
        for o in overlays.values {
            guard let w = o.parent, let view = o.contentView as? PictureInPictureOverlayView else { continue }
            let visible = (w.screen ?? NSScreen.main)?.visibleFrame ?? w.frame
            view.resized(toWidth: (visible.width * share).rounded())
        }
    }

    /// `cra://debug?pipPinch=<m>[,<m>…]`: a trackpad pinch on the window's middle, one magnify
    /// event per value (0.1 is 10 % apart), routed by AppKit with the trackpad's touch-down and
    /// lift around it (`TestGesture.pinch`, #534). Until 0.1.50 this called the pinch's code
    /// straight, so it passed while a real pinch did nothing (#573).
    func debugPinch(_ steps: [CGFloat]) {
        for o in overlays.values {
            TestGesture.pinch(steps, at: NSPoint(x: o.frame.width / 2, y: o.frame.height / 2), in: o)
        }
    }

    /// The window's width as a share of its display's visible width, two decimals.
    private static func share(of w: NSWindow) -> String {
        guard let visible = (w.screen ?? NSScreen.main)?.visibleFrame, visible.width > 0 else { return "-" }
        return String(format: "%.2f", w.frame.width / visible.width)
    }

    /// `cra://debug?pipButton=back|minimize|close`: that hover button clicked.
    func debugPress(_ name: String) {
        for o in overlays.values { o.controls.debugPress(name) }
    }

    /// `cra://debug?pipPointer=readd|enter|move`: what Chromium's own code and the window server can
    /// do to its window (#535). `readd`: Chromium's view puts its tracking area back, as it does on a
    /// level change; `enter`/`move`: the pointer comes onto the window's middle, as AppKit hands
    /// those events to every window under it, to the view's tracking areas when it has any.
    func debugPointer(_ what: String) {
        for o in overlays.values {
            guard let w = o.parent, let view = w.contentView else { continue }
            if what == "readd" {
                let update = NSSelectorFromString("updateCursorTrackingArea")
                if view.responds(to: update) { view.perform(update) }
                continue
            }
            let at = NSPoint(x: w.frame.width / 2, y: w.frame.height / 2)
            let areas = Self.hoverTracking(w).map(\.area)
            for area in areas.isEmpty ? [nil] : areas.map(Optional.some) {
                let number = area.map { Int(bitPattern: Unmanaged.passUnretained($0).toOpaque()) } ?? 0
                let event = what == "move"
                    ? NSEvent.mouseEvent(with: .mouseMoved, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
                    : NSEvent.enterExitEvent(with: .mouseEntered, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: w.windowNumber, context: nil, eventNumber: 0, trackingNumber: number,
                                             userData: area.map { Unmanaged.passUnretained($0).toOpaque() })
                if let event { NSApp.postEvent(event, atStart: false) }
            }
        }
    }

    /// `cra://debug?pipShow=1`: the hover controls shown as the pointer shows them, and kept up.
    func debugShow() {
        for o in overlays.values { o.controls.debugShow() }
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
                // As a real click does on its way through the overlay (`PictureInPictureOverlay.sendEvent`, #741).
                if type == .leftMouseDown { pressed(on: o); view.mouseDown(with: e) } else { view.mouseUp(with: e) }
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
        // Whatever still reaches it is dropped, and it never becomes key: either shows Chrome's own
        // controls under Arc's (#460).
        ChromiumPictureInPictureSeal.seal(window)
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
        let saved = Self.saved()
        let remembered = saved[Self.frameKey].map(NSRectFromString).map {
            PictureInPictureLayout.Placement(frame: $0, display: saved[Self.displayKey],
                                             displayFrame: saved[Self.displayFrameKey].map(NSRectFromString))
        }
        let displays = NSScreen.screens.map(Self.display)
        let frame = PictureInPictureLayout.initialFrame(aspect: aspect, displays: displays, current: current, remembered: remembered)
        let on = displays.firstIndex { $0.frame.intersects(frame) }.map { "display \($0 + 1)/\(displays.count)" } ?? "no display"
        CraLog.note("pip: opens at \(Int(frame.width))×\(Int(frame.height)) on \(on)\(remembered == nil ? "" : " (remembered)")")
        return frame
    }

    func remember(_ frame: NSRect) {
        var values = [Self.frameKey: NSStringFromRect(frame)]
        // The display most of the window is on, as AppKit's `screen` picks it.
        let screen = NSScreen.screens.max { PictureInPictureChrome.overlap($0.frame, frame) < PictureInPictureChrome.overlap($1.frame, frame) }
        if let screen, let id = Self.display(screen).id {
            values[Self.displayKey] = id
            values[Self.displayFrameKey] = NSStringFromRect(screen.frame)
        }
        Self.save(values)
    }

    /// A test instance (CRA_DATA_DIR) keeps the placement in a file in its own data folder, not in
    /// the app's defaults: a test run moved the window the user had left somewhere, and where the
    /// user left it decided how a test went.
    private static let testFile = ProcessInfo.processInfo.environment["CRA_DATA_DIR"] == nil ? nil : AppPaths.file("pip-placement.plist")
    private static let keys = [frameKey, displayKey, displayFrameKey]

    private static func saved() -> [String: String] {
        if let testFile { return (NSDictionary(contentsOf: testFile) as? [String: String]) ?? [:] }
        return Dictionary(uniqueKeysWithValues: keys.compactMap { k in UserDefaults.standard.string(forKey: k).map { (k, $0) } })
    }

    private static func save(_ values: [String: String]) {
        if let testFile { (values as NSDictionary).write(to: testFile, atomically: true); return }
        for k in keys {
            if let v = values[k] { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
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

    /// Cra came forward for a press on the window (#741): the overlay has the keyboard meanwhile, so AppKit doesn't
    /// give it to a browser window, which would bring an automatic Picture in Picture's video back into its tab.
    var takesKeyForGesture = false
    override var canBecomeKey: Bool { takesKeyForGesture }

    /// A press anywhere on the window, its controls too, brings Cra forward first (#741).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { PictureInPictureChrome.shared.pressed(on: self) }
        super.sendEvent(event)
    }
    override var canBecomeMain: Bool { false }
}

final class PictureInPictureOverlayView: NSView {
    private typealias Edge = PictureInPictureGesture.Edge
    private var gesture: PictureInPictureGesture?
    private var requested: NSRect?
    /// The display the window was on when the press or the swipe began, and its size then, for a
    /// move to another display. The size is the press's: on the way Chromium may cut the window
    /// down, and Cra fits it to the display it is crossing (`undoChromiumCap`).
    private var pressedOn: PictureInPictureLayout.Display?
    private var pressedSize: NSSize?
    /// The size Cra last gave the window or let it keep, and Chromium's cap on it then
    /// (`undoChromiumCap`).
    private var given: NSSize?
    private var cap: NSSize?

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
            pinch = nil
            fingers.reset()
            releasePointer()
            magnifyMonitor.map(NSEvent.removeMonitor)
            magnifyMonitor = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, magnifyMonitor == nil else { return }
        // A trackpad's magnify comes to this window, but AppKit doesn't always hand it on to the
        // view: in a probe (19 Nov 2026), magnify events the window server addressed to a panel
        // that can't become key, the pointer in its middle, reached the app's event monitors and
        // never the view's `magnify(with:)`, while the scrolls of the same fingers did; a 0.1.49
        // PiP didn't resize under them either (#573). So the overlay takes them where AppKit sends
        // events on, before that dispatch.
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            let taken = MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window else { return false }
                self.magnify(with: event)
                return true
            }
            return taken ? nil : event
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
        fingers.reset()
        pressedOn = Self.display(holding: target.frame)
        pressedSize = target.frame.size
        releasePointer()
        stopLink()
        gesture = PictureInPictureGesture(mouse: Self.screenLocation(of: event), frame: target.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let target, var g = gesture else { return }
        // The button was let go without a mouse-up reaching this window.
        if NSEvent.pressedMouseButtons & 1 == 0 { finish(event); return }
        // The limits (#246): 224 × 126 for a 16:9 video at least, as in Arc, and the display's
        // visible frame at most. Chromium's own maximum (80 % of the work area, `contentMaxSize`)
        // only binds its native resize, which this window never gets.
        let screen = target.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? target.frame
        let limits = PictureInPictureLayout.sizeLimits(aspect: g.startFrame.width / max(g.startFrame.height, 1),
                                                       screen: screen?.frame ?? visible, visible: visible)
        // Up to the display's edges, not past them.
        let room = g.room(in: visible)
        let maxSize = NSSize(width: min(limits.max.width, room.width), height: min(limits.max.height, room.height))
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
            give(frame, to: target)
        }
    }

    override func mouseUp(with event: NSEvent) { finish(event) }

    private func finish(_ event: NSEvent) {
        guard let target, let g = gesture else { return }
        gesture = nil
        if !g.isDragging || g.edge != .none { pressedOn = nil }   // only a move can change display
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

    /// The mouse let the moved window go (or the displays changed). It comes to rest on one
    /// display (`PictureInPictureLayout.rest`): partly past the screen's edge, it flies into the
    /// nearest corner on the swipe's spring, as Arc's does (#332); across two displays, it slides
    /// onto the one most of it is on; on another display than it came from, it takes the same
    /// share of that display's width. Where it lands is kept for the next video; otherwise the
    /// spot it was let go at is.
    func dropped() {
        guard let target else { return }
        undoChromiumCap(settling: false)
        let from = pressedOn, f = target.frame
        // Moved from another display: the share of the width is taken of the size at the press.
        let letGo = from.flatMap { _ in pressedSize }.map { NSRect(x: f.midX - $0.width / 2, y: f.midY - $0.height / 2, width: $0.width, height: $0.height) } ?? f
        pressedOn = nil
        pressedSize = nil
        // Back on the display it came from, it has its size from the press again.
        guard let rest = PictureInPictureLayout.rest(afterDropping: letGo, from: from, displays: NSScreen.screens.map(PictureInPictureChrome.display))
                ?? (letGo.size != f.size ? .init(frame: letGo, corner: nil) : nil) else {
            return PictureInPictureChrome.shared.remember(target.frame)
        }
        if let corner = rest.corner {
            CraLog.note("pip: dropped past the edge, to \(corner.rawValue)")
        } else {
            CraLog.note("pip: onto one display, \(Self.size(target.frame)) → \(Self.size(rest.frame))")
        }
        if rest.frame.size != target.frame.size {
            // The new size first, around the window's centre; then it flies to its place.
            let f = target.frame
            give(NSRect(x: f.midX - rest.frame.width / 2, y: f.midY - rest.frame.height / 2, width: rest.frame.width, height: rest.frame.height), to: target)
        }
        flight = PictureInPictureFlight(from: target.frame.origin, velocity: .zero, to: rest.frame.origin)
        startLink()
    }

    /// Sets the window's frame and remembers its size as the one Cra gave it.
    private func give(_ frame: NSRect, to target: NSWindow) {
        given = frame.size
        cap = target.contentMaxSize
        target.setFrame(frame, display: true)
    }

    /// The window resized to `width` inside the limits of its display, its top-left kept where the
    /// display's visible frame has room, then kept for the next video (`cra://debug?pipSize`).
    func resized(toWidth width: CGFloat) {
        guard let target, let screen = target.screen ?? NSScreen.main else { return }
        let f = target.frame, v = screen.visibleFrame
        let display = PictureInPictureChrome.display(screen)
        let size = PictureInPictureLayout.size(NSSize(width: width, height: width * f.height / max(f.width, 1)), movedFrom: nil, onto: display)
        let x = max(min(f.minX, v.maxX - size.width), v.minX), top = min(max(f.maxY, v.minY + size.height), v.maxY)
        give(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), to: target)
        CraLog.note("pip: resized to \(Self.size(target.frame))")
        PictureInPictureChrome.shared.remember(target.frame)
    }

    /// Chromium resized the window. When that was Chromium cutting it down to its own cap (80 % of
    /// the work area, which Cra's limits go past), the size Cra gave it comes back, in the video's
    /// shape (`PictureInPictureLayout.undoingChromiumCap`), and outside a gesture the window comes
    /// to rest on its display again. Returns whether it put the size back.
    @discardableResult
    func undoChromiumCap(settling: Bool = true) -> Bool {
        guard let target else { return false }
        let now = target.frame.size, chromiumCap = target.contentMaxSize
        defer { cap = chromiumCap }
        guard let was = given, now != was else {
            if given == nil { given = now }
            return false
        }
        guard let screen = target.screen ?? NSScreen.main,
              let size = PictureInPictureLayout.undoingChromiumCap(was: was, now: now, cap: chromiumCap, capChanged: cap != chromiumCap,
                                                                    on: PictureInPictureChrome.display(screen)) else {
            given = now   // Chromium's own size stands
            return false
        }
        CraLog.note("pip: Chromium cut \(Self.size(NSRect(origin: .zero, size: was))) to \(Self.size(target.frame)), back to \(Int(size.width))×\(Int(size.height))")
        // Chromium cut it from the bottom right; it grows back there.
        let f = target.frame
        give(NSRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height), to: target)
        if settling, gesture == nil, swipe == nil, pinch == nil, flight == nil { dropped() }
        return true
    }

    private static func display(holding frame: NSRect) -> PictureInPictureLayout.Display? {
        PictureInPictureLayout.display(holding: frame, in: NSScreen.screens.map(PictureInPictureChrome.display))
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

    // MARK: Pinch to resize (Arc, #534)

    private var pinch: PictureInPicturePinch?
    /// Takes the trackpad's magnify events addressed to this window (`viewDidMoveToWindow`).
    private var magnifyMonitor: Any?
    /// Which of the two-finger gestures has the window (`PictureInPictureFingers`).
    private var fingers = PictureInPictureFingers()

    /// Two fingers pinching on the trackpad resize the window, as Arc's do: apart larger, together
    /// smaller, in the video's shape, inside the limits of an edge resize
    /// (`PictureInPicturePinch`). Not while a press has it, or a swipe that has moved it. Fingers
    /// resting on the trackpad before the pinch (a scroll that may begin) don't keep it from the
    /// pinch: in 0.1.49 they did, and a real pinch did nothing (#573).
    override func magnify(with event: NSEvent) {
        guard gesture == nil else { return }
        switch fingers.magnify(Self.phase(event), swipeMoved: swipe?.hasMoved ?? false) {
        case .startPinch(let fromSwipe):
            if fromSwipe { dropSwipe() }
            endPinch()   // one whose end never came
            beginPinch()
            pinched(by: event.magnification)
        case .pinch:
            pinched(by: event.magnification)
        case .endPinch:
            endPinch()
        case .pinchOnce(let fromSwipe):
            if fromSwipe { dropSwipe() }
            beginPinch(); pinched(by: event.magnification); endPinch()
        case .ignore, .startSwipe, .swipe, .endSwipe:
            break
        }
    }

    private static func phase(_ event: NSEvent) -> PictureInPictureFingers.Phase {
        switch event.phase {
        case .mayBegin: .mayBegin
        case .began: .began
        case .changed, .stationary: .changed
        case .ended: .ended
        case .cancelled: .cancelled
        default: .none
        }
    }

    /// Resting fingers had the window for a swipe that never moved it; the pinch takes it over,
    /// and nothing is thrown.
    private func dropSwipe() {
        guard swipe != nil else { return }
        swipe = nil
        releasePointer()
        pressedOn = nil
        pressedSize = nil
        if flight == nil { stopLink() }
    }

    private func beginPinch() {
        guard gesture == nil, let target else { return }
        land()
        pinch = PictureInPicturePinch(frame: target.frame)
        pressedOn = nil
    }

    private func pinched(by magnification: CGFloat) {
        guard let target else { return }
        if pinch == nil { beginPinch() }
        guard var p = pinch else { return }
        let screen = target.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? target.frame
        let limits = PictureInPictureLayout.sizeLimits(aspect: p.startFrame.width / max(p.startFrame.height, 1),
                                                       screen: screen?.frame ?? visible, visible: visible)
        let minSize = NSSize(width: max(target.contentMinSize.width, limits.min.width), height: max(target.contentMinSize.height, limits.min.height))
        let frame = p.magnify(by: magnification, minSize: minSize, maxSize: limits.max, visible: visible)
        if p.scale != 1, pinch?.scale == 1 { CraLog.note("pip: pinch from \(Self.size(p.startFrame))") }
        pinch = p
        guard frame != target.frame else { return }
        give(frame, to: target)
    }

    private func endPinch() {
        guard let p = pinch else { return }
        pinch = nil
        guard let target, p.scale != 1 else { return }
        CraLog.note("pip: pinched \(Self.size(p.startFrame)) → \(Self.size(target.frame))")
        PictureInPictureChrome.shared.remember(target.frame)
    }

    // MARK: Swipe to a corner (Arc)

    private var swipe: PictureInPictureThrow?
    private var flight: PictureInPictureFlight?
    /// Runs while the fingers are on the window and while it flies: the window moves once per
    /// screen refresh, never straight from a scroll event.
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    /// The pointer is hidden, riding along with the window under the fingers.
    private var carrying = false
    /// Watch for the fingers' lift reaching another window (`watchForLift`).
    private var liftMonitors: [Any] = []

    /// Two fingers on the trackpad (or a Magic Mouse) move the window with them, and when they
    /// lift it flies on into the corner of the screen it was heading for, as Arc's does. A wheel
    /// without phases (a plain mouse) moves nothing, and AppKit's own momentum after the lift is
    /// left out: the flight is the momentum. Scroll events only record where the fingers are;
    /// `tick` shows the window there, a frame at a time (see `PictureInPictureThrow.origin(at:)`).
    override func scrollWheel(with event: NSEvent) {
        guard gesture == nil, let target, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        let t = event.timestamp
        // While a pinch has the window its scrolls go nowhere, the touch-down's late end included.
        switch fingers.scroll(Self.phase(event)) {
        case .startSwipe:
            endPinch()   // one whose end never came
            beginSwipe(target, event)
        case .swipe:
            if swipe == nil { beginSwipe(target, event) }
            // The window goes where the fingers go: with natural scrolling the deltas already
            // follow them, without it they're the other way round.
            let toFingers: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            _ = swipe?.move(dx: toFingers * event.scrollingDeltaX, dy: -toFingers * event.scrollingDeltaY, at: t)
        case .endSwipe:
            endSwipe(target, event)
        case .ignore, .startPinch, .pinch, .endPinch, .pinchOnce:
            break
        }
    }

    /// The fingers touched down on the window. The window will go only as far as the pointer,
    /// riding along at its spot in it, can follow: inside the displays' visible frames, off the
    /// menu bar and the Dock (`PictureInPictureThrow`, #516).
    private func beginSwipe(_ target: NSWindow, _ event: NSEvent) {
        land()
        releasePointer()
        let f = target.frame, at = Self.screenLocation(of: event)
        swipe = PictureInPictureThrow(frame: f, at: event.timestamp, pointer: CGVector(dx: at.x - f.minX, dy: at.y - f.minY),
                                      displays: NSScreen.screens.map(\.visibleFrame))
        pressedOn = Self.display(holding: f)
        pressedSize = f.size
        watchForLift()
        startLink()
    }

    private func endSwipe(_ target: NSWindow, _ event: NSEvent) {
        guard let s = swipe else { return }
        swipe = nil
        releasePointer()
        guard s.hasMoved else { pressedOn = nil; return stopLink() }
        throwWindow(target, aim: s.frame, velocity: event.phase == .ended ? s.velocity(at: event.timestamp) : .zero)
    }

    /// Should the fingers' lift reach another window after all (a notification banner over this
    /// one, the displays changing under it), it still ends the swipe: the window flies into its
    /// corner and the pointer shows again, where before it stayed hidden until Cra quit (#516).
    private func watchForLift() {
        guard liftMonitors.isEmpty else { return }
        let lifted = { [weak self] (e: NSEvent) in
            guard e.momentumPhase.isEmpty, e.phase == .ended || e.phase == .cancelled else { return }
            MainActor.assumeIsolated {
                guard let self, let target = self.target, self.swipe != nil else { return }
                CraLog.note("pip: swipe lifted over another window")
                self.fingers.reset()
                self.endSwipe(target, e)
            }
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            if e.window !== self?.window { lifted(e) }
            return e
        }) { liftMonitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: lifted) { liftMonitors.append(m) }
    }

    /// The fingers lifted with the window shown at its own frame and aimed at `aim` (where the
    /// fingers had it): it flies on from where it is shown, at their speed, so the hand-off is seamless.
    private func throwWindow(_ target: NSWindow, aim: NSRect, velocity: CGVector) {
        let from = pressedOn
        pressedOn = nil
        let rest = PictureInPictureThrow.restingCentre(of: aim, velocity: velocity)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rest) }) ?? target.screen ?? NSScreen.main else { return stopLink() }
        let display = PictureInPictureChrome.display(screen)
        let corner = PictureInPictureThrow.corner(for: aim, velocity: velocity, in: display.visible)
        // On another display it takes the same share of its width, as a mouse drag there does;
        // `aim` has the size the swipe began with, whatever Chromium cut it to on the way.
        let size = PictureInPictureLayout.size(aim.size, movedFrom: from, onto: display)
        let end = PictureInPictureLayout.frame(in: corner, size: size, on: display)
        CraLog.note("pip: swipe to \(corner.rawValue) at \(Int(hypot(velocity.dx, velocity.dy))) pt/s")
        if size != target.frame.size {
            let f = target.frame
            give(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height), to: target)
        }
        flight = PictureInPictureFlight(from: target.frame.origin, velocity: velocity, to: end.origin)
        startLink()
    }

    /// Scroll events go to the window under the pointer, so once the window slid out from under
    /// it the fingers moved whatever was behind instead. As in Arc, the pointer hides when the
    /// window starts to move and rides along at its spot in the window (`pointer`, from the
    /// window's origin) until the fingers lift.
    private func carryPointer(to origin: CGPoint, at pointer: CGVector) {
        if !carrying {
            carrying = true
            NSCursor.hide()
        }
        guard let primary = NSScreen.screens.first else { return }
        CGWarpMouseCursorPosition(CGPoint(x: origin.x + pointer.dx, y: primary.frame.maxY - (origin.y + pointer.dy)))
        // A warp holds the pointer's own moves back for a quarter of a second; this lifts the hold.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// The swipe is over: the pointer shows again and the lift is no longer watched for.
    private func releasePointer() {
        liftMonitors.forEach { NSEvent.removeMonitor($0) }
        liftMonitors = []
        guard carrying else { return }
        carrying = false
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
        guard let target else {
            releasePointer()
            return stopLink()
        }
        if let s = swipe {
            let origin = s.origin(at: link.timestamp)
            guard origin != target.frame.origin else { return }
            if let pointer = s.pointer { carryPointer(to: origin, at: pointer) }
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
