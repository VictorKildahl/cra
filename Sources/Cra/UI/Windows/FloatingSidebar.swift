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
    /// Whether the browser window is in macOS full screen; the tests stand one in.
    lazy var windowFullScreen: () -> Bool = { [unowned self] in self.window.styleMask.contains(.fullScreen) }
    /// The browser window's corner radius, for clipping the sidebar to it on its way in and out.
    var windowCornerRadius: () -> CGFloat = { 0 }
    /// Called after the panel is attached so the overlay panel can be re-ordered above it.
    var didAttachPanel: (() -> Void)?

    private(set) var isShown = false
    /// A completed hide must not take the panel away from a newer reveal or anchor.
    private var transitionGeneration: UInt64 = 0
    private var panel: FloatingSidebarPanel?
    /// The sidebar's shadow, in a panel of its own under the sidebar's that lets clicks through. The
    /// sidebar panel's window shadow drew a hard outline round it; Arc has only the soft shadow (#293).
    private var shadowPanel: NSPanel?
    private let shadowView = NSView()
    private let shadowCutout = CAShapeLayer()
    /// The pointer's wait in the reveal strip (#293).
    private var dwell = FloatingSidebarRevealDwell()
    /// The clock the wait runs on; the tests stand one in.
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// The window's shape, as a mask on each panel's content. The panels start at the window's left
    /// edge and are square, so the sidebar's top and bottom edges showed past the window's rounded
    /// corners while it slid along that edge; Arc draws its sidebar inside the window, which cuts it
    /// there (#341).
    private let clip = CALayer()
    private let shadowClip = CALayer()
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
        /// Arc 1.172.1's reveal, fitted to its 120 fps frames (9 Nov 2026, GitHub #293): a spring that
        /// lands in ~0.1 s, overshoots ~1.5 % and settles by ~0.23 s. Cra slid in on the ⌘S hide's
        /// 0.085 s ease-out, half way out in the first frame.
        static let revealStiffness: CGFloat = 759
        static let revealDamping: CGFloat = 46.3
        static let revealVelocity: CGFloat = 23.3
        /// Arc's hide, fitted the same way: 0.1 s on (0.14, 0, 0.53, 1), a soft start.
        static let hideDuration: TimeInterval = 0.102
        static let hideCurve: (Float, Float, Float, Float) = (0.14, 0, 0.53, 1)
        /// Arc's floating sidebar shadow (2x still, #293): a tight band, ~7 % darker for 4–5 pt past the
        /// edge, ~1.5 % at 6 pt, nothing from ~8 pt, the same on every side. Fitted as a shadow of the
        /// sidebar grown by 5 pt with a 1.5 pt Gaussian edge (shadowRadius 3).
        static let shadowRadius: CGFloat = 3
        static let shadowSpread: CGFloat = 5
        static let shadowOpacity: Float = 0.07
        /// How long the first frames of a reveal take to reach the screen (#293, 120 fps: ~25 ms).
        static let firstFrameDelay: CFTimeInterval = 0.025
        /// Room round the sidebar for its shadow in the shadow panel.
        static let shadowPad: CGFloat = 16
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
        guard NSApp.isActive, window.isVisible else { return }
        guard isShown || sidebarHidden() else { return }
        let screenPoint = NSEvent.mouseLocation
        let p = shell.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        if !isShown {
            edgeSample(inStrip: sidebarHidden() && isKey && FloatingSidebarGeometry.shouldReveal(at: p, in: shell.bounds, edgeToEdge: shell.fillsWindow))
        } else if !staysShown(), FloatingSidebarGeometry.shouldHide(at: p, in: shell.bounds, sidebarWidth: shell.sidebarWidth,
                                                    pressedMouseButtons: NSEvent.pressedMouseButtons, edgeToEdge: shell.fillsWindow) {
            hide(animated: true)
        }
    }

    /// The shell saw the pointer move in the strip: a sample toward the same wait as the poll's, so a
    /// moving pointer can't skip it (#293).
    func edgeHovered() {
        guard !isShown, sidebarHidden(), isKey else { return }
        edgeSample(inStrip: true)
    }

    /// One look at the pointer while the sidebar is in. Arriving in the strip stages the sidebar (in its
    /// panel, tucked out of sight), so the costly part of a reveal happens during the wait: done at the
    /// reveal, it held the first frame back ~90 ms. Leaving before the wait is over puts it back.
    func edgeSample(inStrip: Bool) {
        guard !isShown else { return }
        // The wait runs from the sample, not from after the staging: that takes ~90 ms on the main thread.
        let t = now()
        if inStrip, !shell.sidebarDetached { stage() }
        if !inStrip, staged { unstage() }
        if dwell.sample(inStrip: inStrip, at: t) { show() }
    }

    /// Whether the sidebar waits in its panel, tucked away, for the pointer's wait to end.
    private(set) var staged = false

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

    /// The shadow panel: the sidebar panel with room for the shadow right, above and below. It
    /// starts at the window's edge too, so the shadow is clipped there with the sidebar.
    private var shadowPanelFrame: NSRect {
        let f = panelFrame, pad = Metrics.shadowPad
        return NSRect(x: f.minX, y: f.minY - pad, width: f.width + pad, height: f.height + 2 * pad)
    }

    private func makeShadowPanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isMovable = false
        p.hidesOnDeactivate = false
        let content = NSView(frame: p.contentRect(forFrameRect: p.frame))
        content.wantsLayer = true
        p.contentView = content
        shadowView.wantsLayer = true
        content.addSubview(shadowView)
        shadowCutout.fillRule = .evenOdd
        return p
    }

    /// Each mask takes the window's frame and corners, as seen from its panel, so it stays put while
    /// the sidebar and its shadow slide under it. A full-screen window has square corners.
    private func placeClips() {
        let radius = windowFullScreen() ? 0 : windowCornerRadius()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (mask, host) in [(clip, panel as NSWindow?), (shadowClip, shadowPanel)] {
            guard let host, let content = host.contentView?.layer else { continue }
            mask.backgroundColor = NSColor.black.cgColor
            mask.cornerCurve = .continuous
            mask.cornerRadius = radius
            mask.frame = FloatingSidebarGeometry.windowClip(window: window.frame, panel: host.frame)
            if content.mask !== mask { content.mask = mask }
        }
        CATransaction.commit()
    }

    /// The shadow follows the sidebar's frame, inside the shadow panel.
    private func placeShadow() {
        let s = slider.frame, pad = Metrics.shadowPad
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowView.frame = NSRect(x: s.minX, y: s.minY + pad, width: s.width, height: s.height)
        if let l = shadowView.layer {
            l.shadowColor = NSColor.black.cgColor
            l.shadowOpacity = Metrics.shadowOpacity
            l.shadowRadius = Metrics.shadowRadius
            l.shadowOffset = .zero
            // Only the shadow outside the sidebar: the translucent sidebar must not blur its own shadow.
            l.mask = shadowCutout
        }
        let body = CGPath(roundedRect: shadowView.bounds, cornerWidth: Metrics.cornerRadius, cornerHeight: Metrics.cornerRadius, transform: nil)
        let spread = Metrics.shadowSpread, r = Metrics.cornerRadius + spread
        shadowView.layer?.shadowPath = CGPath(roundedRect: shadowView.bounds.insetBy(dx: -spread, dy: -spread), cornerWidth: r, cornerHeight: r, transform: nil)
        let room = shadowView.bounds.insetBy(dx: -pad * 2, dy: -pad * 2)
        let cut = CGMutablePath()
        cut.addRect(room)
        cut.addPath(body)
        shadowCutout.frame = shadowView.bounds
        shadowCutout.path = cut
        CATransaction.commit()
    }

    private static let slideKey = "slide"

    /// Slides the sidebar (and its shadow) in or out from wherever it is on screen now: Arc's spring
    /// in, its eased hide out (#293).
    /// `entering`: the sidebar comes out from tucked away; the spring starts from there a beat late,
    /// because its first frames reach the screen ~2–3 frames after the animation is added, and those
    /// frames of the spring were lost (it appeared 25–40 % out, Arc's first frame is at 1 %).
    private func slide(shown: Bool, entering: Bool = false, completion: @escaping () -> Void) {
        guard let layer = slider.layer else { completion(); return }
        let from = entering ? layer.position.x : (layer.presentation()?.position.x ?? layer.position.x)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.frame = slideFrame(shown: shown)
        CATransaction.commit()
        placeShadow()
        let animation: CABasicAnimation
        if shown {
            let spring = CASpringAnimation()
            spring.mass = 1
            spring.stiffness = Metrics.revealStiffness
            spring.damping = Metrics.revealDamping
            spring.initialVelocity = Metrics.revealVelocity
            spring.duration = spring.settlingDuration
            if entering {
                spring.beginTime = CACurrentMediaTime() + Metrics.firstFrameDelay
                spring.fillMode = .backwards
            }
            animation = spring
        } else {
            animation = CABasicAnimation()
            animation.duration = Metrics.hideDuration
            let c = Metrics.hideCurve
            animation.timingFunction = CAMediaTimingFunction(controlPoints: c.0, c.1, c.2, c.3)
        }
        animation.keyPath = "position.x"
        animation.isAdditive = true
        animation.fromValue = from - layer.position.x
        animation.toValue = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        for l in [layer, shadowView.layer].compactMap({ $0 }) {
            l.removeAnimation(forKey: Self.slideKey)
            l.add(animation, forKey: Self.slideKey)
        }
        CATransaction.commit()
    }

    /// Both panels on the window, the shadow's under the sidebar's.
    private func attachPanels(_ p: NSPanel, _ s: NSPanel) {
        if s.parent !== window { window.addChildWindow(s, ordered: .above) }
        if p.parent !== window { window.addChildWindow(p, ordered: .above) }
        s.orderFront(nil)
        p.order(.above, relativeTo: s.windowNumber)
    }

    /// The shadow's panel and the sidebar's, bottom first, while they are on the window.
    var attachedPanels: [NSWindow] {
        guard let panel, panel.parent === window else { return [] }
        return [shadowPanel, panel].compactMap { $0 }
    }

    private func detachPanels() {
        for w in [panel, shadowPanel].compactMap({ $0 }) {
            window.removeChildWindow(w)
            w.orderOut(nil)
        }
    }

    private func makePanel() -> FloatingSidebarPanel {
        let p = FloatingSidebarPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        // A window shadow outlines the panel's shape with a hard rim; the shadow panel draws Arc's.
        p.hasShadow = false
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
        resizeHandle.onBegin = { [weak self] in self?.shell.resizeHandle.onBegin?() }
        resizeHandle.onResize = { [weak self] translation, speed in
            guard let self, let resize = shell.resizeHandle.onResize else { return }
            resize(translation, speed)
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
        // Not staged by the pointer's wait (a scripted or remote reveal): stage now, a beat before the
        // spring, because the panel reaches the screen a few frames after it is ordered in.
        let fresh = !shell.sidebarDetached
        if fresh { stage() }
        // From tucked away (not back from a hide in flight): the spring starts a beat late, see slide.
        let tucked = fresh || staged
        isShown = true
        staged = false
        dwell.reset()
        transitionGeneration &+= 1
        panel?.ignoresMouseEvents = false
        slide(shown: true, entering: tucked) {}
    }

    /// The sidebar into its panels, tucked out past the window's edge and drawn, the panels on the
    /// window but letting clicks through until it comes out.
    private func stage() {
        guard !shell.sidebarDetached else { return }
        staged = true
        transitionGeneration &+= 1
        let p = panel ?? makePanel()
        panel = p
        let s = shadowPanel ?? makeShadowPanel()
        shadowPanel = s
        p.setFrame(panelFrame, display: false)
        s.setFrame(shadowPanelFrame, display: false)
        placeClips()
        p.ignoresMouseEvents = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.frame = slideFrame(shown: false)
        CATransaction.commit()
        placeShadow()
        refreshBackdrop()
        let host = shell.sidebarHost
        host.removeFromSuperview()
        host.frame = slider.bounds
        host.autoresizingMask = [.width, .height]
        host.layer?.cornerRadius = 0
        slider.addSubview(host)
        // The window's own traffic lights hide with the sidebar; these stand in at the
        // same spot in the sidebar's top row. Full screen has none: Arc's floating sidebar there
        // starts with the toggle, as the docked one does (#315).
        if let lights = trafficLights {
            lights.setFrameOrigin(NSPoint(x: 13, y: slider.bounds.height - CraMetrics.titleRowCenter - lights.frame.height / 2))
            lights.isHidden = windowFullScreen()
            slider.addSubview(lights, positioned: .above, relativeTo: host)
        }
        let w = Metrics.resizeHandleWidth
        resizeHandle.frame = NSRect(x: slider.bounds.width - w, y: 0, width: w, height: slider.bounds.height)
        resizeHandle.isHidden = !shell.sidebarResizable
        slider.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
        shell.sidebarDetached = true
        shell.floatingSidebar = true
        attachPanels(p, s)
        didAttachPanel?()
        // Draw the sidebar in its new window now, so a spring that follows starts after that work and
        // not under it: at 120 fps its first ~50 ms never reached the screen (#293).
        p.displayIfNeeded()
        s.displayIfNeeded()
        CATransaction.flush()
    }

    /// The pointer left the strip before the wait was over: the sidebar goes home unseen.
    private func unstage() {
        guard staged, !isShown else { return }
        staged = false
        transitionGeneration &+= 1
        detachPanels()
        reattach(floating: false)
    }

    func hide(animated: Bool) {
        // A synchronous hide also finishes a hide already in flight (for example,
        // before a traffic-light action). Repeated animated exits do not restart it.
        guard isShown || (!animated && shell.sidebarDetached), panel != nil else { return }
        isShown = false
        staged = false
        dwell.reset()
        transitionGeneration &+= 1
        let generation = transitionGeneration
        let finish = { [weak self] in
            guard let self, self.transitionGeneration == generation, !self.isShown else { return }
            for l in [self.slider.layer, self.shadowView.layer] { l?.removeAnimation(forKey: Self.slideKey) }
            self.detachPanels()
            self.reattach(floating: false)
        }
        guard animated else { finish(); return }
        slide(shown: false) { finish() }
    }

    /// The sidebar is about to be anchored (⌘S while floating): put it back in the
    /// shell at its floating frame so the anchoring animation starts from there.
    func prepareForAnchoring() {
        transitionGeneration &+= 1
        // During the hide animation isShown is already false, but the view still
        // belongs to the panel and must come home before the anchoring animation.
        guard shell.sidebarDetached, panel != nil else { return }
        isShown = false
        staged = false
        dwell.reset()
        for l in [slider.layer, shadowView.layer] { l?.removeAnimation(forKey: Self.slideKey) }
        detachPanels()
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
        shadowPanel?.setFrame(shadowPanelFrame, display: true)
        placeClips()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.frame = slideFrame(shown: true)
        CATransaction.commit()
        placeShadow()
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
