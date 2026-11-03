import AppKit

/// Arc's floating sidebar: with the sidebar hidden, touching the window's left
/// edge slides the sidebar in over the page; it leaves when the pointer does.
///
/// Pages are separate Chromium child windows stacked above the shell, so a
/// sidebar drawn inside the shell would be covered and the shell never sees the
/// pointer over a page. The sidebar therefore moves into its own child panel
/// (above the page windows) while it floats, and a pointer monitor that sees
/// events in every window of the app decides when it comes and goes.
@MainActor
final class FloatingSidebarController {
    unowned let shell: ShellView
    unowned let window: NSWindow
    /// Whether the anchored sidebar is hidden right now (floating only makes sense then).
    var sidebarHidden: () -> Bool = { false }
    /// Something beside the sidebar still belongs to it (a folder preview): the pointer may leave.
    var staysShown: () -> Bool = { false }
    var palette: () -> SpacePalette
    /// Called after the panel is attached so the overlay panel can be re-ordered above it.
    var didAttachPanel: (() -> Void)?

    private(set) var isShown = false
    /// A completed hide must not take the panel away from a newer reveal or anchor.
    private var transitionGeneration: UInt64 = 0
    private var panel: FloatingSidebarPanel?
    /// The sidebar's rounded body; it slides inside the panel (see `panelFrame`).
    private let slider = NSView()
    private let blur = NSVisualEffectView()
    private let lift = NSView()
    private var gradientHost: PaletteBackgroundView?
    private var trafficLights: FloatingTrafficLights?
    /// The floating sidebar's right edge drags its width, like the anchored sidebar's handle.
    private let resizeHandle = ResizeHandleView()

    enum Metrics {
        static let cornerRadius: CGFloat = 12
        static let duration: TimeInterval = 0.085
        /// Inside the sidebar's edge: the panel ends there, so the strip cannot straddle it.
        static let resizeHandleWidth: CGFloat = 6
    }

    init(shell: ShellView, window: NSWindow, palette: @escaping () -> SpacePalette) {
        self.shell = shell
        self.window = window
        self.palette = palette
    }

