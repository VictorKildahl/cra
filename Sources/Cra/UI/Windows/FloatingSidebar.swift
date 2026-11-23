import AppKit

/// Arc's floating sidebar: with the sidebar hidden, touching the window's left
/// edge slides the sidebar in over the page; it leaves when the pointer does.
/// With the sidebar on the right (#464) all of it happens at the right edge instead.
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
    /// Nothing may send the sidebar away on its own (requestAutomaticHide): a folder's preview beside it
    /// still belongs to it, or the window has no tab (SidebarPresentation.mayRetract, GitHub #483).
    var staysShown: () -> Bool = { false }
    /// Out whatever the pointer does, for a scenario on screen (cra://debug?floatingSidebar=hold), where
    /// the real pointer is somewhere else and the poll would send the sidebar away.
    var heldOut = false
    var palette: () -> SpacePalette
    /// Whether the browser window is in macOS full screen; the tests stand one in.
    lazy var windowFullScreen: () -> Bool = { [unowned self] in self.window.styleMask.contains(.fullScreen) }
    /// The browser window's corner radius (macOS's, larger than Arc's); the tests stand one in.
    lazy var windowCornerRadius: () -> CGFloat = { [unowned self] in LittleWindow.cornerRadius(of: self.window) }
    /// Called after the panel is attached so the overlay panel can be re-ordered above it.
    var didAttachPanel: (() -> Void)?

    private(set) var isShown = false {
        didSet { if isShown != oldValue { refreshPolling() } }
    }
    /// A completed hide must not take the panel away from a newer reveal or anchor.
    private var transitionGeneration: UInt64 = 0
    private var panel: FloatingSidebarPanel?
    /// The panel the sidebar slides out in, for a scenario's clicks (cra://debug?clickAt=…&target=floating).
    var panelWindow: NSWindow? { panel }
    /// The sidebar's shadow, in a panel of its own under the sidebar's that lets clicks through. The
    /// sidebar panel's window shadow drew a hard outline round it; Arc has only the soft shadow (#293).
    private var shadowPanel: NSPanel?
    private let shadowView = NSView()
    private let shadowCutout = CAShapeLayer()
    /// The window's rounded outline, one per panel: a child window isn't clipped by its parent (#341).
    private let panelClip = CALayer()
    private let shadowClip = CALayer()
    /// The pointer's wait in the reveal strip (#293).
    private var dwell = FloatingSidebarRevealDwell()
    /// Where the pointer rested when the sidebar went away without it moving (#635): the strip brings
    /// nothing out until the pointer moves from there (FloatingSidebarStillPointer).
    private(set) var stillPointer: CGPoint?
    /// The pointer's way out past the window's left edge, and its wait there (#350).
    private var offEdge = FloatingSidebarOffEdge()
    /// The clock the wait runs on; the tests stand one in.
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
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
        panelMoves.forEach(NotificationCenter.default.removeObserver)
        displayOptions.map(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private var poll: Timer?
    private var activation: [NSObjectProtocol] = []
    /// Either panel moved or resized while on the window: the shadow and the window's outline follow (#550).
    private var panelMoves: [NSObjectProtocol] = []

    private func followMoves(of p: NSWindow) {
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            panelMoves.append(NotificationCenter.default.addObserver(forName: name, object: p, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.panelMoved() }
            })
        }
    }

    private func panelMoved() {
        // While it docks the shadow stays put and fades; staging places it before the panels attach.
        guard dock == nil, let p = panel, p.parent === window else { return }
        clipToWindow()
        placeShadow()
    }
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
                MainActor.assumeIsolated {
                    self?.appActive = on
                    self?.refreshPolling()
                    if !on { self?.resignedActive() }
                }
            }
        }
        appActive = NSApp.isActive
        refreshPolling()
        displayOptions = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBackdrop() }
        }
    }

    /// Whether Cra is the active app, as the activation notifications last said.
    private var appActive = false

    /// The pointer matters only while Cra is active and the sidebar is hidden (it may come out) or out
    /// floating (it may leave). With the sidebar anchored, the timer was most of an idle Cra's
    /// wake-ups with its window in front.
    private func refreshPolling() {
        setPolling(appActive && (isShown || sidebarHidden()))
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

    /// The anchored sidebar was shown or hidden, or a page entered or left full screen.
    func sidebarVisibilityChanged() { refreshPolling() }

    private func pointerMoved() {
        guard NSApp.isActive, window.isVisible else { return }
        guard isShown || sidebarHidden() else { return }
        let screenPoint = NSEvent.mouseLocation
        pointerSample(at: shell.convert(window.convertPoint(fromScreen: screenPoint), from: nil))
    }

    /// One look at the pointer, in the shell's coordinates: the poll's, wherever the pointer is on
    /// screen (the tests stand one in).
    func pointerSample(at p: CGPoint) {
        guard isShown || sidebarHidden() else { return }
        if !isShown, pointerStillThere(p) { return }
        if !isShown {
            let t = now()
            guard sidebarHidden(), isKey else {
                offEdge.reset()
                wait(atEdge: false, over: dwell.sample(inStrip: false, at: t), why: "the edge strip", at: p)
                return
            }
            let inStrip = FloatingSidebarGeometry.shouldReveal(at: p, in: shell.bounds, edgeToEdge: shell.fillsWindow, side: side,
                                                               pageMargin: shell.pageMargin)
            // Thrown past the edge, out of the window: it comes out there as well (#350).
            let off = offEdge.sample(p, in: shell.bounds, sidebarWidth: shell.sidebarWidth, side: side, at: t)
            let stripOver = dwell.sample(inStrip: inStrip, at: t)
            wait(atEdge: inStrip || off != .away, over: stripOver || off == .reveal,
                 why: stripOver ? "the edge strip" : "past the window's edge", at: p)
        } else if FloatingSidebarGeometry.shouldHide(at: p, in: shell.bounds, sidebarWidth: shell.sidebarWidth,
                                                     pressedMouseButtons: NSEvent.pressedMouseButtons, edgeToEdge: shell.fillsWindow,
                                                     side: side, pageMargin: shell.pageMargin) {
            requestAutomaticHide()
        }
    }

    /// The sidebar would go on its own: the pointer moved away (the poll, or the shell's own tracking) or
    /// another app came to the front. It goes unless something keeps it out. The sidebar button and the
    /// window's own actions call `hide` and don't ask.
    func requestAutomaticHide() {
        guard isShown, !staysShown(), !heldOut else { return }
        hide(animated: true)
    }

    /// Cra stopped being the active app, and with it the poll that sends the sidebar away. One the
    /// pointer keeps out from beside the window goes now, as in Arc 1.172.2 (11 Nov 2026, #350: out with
    /// the pointer 100 pt left of the window, another app activated, back in 85 ms later). Over the
    /// window it stays as it did.
    func resignedActive(pointerAt p: CGPoint) {
        guard !shell.bounds.contains(p) else { return }
        requestAutomaticHide()
    }

    private func resignedActive() {
        resignedActive(pointerAt: shell.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    /// The shell saw the pointer move in the strip: a sample toward the same wait as the poll's, so a
    /// moving pointer can't skip it (#293).
    func edgeHovered() {
        guard !isShown, sidebarHidden(), isKey, !pointerStillThere(pointerInShell) else { return }
        edgeSample(inStrip: true)
    }

    /// The sidebar went away with no move of the pointer (a swipe out of the Library, ⇧⌘L or Esc out of a
    /// Library a hidden sidebar opened; #635): the strip under a resting pointer waits for it to move.
    func waitForPointerToMove(from p: CGPoint? = nil) {
        stillPointer = p ?? pointerInShell
        dwell.reset()
        offEdge.reset()
        if staged { unstage() }
    }

    /// Scenarios (#635): as if the pointer had moved since.
    func debugPointerMoved() { stillPointer = nil }

    /// Whether the pointer is still where it rested when the sidebar went away (and the strip waits).
    private func pointerStillThere(_ p: CGPoint) -> Bool {
        guard let still = stillPointer else { return false }
        if FloatingSidebarStillPointer.moved(from: still, to: p) { stillPointer = nil; return false }
        return true
    }

    private var pointerInShell: CGPoint { shell.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }

    /// The shell saw the pointer leave the sidebar over the window itself, where no page window takes
    /// the pointer (an empty window, GitHub #483).
    func edgeLeft() { requestAutomaticHide() }

    /// Docking a floating sidebar in place, on the window's own slide as its clock
    /// (ShellView.animateSidebar's `alongside` and `completion`): the panel grows from where the sidebar
    /// floats to the docked place while its corners square and its shadow fades, and `finishDock` hands
    /// the sidebar back to the window, where it then looks the same. Swapped out in one frame instead, the
    /// panel's body, corners and shadow went at once and the sidebar jumped by the floating margin.
    private var dock: (from: NSRect, to: NSRect, generation: UInt64)?

    func beginDock() -> Bool {
        guard isShown, let p = panel, p.parent === window else { return false }
        isShown = false
        staged = false
        revealRoom = 0
        dwell.reset()
        offEdge.reset()
        transitionGeneration &+= 1
        let dockedInShell = shell.frames(sidebarVisible: true, floating: false, fullscreen: shell.contentFullscreen,
                                         width: shell.sidebarWidth).sidebar
        let docked = window.convertToScreen(shell.convert(dockedInShell, to: nil))
        let current = p.convertToScreen(slider.frame)
        // One panel holds both places, so each frame only moves the sidebar inside it.
        let room = current.union(docked).intersection(window.frame)
        let from = current.offsetBy(dx: -room.minX, dy: -room.minY)
        // Set first: the shadow stays where it is while it fades, not re-placed by the panel's resize.
        dock = (from, docked.offsetBy(dx: -room.minX, dy: -room.minY), transitionGeneration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [slider.layer, shadowView.layer] { l?.removeAnimation(forKey: Self.slideKey) }
        p.setFrame(room, display: false)
        clipToWindow()
        slider.frame = from
        CATransaction.commit()
        return true
    }

    func dockProgress(_ progress: Double) {
        guard let d = dock, d.generation == transitionGeneration else { return }
        let k = CGFloat(min(max(progress, 0), 1))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * k }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.frame = NSRect(x: mix(d.from.minX, d.to.minX), y: mix(d.from.minY, d.to.minY),
                              width: mix(d.from.width, d.to.width), height: mix(d.from.height, d.to.height))
        slider.layer?.cornerRadius = Metrics.cornerRadius * (1 - k)
        CATransaction.commit()
        shadowPanel?.alphaValue = 1 - k
    }

    /// Whether it handed the sidebar back docked: false when another transition took it over meanwhile.
    @discardableResult
    func finishDock() -> Bool {
        guard let d = dock else { return false }
        dock = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.layer?.cornerRadius = Metrics.cornerRadius
        CATransaction.commit()
        shadowPanel?.alphaValue = 1
        // Hidden or shown again while it docked: that transition owns the sidebar now.
        guard d.generation == transitionGeneration else { return false }
        detachPanels()
        reattach(floating: false)
        return true
    }

    /// A swipe is bringing the Library in under the sidebar: it goes back toward the window's edge by
    /// `distance` as the Library comes (LibrarySwipe.floatingRetreat), and out again when the swipe
    /// turns back.
    func retreat(_ distance: CGFloat) {
        guard isShown, panel != nil, dock == nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [slider.layer, shadowView.layer] { l?.removeAnimation(forKey: Self.slideKey) }
        var f = slideFrame(shown: true)
        f.origin.x += side == .right ? distance : -distance
        slider.frame = f
        CATransaction.commit()
        placeShadow()
    }

    /// How far it has gone back, for a scenario.
    var retreatReadout: Int {
        guard isShown, panel != nil else { return 0 }
        return Int(abs(slideFrame(shown: true).minX - slider.frame.minX).rounded())
    }

    /// An empty window's hidden sidebar is held open (SidebarPresentation.heldOpen, GitHub #483): it comes
    /// out straight to its floating place, without the edge reveal's spring, as Arc's does when the window
    /// has no tab. The hover reveal is `show`.
    func showInPlace() {
        guard !isShown, sidebarHidden() else { return }
        if !shell.sidebarDetached { stage() }
        isShown = true
        staged = false
        dwell.reset()
        offEdge.reset()
        transitionGeneration &+= 1
        panel?.ignoresMouseEvents = false
        setRevealRoom(0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Back out of a hide still sliding (a tab opened, then the window was empty again): its slide
        // would keep drawing from where it was and snap back.
        for l in [slider.layer, shadowView.layer] { l?.removeAnimation(forKey: Self.slideKey) }
        slider.frame = slideFrame(shown: true)
        CATransaction.commit()
        placeShadow()
    }

    /// One look at the pointer while the sidebar is in. Arriving in the strip stages the sidebar (in its
    /// panel, tucked out of sight), so the costly part of a reveal happens during the wait: done at the
    /// reveal, it held the first frame back ~90 ms. Leaving before the wait is over puts it back.
    func edgeSample(inStrip: Bool) {
        // The wait runs from the sample, not from after the staging: that takes ~90 ms on the main thread.
        wait(atEdge: inStrip, over: dwell.sample(inStrip: inStrip, at: now()), why: "the edge strip", at: pointerInShell)
    }

    /// The pointer is at the edge (in the strip, or thrown past it) or not, and its wait is over or not.
    private func wait(atEdge: Bool, over: Bool, why: String, at p: CGPoint) {
        guard !isShown else { return }
        if atEdge, !shell.sidebarDetached { stage() }
        if !atEdge, staged { unstage() }
        if over { show(why: "\(why), pointer at \(Int(p.x)),\(Int(p.y))") }
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

    private var side: SidebarSide { shell.sidebarSide }

    /// The sidebar's floating frame on screen, from the shell's layout.
    private var targetFrame: NSRect {
        let f = shell.frames(sidebarVisible: false, floating: true, fullscreen: false, width: shell.sidebarWidth).sidebar
        return window.convertToScreen(shell.convert(f, to: nil))
    }

    /// The panel reaches from the window's left edge to the sidebar's right edge, so the
    /// sidebar slides in from the window edge and is clipped there (Arc draws it inside
    /// its window), instead of sliding across whatever lies left of the window. Its
    /// corners are cut to the window's rounded ones too (`clipToWindow`). On the right it reaches
    /// from the sidebar's left edge to the window's right one (#464).
    private var panelFrame: NSRect {
        let t = targetFrame, w = window.frame
        let f = side == .right
            ? NSRect(x: t.minX - revealRoom, y: t.minY, width: w.maxX - t.minX + revealRoom, height: t.height)
            : NSRect(x: w.minX, y: t.minY, width: t.maxX - w.minX + revealRoom, height: t.height)
        return f.intersection(w)
    }

    /// Room past the sidebar's resting edge (right of it, left on the right) while the reveal's spring runs: it swings ~4 pt past
    /// (Arc: 274 for 270). A panel that ended at the resting edge cut the sidebar off there while its
    /// shadow swung on (#350). Only for the spring: the panel takes clicks, and this strip is the page's.
    private var revealRoom: CGFloat = 0

    /// The sidebar inside the panel: in place, or tucked out past the window edge.
    private func slideFrame(shown: Bool) -> NSRect {
        // Where the panel is now: a hide drops the reveal's room without resizing it.
        let t = targetFrame, p = panel.map { $0.parent === window ? $0.frame : panelFrame } ?? panelFrame
        let tucked = side == .right ? p.width : -t.width
        return NSRect(x: shown ? t.minX - p.minX : tucked, y: 0, width: t.width, height: t.height)
    }

    /// The shadow panel: the sidebar panel with room for the shadow right, above and below. It
    /// starts at the window's edge too, so the shadow is clipped there with the sidebar.
    /// Never past the window's frame: what would reach past it is cut off by the window's outline
    /// anyway, and a panel that reached above a window zoomed to the screen lay under the menu bar,
    /// where macOS backs the menu bar over any window beneath it. That hid the browser window's own
    /// shadow and dark outline along its top edge for as long as the sidebar was out (#350).
    private var shadowPanelFrame: NSRect {
        let f = panelFrame, pad = Metrics.shadowPad
        return NSRect(x: side == .right ? f.minX - pad : f.minX, y: f.minY - pad, width: f.width + pad, height: f.height + 2 * pad)
            .intersection(window.frame)
    }

    /// Each panel is clipped to the window's rounded outline. A child window is not clipped by its
    /// parent, so the panels' straight cut at the window's edge left the sidebar sliding in (and its
    /// shadow) square past the window's rounded corners; Arc draws it inside its window, which
    /// clips it there (#341).
    private func clipToWindow() {
        let radius = windowFullScreen() ? 0 : windowCornerRadius()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (p, clip) in [(panel as NSPanel?, panelClip), (shadowPanel, shadowClip)] {
            guard let p, let layer = p.contentView?.layer else { continue }
            clip.backgroundColor = NSColor.black.cgColor
            clip.cornerRadius = radius
            clip.cornerCurve = .continuous
            clip.frame = window.frame.offsetBy(dx: -p.frame.minX, dy: -p.frame.minY)
            if layer.mask !== clip { layer.mask = clip }
        }
        CATransaction.commit()
    }

    private func makeShadowPanel() -> NSPanel {
        let p = FloatingSidebarShadowPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
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
        followMoves(of: p)
        return p
    }

    /// The shadow follows the sidebar's frame, inside the shadow panel: from where both panels really
    /// are, so a panel moved by anyone but the controller still has the shadow under the sidebar (#550).
    private func placeShadow() {
        let s = slider.frame, pad = Metrics.shadowPad
        let sidebarOrigin = panel?.frame.origin ?? panelFrame.origin
        let shadowOrigin = shadowPanel?.frame.origin ?? shadowPanelFrame.origin
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowView.frame = s.offsetBy(dx: sidebarOrigin.x - shadowOrigin.x, dy: sidebarOrigin.y - shadowOrigin.y)
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
            // Arc's reveal (CraCore's FloatingSidebarSpring): lands in ~0.115 s, swings ~4 pt past, settles by ~0.25 s.
            let arc = FloatingSidebarSpring.reveal(travel: Double(shell.sidebarWidth + FloatingSidebarGeometry.margin))
            let spring = CASpringAnimation()
            spring.mass = 1
            spring.stiffness = CGFloat(arc.stiffness)
            spring.damping = CGFloat(arc.damping)
            spring.initialVelocity = CGFloat(arc.initialVelocity)
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
        followMoves(of: p)
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
        // Translucent sidebar (#366): the HUD material, which lets the page under the panel through;
        // underWindowBackground is close to opaque.
        blur.material = pal.glass ? .hudWindow : pal.isDark ? .underWindowBackground : t.material
        blur.appearance = NSAppearance(named: pal.glass ? (pal.isDark ? .darkAqua : .aqua) : t.darkBlur ? .darkAqua : .aqua)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Translucent sidebar (#366): the page under the panel shows through, darkened rather than greyed.
        let amount = pal.glass ? SidebarGlass.floatingLift(dark: pal.isDark, reduceTransparency: reduce, lift: t.liftActive)
            : SidebarBackdrop.floatingLift(dark: pal.isDark, reduceTransparency: reduce, lift: t.liftActive)
        lift.layer?.backgroundColor = NSColor(white: 1, alpha: amount).cgColor
    }

    /// `why`, for cra.log: what brought it out (#679 asks what brought it back after a swipe out of the
    /// Library on a reporter's Mac, where no test made it come back).
    func show(why: String = "asked") {
        guard !isShown, sidebarHidden() else { return }
        CraLog.note("floating sidebar out: \(why)")
        // Not staged by the pointer's wait (a scripted or remote reveal): stage now, a beat before the
        // spring, because the panel reaches the screen a few frames after it is ordered in.
        let fresh = !shell.sidebarDetached
        if fresh { stage() }
        // From tucked away (not back from a hide in flight): the spring starts a beat late, see slide.
        let tucked = fresh || staged
        isShown = true
        staged = false
        dwell.reset()
        offEdge.reset()
        transitionGeneration &+= 1
        panel?.ignoresMouseEvents = false
        // Staged with it already; back from a hide in flight it is set here.
        setRevealRoom(ceil(FloatingSidebarGeometry.revealOvershoot(sidebarWidth: shell.sidebarWidth)) + 2)
        let generation = transitionGeneration
        slide(shown: true, entering: tucked) { [weak self] in
            guard let self, self.transitionGeneration == generation, self.isShown else { return }
            self.setRevealRoom(0)
        }
    }

    private func setRevealRoom(_ room: CGFloat) {
        guard room != revealRoom else { return }
        revealRoom = room
        guard let p = panel, p.parent === window else { return }
        p.setFrame(panelFrame, display: false)
        shadowPanel?.setFrame(shadowPanelFrame, display: false)
        clipToWindow()
        // On the right the room is on the panel's leading side, so the sidebar's place in it moves.
        guard side == .right, slider.layer?.animation(forKey: Self.slideKey) == nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.frame = slideFrame(shown: isShown)
        CATransaction.commit()
        placeShadow()
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
        // Room for the reveal's swing from the start, so nothing is resized as the spring begins.
        revealRoom = ceil(FloatingSidebarGeometry.revealOvershoot(sidebarWidth: shell.sidebarWidth)) + 2
        p.setFrame(panelFrame, display: false)
        s.setFrame(shadowPanelFrame, display: false)
        clipToWindow()
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
            lights.setFrameOrigin(NSPoint(x: TrafficLightLayout.leading, y: slider.bounds.height - CraMetrics.titleRowCenter - lights.frame.height / 2))
            lights.isHidden = windowFullScreen()
            slider.addSubview(lights, positioned: .above, relativeTo: host)
        }
        // The resize edge is the one beside the page: the right one, or the left on the right (#464).
        let w = Metrics.resizeHandleWidth
        resizeHandle.side = side
        resizeHandle.autoresizingMask = side == .right ? [.maxXMargin, .height] : [.minXMargin, .height]
        resizeHandle.frame = NSRect(x: side == .right ? 0 : slider.bounds.width - w, y: 0, width: w, height: slider.bounds.height)
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
        if isShown { CraLog.note("floating sidebar in\(animated ? "" : " at once")") }
        revealRoom = 0
        isShown = false
        staged = false
        dwell.reset()
        offEdge.reset()
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
        revealRoom = 0
        isShown = false
        staged = false
        dwell.reset()
        offEdge.reset()
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

    /// For `cra://debug?windowState`: the window edge the floating sidebar comes out at and how far in
    /// it rests, e.g. `right 5` (#464); `none` while it is in.
    var edgeReadout: String {
        guard isShown, let p = panel, p.parent === window else { return "none" }
        let w = window.frame, f = p.frame
        let s = p.convertToScreen(slider.convert(slider.bounds, to: nil))
        if abs(f.minX - w.minX) < 0.5 { return "left \(Int((s.minX - w.minX).rounded()))" }
        if abs(f.maxX - w.maxX) < 0.5 { return "right \(Int((w.maxX - s.maxX).rounded()))" }
        return "none"
    }

    /// For `cra://debug?windowState`: where the shadow's body lies against the sidebar on screen, its left,
    /// bottom, right and top edges' distance from the sidebar's (`0,0,0,0` under it), then how far below the
    /// window's top the sidebar rests, e.g. `0,0,0,0 top 5` (#550); `-` while it is in.
    var shadowReadout: String {
        guard isShown, let p = panel, p.parent === window, let s = shadowPanel else { return "-" }
        let body = p.convertToScreen(slider.convert(slider.bounds, to: nil))
        let cast = s.convertToScreen(shadowView.convert(shadowView.bounds, to: nil))
        let d = [cast.minX - body.minX, cast.minY - body.minY, cast.maxX - body.maxX, cast.maxY - body.maxY]
        return d.map { String(format: "%g", ($0 * 2).rounded() / 2) }.joined(separator: ",")
            + String(format: " top %g", ((window.frame.maxY - body.maxY) * 2).rounded() / 2)
    }

    /// Window moved or resized while floating.
    func reposition() {
        guard isShown, let p = panel else { return }
        p.setFrame(panelFrame, display: true)
        shadowPanel?.setFrame(shadowPanelFrame, display: true)
        clipToWindow()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slider.frame = slideFrame(shown: true)
        CATransaction.commit()
        placeShadow()
    }
}

/// The sidebar's panels rest where the controller puts them, inside the browser window. AppKit's
/// constraint keeps a window clear of the menu bar: it moves a panel 5 pt in from the screen's bottom and
/// 10 pt shorter than the screen (the sidebar's in full screen) down 5 pt, and leaves the full-height
/// shadow panel. On macOS 27.2 the full-screen sidebar rested 10 pt from the top with its shadow 5 pt
/// above it, and the page showed between them as a halo (#550); 26.7 never asks for the constraint.
class FloatingSidebarPanelBase: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Carries the sidebar's shadow under the sidebar's panel, letting clicks through.
final class FloatingSidebarShadowPanel: FloatingSidebarPanelBase {}

final class FloatingSidebarPanel: FloatingSidebarPanelBase {
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
        // Spaced like the window's own buttons, which keep the system's gaps (#445).
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let system = types.compactMap { browserWindow.standardWindowButton($0).map { Double($0.frame.minX) } }
        let xs = system.count == types.count ? TrafficLightLayout.originsX(system: system, leading: 0) : [0, 20, 40]
        for (i, type) in types.enumerated() {
            guard let b = NSWindow.standardWindowButton(type, for: browserWindow.styleMask) else { continue }
            b.setFrameOrigin(NSPoint(x: CGFloat(xs[i]), y: 0))
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
