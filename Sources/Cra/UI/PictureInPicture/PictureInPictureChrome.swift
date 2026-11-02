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
    private enum Edge { case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
    private static let grip: CGFloat = 8
    private var edge: Edge = .none
    private var startMouse: NSPoint = .zero
    private var startFrame: NSRect = .zero

    private var target: NSWindow? { window?.parent }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        let g = Self.grip
        let b = bounds
        addCursorRect(NSRect(x: b.minX, y: b.minY + g, width: g, height: b.height - 2 * g), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.maxX - g, y: b.minY + g, width: g, height: b.height - 2 * g), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.minX + g, y: b.maxY - g, width: b.width - 2 * g, height: g), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: b.minX + g, y: b.minY, width: b.width - 2 * g, height: g), cursor: .resizeUpDown)
    }

    private func edge(at p: NSPoint) -> Edge {
        let g = Self.grip
        let l = p.x < g, r = p.x > bounds.maxX - g, t = p.y > bounds.maxY - g, bt = p.y < g
        switch (l, r, t, bt) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return .none
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let target else { return }
        edge = edge(at: convert(event.locationInWindow, from: nil))
        startMouse = NSEvent.mouseLocation
        startFrame = target.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let target else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - startMouse.x, dy = m.y - startMouse.y
        if edge == .none {
            target.setFrameOrigin(NSPoint(x: startFrame.minX + dx, y: startFrame.minY + dy))
            return
        }
        // Aspect-locked resize anchored on the opposite edge/corner.
        let aspect = startFrame.width / max(startFrame.height, 1)
        var w = startFrame.width
        switch edge {
        case .right, .topRight, .bottomRight: w = startFrame.width + dx
        case .left, .topLeft, .bottomLeft: w = startFrame.width - dx
        case .top: w = (startFrame.height + dy) * aspect
        case .bottom: w = (startFrame.height - dy) * aspect
        case .none: break
        }
        w = max(160, min(w, (target.screen?.visibleFrame.width ?? 2000) - 2 * PictureInPictureChrome.edgeMargin))
        let h = w / aspect
        var f = startFrame
        f.size = NSSize(width: w, height: h)
        switch edge {
        case .left, .bottomLeft: f.origin.x = startFrame.maxX - w
        case .topLeft: f.origin = NSPoint(x: startFrame.maxX - w, y: startFrame.maxY - h)
        case .topRight, .top: f.origin.y = startFrame.maxY - h
        default: break
        }
        target.setFrame(f, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let target else { return }
        PictureInPictureChrome.shared.remember(target.frame)
        edge = .none
    }

    // The pointer never reaches Chromium (its own controls stay hidden); the
    // controls subview shows Arc's on hover.
    override func mouseMoved(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