    deinit {
        poll?.invalidate()
        activation.forEach(NotificationCenter.default.removeObserver)
        displayOptions.map(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private var poll: Timer?
    private var activation: [NSObjectProtocol] = []
    /// Reduce transparency changes the panel's lift (GitHub #156).
    private var displayOptions: NSObjectProtocol?

    /// No window of ours reliably receives mouse-moved events here: the key window
    /// is usually a Chromium page window, and the shell's tracking areas only run in
    /// the key window. So the pointer is sampled on a timer while the app is active,
    /// and the timer stops while it is not: at 30 Hz it was most of the run loop's
    /// wake-ups in a Cra left in the background (#136).
    func install() {
        guard activation.isEmpty else { return }
        let center = NotificationCenter.default
        activation = [(NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false)].map { name, on in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPolling(on) }
            }
        }
        setPolling(NSApp.isActive)
        displayOptions = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBackdrop() }
        }
    }

    private func setPolling(_ on: Bool) {
        guard on != (poll != nil) else { return }
        poll?.invalidate()
        poll = nil
        guard on else { return }
        // Fired on the main run loop, so no hop to the main actor: one wake-up per tick, not two.
        poll = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        poll?.tolerance = 0.01
    }

    /// Whether the pointer is being sampled (the tests check it follows the app's activation).
    var isPolling: Bool { poll != nil }

    private func pointerMoved() {
        guard NSApp.isActive, !shell.contentFullscreen, window.isVisible else { return }
        guard isShown || sidebarHidden() else { return }
        let screenPoint = NSEvent.mouseLocation
        let p = shell.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        if !isShown {
            guard sidebarHidden(), isKey, FloatingSidebarGeometry.shouldReveal(at: p, in: shell.bounds, edgeToEdge: shell.edgeToEdge) else { return }
            show()
        } else if !staysShown(), FloatingSidebarGeometry.shouldHide(at: p, in: shell.bounds, sidebarWidth: shell.sidebarWidth,
                                                    pressedMouseButtons: NSEvent.pressedMouseButtons, edgeToEdge: shell.edgeToEdge) {
            hide(animated: true)
        }
    }

    /// The app's key window (nil while Cra is inactive); the tests stand one in.
    var keyWindow: () -> NSWindow? = { NSApp.keyWindow }

    /// Like Arc, only the key window's sidebar comes out on hover (GitHub #82): every window
    /// polls the pointer, and one behind another would otherwise reveal over it. The key
    /// window is often one of this window's own child windows (a page, DevTools, the panel).
    var isKey: Bool {
        var w = keyWindow()
        while let c = w, c !== window { w = c.parent }
        return w != nil
    }

    /// The sidebar's floating frame on screen, from the shell's layout.
    private var targetFrame: NSRect {
        let f = shell.frames(sidebarVisible: false, floating: true, fullscreen: false, width: shell.sidebarWidth).sidebar
        return window.convertToScreen(shell.convert(f, to: nil))
    }

    /// The panel reaches from the window's left edge to the sidebar's right edge, so the
    /// sidebar slides in from the window edge and is clipped there (Arc draws it inside
    /// its window), instead of sliding across whatever lies left of the window.
    private var panelFrame: NSRect {
        let t = targetFrame
        return NSRect(x: window.frame.minX, y: t.minY, width: t.maxX - window.frame.minX, height: t.height)
    }

    /// The sidebar inside the panel: in place, or tucked out past the window edge.
    private func slideFrame(shown: Bool) -> NSRect {
        let t = targetFrame
        return NSRect(x: shown ? t.minX - window.frame.minX : -t.width, y: 0, width: t.width, height: t.height)
    }

    private func makePanel() -> FloatingSidebarPanel {
        let p = FloatingSidebarPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        let content = NSView(frame: p.contentRect(forFrameRect: p.frame))
        content.wantsLayer = true
        p.contentView = content
        slider.wantsLayer = true
        slider.layer?.cornerRadius = Metrics.cornerRadius
        slider.layer?.cornerCurve = .continuous
        slider.layer?.masksToBounds = true
        content.addSubview(slider)
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        slider.addSubview(blur)
        lift.wantsLayer = true
        lift.autoresizingMask = [.width, .height]
        slider.addSubview(lift)
        let g = PaletteBackgroundView(palette: palette())
        g.autoresizingMask = [.width, .height]
        slider.addSubview(g)
        gradientHost = g
        let lights = FloatingTrafficLights(browserWindow: window)
        lights.willAct = { [weak self] in self?.hide(animated: false) }
        trafficLights = lights
        resizeHandle.autoresizingMask = [.minXMargin, .height]
        // The shell's handle owns the width and saves it; the panel follows.
        resizeHandle.onDrag = { [weak self] dx in
            guard let self else { return }
            shell.resizeHandle.onDrag?(dx)
            reposition()
        }
        resizeHandle.onEnd = { [weak self] in self?.shell.resizeHandle.onEnd?() }
        return p
    }

    /// The space's colours behind the sidebar; the window calls it when the theme changes.
    func refreshBackdrop() {
        guard panel != nil else { return }
        let pal = palette()
        let t = CraTuning.shared
        for v in [blur, lift, gradientHost as NSView?].compactMap({ $0 }) { v.frame = slider.bounds }
        gradientHost?.palette = pal
        blur.isHidden = !pal.vibrant
        lift.isHidden = !pal.vibrant
        blur.material = pal.isDark ? .underWindowBackground : t.material
        blur.appearance = NSAppearance(named: t.darkBlur ? .darkAqua : .aqua)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        lift.layer?.backgroundColor = NSColor(white: 1, alpha: SidebarBackdrop.floatingLift(dark: pal.isDark, reduceTransparency: reduce, lift: t.liftActive)).cgColor
    }

    func show() {
        guard !isShown, sidebarHidden() else { return }
        isShown = true
        transitionGeneration &+= 1
        let generation = transitionGeneration
        let p = panel ?? makePanel()
        panel = p
        // The window shadow is traced from the panel's pixels once; it comes on when the
        // sidebar has landed and goes off before it leaves, so no shadow is left behind.
        p.hasShadow = false
        p.setFrame(panelFrame, display: false)
        slider.frame = slideFrame(shown: false)
        refreshBackdrop()
        let host = shell.sidebarHost
        host.removeFromSuperview()
        host.frame = slider.bounds
        host.autoresizingMask = [.width, .height]
        host.layer?.cornerRadius = 0
        slider.addSubview(host)
        // The window's own traffic lights hide with the sidebar; these stand in at the
        // same spot in the sidebar's top row.
        if let lights = trafficLights {
            lights.setFrameOrigin(NSPoint(x: 13, y: slider.bounds.height - CraMetrics.titleRowCenter - lights.frame.height / 2))
            slider.addSubview(lights, positioned: .above, relativeTo: host)
        }
        let w = Metrics.resizeHandleWidth
        resizeHandle.frame = NSRect(x: slider.bounds.width - w, y: 0, width: w, height: slider.bounds.height)
        resizeHandle.isHidden = !shell.sidebarResizable
        slider.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
        shell.sidebarDetached = true
        shell.floatingSidebar = true
        if p.parent !== window { window.addChildWindow(p, ordered: .above) }
        didAttachPanel?()
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Metrics.duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.7, 0.3, 1)
            slider.animator().frame = slideFrame(shown: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation, self.isShown else { return }
                p.hasShadow = true
                p.invalidateShadow()
            }
        }
    }

    func hide(animated: Bool) {
        // A synchronous hide also finishes a hide already in flight (for example,
        // before a traffic-light action). Repeated animated exits do not restart it.
        guard isShown || (!animated && shell.sidebarDetached), let p = panel else { return }
        isShown = false
        transitionGeneration &+= 1
        let generation = transitionGeneration
        p.hasShadow = false
        let finish = { [weak self] in
            guard let self, self.transitionGeneration == generation, !self.isShown else { return }
            self.window.removeChildWindow(p)
            p.orderOut(nil)
            self.reattach(floating: false)
        }
        guard animated else { finish(); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Metrics.duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.7, 0.3, 1)
            slider.animator().frame = slideFrame(shown: false)
        } completionHandler: { finish() }
    }

    /// The sidebar is about to be anchored (⌘S while floating): put it back in the
    /// shell at its floating frame so the anchoring animation starts from there.
    func prepareForAnchoring() {
        transitionGeneration &+= 1
        // During the hide animation isShown is already false, but the view still
        // belongs to the panel and must come home before the anchoring animation.
        guard shell.sidebarDetached, let p = panel else { return }
        isShown = false
        window.removeChildWindow(p)
        p.orderOut(nil)
        reattach(floating: true)
    }

    private func reattach(floating: Bool) {
        let host = shell.sidebarHost
        host.removeFromSuperview()
        host.autoresizingMask = []
        shell.addSubview(host, positioned: .below, relativeTo: shell.resizeHandle)
        shell.sidebarDetached = false
        shell.floatingSidebar = floating
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
    }

    /// Window moved or resized while floating.
    func reposition() {
        guard isShown, let p = panel else { return }
        p.setFrame(panelFrame, display: true)
        slider.frame = slideFrame(shown: true)
        p.invalidateShadow()
    }
}

final class FloatingSidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Keep the stand-in traffic lights in colour, like the window's (CraWindow).
    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func hasActiveAppearance(forStandardWindowButton type: UInt) -> Bool { true }
}

/// Real standard window buttons for the floating sidebar, acting on the browser
/// window rather than on the panel they sit in. AppKit draws the ×/−/+ glyphs
/// only while the buttons' superview answers `_mouseInGroup:` with true.
final class FloatingTrafficLights: NSView {
    unowned let browserWindow: NSWindow
    /// Runs before a button acts (the sidebar gets out of the way first).
    var willAct: () -> Void = {}
    private var mouseInside = false {
        didSet { for b in subviews { b.needsDisplay = true } }
    }
    private var tracking: NSTrackingArea?

    init(browserWindow: NSWindow) {
        self.browserWindow = browserWindow
        super.init(frame: .zero)
        let actions = [#selector(closeWindow), #selector(minimizeWindow), #selector(zoomWindow)]
        var height: CGFloat = 0
        for (i, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = NSWindow.standardWindowButton(type, for: browserWindow.styleMask) else { continue }
            b.setFrameOrigin(NSPoint(x: CGFloat(i) * 24, y: 0))
            b.target = self
            b.action = actions[i]
            addSubview(b)
            height = max(height, b.frame.height)
            setFrameSize(NSSize(width: b.frame.maxX, height: height))
        }
        autoresizingMask = [.maxXMargin, .minYMargin]
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc(_mouseInGroup:)
    func mouseInGroup(_ button: NSButton) -> Bool { mouseInside }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { mouseInside = true }
    override func mouseExited(with event: NSEvent) { mouseInside = false }
    override func viewDidMoveToWindow() { mouseInside = false }

    @objc private func closeWindow() { willAct(); browserWindow.performClose(nil) }
    @objc private func minimizeWindow() { willAct(); browserWindow.performMiniaturize(nil) }
    /// The green button's click: full screen, or zoom with ⌥ held.
    @objc private func zoomWindow() {
        willAct()
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { browserWindow.zoom(nil) } else { browserWindow.toggleFullScreen(nil) }
    }
}
