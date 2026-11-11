import AppKit

@main
enum FloatingSidebarTests {
    private static var checks = 0

    @MainActor
    static func main() {
        geometry()
        revealsOverAFullscreenPage()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1400, height: 880),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let shell = ShellView(frame: NSRect(origin: .zero, size: window.frame.size))
        window.contentView = shell
        let sidebar = FloatingSidebarController(shell: shell, window: window, palette: { SpacePalette() })
        sidebar.sidebarHidden = { true }
        // Do not install the pointer timer or post input events. The real controller
        // and AppKit animation completions run with an offscreen disposable panel.
        sidebar.show()
        expect(sidebar.isShown && shell.sidebarDetached, "show attaches the sidebar to its panel")
        let panel = window.childWindows!.first { $0 is FloatingSidebarPanel }!
        arcsReveal(window: window, sidebar: sidebar, panel: panel)

        sidebar.hide(animated: true)
        expect(!sidebar.isShown && shell.sidebarDetached, "animated hide remains in flight before completion")
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && shell.sidebarDetached && panel.parent === window && panel.isVisible,
               "an old hide completion must not remove a newly revealed panel")
        expect(shell.sidebarHost.window === panel, "the revealed sidebar retains its native panel owner")

        // The floating sidebar's edge drags the width through the shell's handle.
        var saved: CGFloat?
        shell.resizeHandle.onDrag = { shell.sidebarWidth += $0 }
        shell.resizeHandle.onEnd = { saved = shell.sidebarWidth }
        let edge = shell.sidebarHost.superview?.subviews.compactMap { $0 as? ResizeHandleView }.first
        expect(edge.map { !$0.isHidden && abs($0.frame.maxX - shell.sidebarHost.frame.maxX) < 0.5 } == true,
               "the floating sidebar has a resize strip on its right edge")
        let panelWidth = panel.frame.width
        edge?.onDrag?(40)
        edge?.onEnd?()
        expect(shell.sidebarWidth == 368 && saved == 368, "dragging the floating edge resizes and saves the width")
        expect(panel.frame.width == panelWidth + 40 && shell.sidebarHost.frame.width == 368
               && abs(edge!.frame.maxX - shell.sidebarHost.frame.maxX) < 0.5,
               "the panel, sidebar and strip follow the new width")
        edge?.onDrag?(-40)
        // A whole drag from the floating edge reaches the shell's handle too (#287: Arc's resize
        // works from the start width and the pointer's speed).
        var began = false, got: (CGFloat, CGFloat)?
        shell.resizeHandle.onBegin = { began = true }
        shell.resizeHandle.onResize = { t, v in got = (t, v); shell.sidebarWidth = 328 + t }
        edge?.onBegin?()
        edge?.onResize?(20, 15)
        expect(began && got.map { $0 == 20 && $1 == 15 } == true && shell.sidebarHost.frame.width == 348,
               "the floating edge hands the drag's start, translation and speed to the shell")
        shell.resizeHandle.onResize?(0, 0)
        shell.resizeHandle.onBegin = nil
        shell.resizeHandle.onResize = nil
        shell.resizeHandle.onDrag = nil
        shell.resizeHandle.onEnd = nil

        // Multiple animation completions can be queued; only the latest show owns it.
        sidebar.hide(animated: true)
        sidebar.show()
        sidebar.hide(animated: true)
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && shell.sidebarDetached && panel.parent === window && panel.isVisible,
               "rapid edge re-entry leaves the latest reveal visible")

        sidebar.hide(animated: true)
        sidebar.prepareForAnchoring()
        expect(!sidebar.isShown && !shell.sidebarDetached && shell.sidebarHost.superview === shell,
               "anchoring during hide immediately brings the sidebar home")
        expect(shell.floatingSidebar && panel.parent == nil && !panel.isVisible,
               "anchoring preserves the floating start frame while removing its panel")
        drainAnimations()
        expect(shell.floatingSidebar && shell.sidebarHost.superview === shell,
               "a stale hide completion must not overwrite the anchoring start state")

        sidebar.show()
        sidebar.hide(animated: true)
        sidebar.hide(animated: false)
        expect(!shell.sidebarDetached && panel.parent == nil && !panel.isVisible,
               "a synchronous hide finishes an in-flight animated hide immediately")
        drainAnimations()
        expect(!sidebar.isShown && !shell.sidebarDetached && !panel.hasShadow,
               "late show and hide completions cannot revive a hidden panel or shadow")

        sidebar.show()
        sidebar.hide(animated: true)
        drainAnimations()
        expect(!sidebar.isShown && !shell.sidebarDetached && !shell.floatingSidebar,
               "an uninterrupted hide still reattaches the sidebar normally")

        onlyTheKeyWindowReveals(window: window, sidebar: sidebar, panel: panel)
        pointerPastTheLeftEdge(window: window, sidebar: sidebar)
        theRevealSwingsPastItsEdge(window: window, sidebar: sidebar, panel: panel)
        thePanelsStayInsideTheWindow(window: window, sidebar: sidebar, panel: panel)
        noStandInLightsInFullScreen(sidebar: sidebar, panel: panel)
        staysInsideTheWindowsCorners(window: window, sidebar: sidebar, panel: panel)

        // #136: the pointer is sampled only while Cra is the active app.
        sidebar.install()
        expect(!sidebar.isPolling, "an inactive app installs no pointer timer")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        expect(sidebar.isPolling, "becoming active starts the pointer timer")
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        expect(!sidebar.isPolling, "leaving the app stops it")
        window.close()
        print("Floating sidebar: \(checks) checks passed")
    }

    /// GitHub #82: like Arc, only the key window's hidden sidebar comes out on hover, so a window
    /// behind another can't reveal over it. The key window may be one of its own children (the
    /// page, DevTools, the floating panel); with Cra inactive, none reveals.
    // promise: #82
    @MainActor
    private static func onlyTheKeyWindowReveals(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        let page = NSWindow(contentRect: NSRect(x: -9990, y: -9990, width: 1380, height: 860),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        page.isReleasedWhenClosed = false
        window.addChildWindow(page, ordered: .above)
        let front = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        front.isReleasedWhenClosed = false
        var key: NSWindow? = window
        sidebar.keyWindow = { key }
        expect(sidebar.isKey, "the key window reveals")
        key = page
        expect(sidebar.isKey, "its page being key counts as the window")
        sidebar.show()
        key = panel
        expect(sidebar.isKey, "its floating panel being key counts as the window")
        sidebar.hide(animated: false)
        key = front
        expect(!sidebar.isKey, "a window behind the key window does not reveal")
        key = nil
        expect(!sidebar.isKey, "no key window (Cra inactive) does not reveal")
        window.removeChildWindow(page)
        page.close()
        front.close()
    }

    // promise: #24
    /// Where the pointer reveals and hides the floating sidebar; edge to edge, with no margin, only
    /// Arc's 5 pt strip over the page reveals it (#24).
    private static func geometry() {
        // Nonzero bounds also check that both paths use shell-local geometry.
        let bounds = CGRect(x: 20, y: 10, width: 1400, height: 880)
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 20, y: 100), in: bounds), "left edge reveals")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 30, y: 100), in: bounds), "the whole 10 pt margin reveals")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 30.1, y: 100), in: bounds), "page content does not reveal")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 16, y: 100), in: bounds), "just outside the window reveals, as in Arc")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 15.9, y: 100), in: bounds), "further outside does not reveal")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 9.9), in: bounds), "above the window does not reveal")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 890.1), in: bounds), "below the window does not reveal")
        // Edge to edge (GitHub #24) there is no margin; only Arc's 5 pt strip over the page reveals.
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25, y: 100), in: bounds, edgeToEdge: true), "edge to edge: 5 pt reveals")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25.1, y: 100), in: bounds, edgeToEdge: true), "edge to edge: the page past 5 pt does not reveal")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 16, y: 100), in: bounds, edgeToEdge: true), "edge to edge: just outside the window still reveals")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 24, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0, edgeToEdge: true),
               "edge to edge: the reveal strip does not hide what it revealed")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 17, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "the outside reveal strip does not hide what it revealed")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "panel margin and leave slack are included in the retention boundary")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the shared retention boundary hides after release")
        // Beside the window, left of it, the sidebar stays out since #350; above, below and further left it goes.
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 22, y: 9.9), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0)
               && FloatingSidebarGeometry.shouldHide(at: CGPoint(x: -300.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the window hides after release")
        for button in [1, 2, 4] {
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar beyond the leave slack during a gesture")
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 22, y: 9.9), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar outside the moving window during a gesture")
        }
    }

    // promise: #350
    /// GitHub #350: a pointer thrown past the window's left edge brings the hidden sidebar out, and it
    /// stays out while the pointer is beside the window, as in Arc 1.172.2 (the reporter's recording,
    /// and Arc driven at 120 fps, 11 Nov 2026). Cra revealed only in a 14 pt strip at the edge, so a
    /// hand that overshot a window standing clear of the screen's edge got nothing.
    @MainActor
    private static func pointerPastTheLeftEdge(window: NSWindow, sidebar: FloatingSidebarController) {
        // Arc's zone for a 264 pt sidebar: out at 250 pt left of the window, not at 270; a sidebar
        // that is out leaves at 252-257. The strip's own 4 pt outside the window are not part of it.
        let bounds = CGRect(x: 20, y: 10, width: 1400, height: 880)
        func off(_ x: CGFloat, _ y: CGFloat = 100) -> Bool {
            FloatingSidebarGeometry.isOffLeftEdge(CGPoint(x: x, y: y), in: bounds, sidebarWidth: 264)
        }
        expect(off(15.9) && off(-80) && off(-230), "beside the window, left of it, is off the edge")
        expect(off(-236) && !off(-236.1), "as far out as the sidebar is wide, less its margin (256 pt for 264)")
        expect(!off(16) && !off(20) && !off(300), "the strip and the window are not")
        expect(!off(-80, 9.9) && !off(-80, 890.1), "nor is anything above or below the window")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: -80, y: 100), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "a sidebar that is out stays out with the pointer beside the window")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: -236.1, y: 100), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "further left than that it goes")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: -80, y: 890.1), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "above the window it goes")

        // The poll's samples, in the shell's coordinates (328 pt sidebar: 320 pt of room).
        let shell = sidebar.shell
        var clock: TimeInterval = 500
        sidebar.now = { clock }
        sidebar.keyWindow = { window }
        sidebar.hide(animated: false)
        let mid = shell.bounds.midY
        func sample(_ x: CGFloat, _ y: CGFloat, at t: TimeInterval) {
            clock = t
            sidebar.pointerSample(at: CGPoint(x: x, y: y))
        }
        // A throw from the page to 100 pt outside the window, then at rest.
        sample(300, mid, at: 500)
        expect(!sidebar.isShown && !sidebar.staged, "the pointer over the page leaves the sidebar in")
        sample(-100, mid, at: 500.033)
        expect(!sidebar.isShown && sidebar.staged, "past the left edge the wait starts, as it does in the strip")
        sample(-100, mid, at: 500.1)
        expect(!sidebar.isShown, "it waits for the pointer to rest out there")
        sample(-100, mid, at: 500.133)
        expect(sidebar.isShown, "then the sidebar comes out with the pointer 100 pt outside the window")
        sample(-100, mid + 150, at: 501)
        expect(sidebar.isShown, "and stays out while the pointer is beside the window")
        sample(120, mid, at: 501.1)
        expect(sidebar.isShown, "coming back in over the sidebar keeps it")
        sample(-100, mid, at: 501.2)
        sample(-100, shell.bounds.maxY + 30, at: 501.3)
        expect(!sidebar.isShown, "above the window's top it goes, as in Arc")
        sidebar.hide(animated: false)
        // Arc: a pointer that arrives beside the window from outside brings nothing out.
        for (i, t) in [502.0, 502.2, 502.5].enumerated() { sample(-100 - CGFloat(i), mid, at: t) }
        expect(!sidebar.isShown && !sidebar.staged, "coming back down beside the window brings nothing out")
        sample(-400, mid, at: 503)
        for (i, t) in [503.1, 503.3, 503.6].enumerated() { sample(-60 - CGFloat(i), mid, at: t) }
        expect(!sidebar.isShown && !sidebar.staged, "nor does a pointer that comes from further left")
        // Still moving out there: Arc starts ~70 ms later than for a pointer at rest.
        sample(300, mid, at: 510)
        for (i, t) in [510.033, 510.067, 510.1, 510.133, 510.167].enumerated() { sample(-20 - 15 * CGFloat(i), mid, at: t) }
        expect(!sidebar.isShown && sidebar.staged, "a pointer that keeps moving waits longer than one at rest")
        sample(-100, mid, at: 510.2)
        expect(sidebar.isShown, "and brings it out 0.15 s after it left the window")
        sidebar.hide(animated: false)
        // Out 40 pt and straight back over the page: nothing (Arc, out and in within 30 ms).
        sample(300, mid, at: 520)
        sample(-40, mid, at: 520.02)
        expect(sidebar.staged, "out past the edge")
        sample(60, mid, at: 520.05)
        sample(60, mid, at: 520.3)
        expect(!sidebar.isShown && !sidebar.staged, "a pointer that is back over the page before the wait ends shows nothing")
        // A slow exit goes through the strip; the wait carries on outside.
        sample(300, mid, at: 530)
        sample(4, mid, at: 530.03)
        sample(-10, mid, at: 530.06)
        expect(sidebar.staged && !sidebar.isShown, "through the strip and out: still waiting")
        sample(-10, mid, at: 530.15)
        expect(sidebar.isShown, "at rest 10 pt outside the window it comes out")
        sample(700, mid, at: 531)
        expect(!sidebar.isShown, "on to the page sends it away")
        sidebar.hide(animated: false)
        // Another app comes to the front with the pointer beside the window: the sidebar goes (Arc: 85 ms
        // later). Cra's poll stops then, so nothing else would send it away.
        sample(300, mid, at: 535)
        for t in [535.03, 535.2] { sample(-100, mid, at: t) }
        expect(sidebar.isShown, "out, the pointer beside the window")
        sidebar.resignedActive(pointerAt: CGPoint(x: -100, y: mid))
        expect(!sidebar.isShown, "Cra no longer the active app: it goes")
        sidebar.hide(animated: false)
        sidebar.show()
        sidebar.resignedActive(pointerAt: CGPoint(x: 120, y: mid))
        expect(sidebar.isShown, "with the pointer over the window it stays, as before")
        sidebar.hide(animated: false)
        // Only the key window's sidebar comes out, out there as at the edge (#82).
        sidebar.keyWindow = { nil }
        sample(300, mid, at: 540)
        for t in [540.03, 540.2, 540.4] { sample(-100, mid, at: t) }
        expect(!sidebar.isShown && !sidebar.staged, "a window that isn't key brings nothing out")
        sidebar.keyWindow = { window }
        sidebar.now = { ProcessInfo.processInfo.systemUptime }
    }

    // promise: #350
    /// GitHub #350, seen by Victor in the fixed build: the reveal's spring swings past the sidebar's
    /// resting place (Arc 1.172.2: 274 for 270). Cra's panel ended at the resting edge, so the
    /// sidebar's right side was cut off there while its shadow swung on, and its left side, resting 8 pt
    /// in, uncovered 2-3 pt of the page. The panel has room for the swing while the spring runs, and
    /// the sidebar rests 5 pt in, as Arc's does.
    @MainActor
    private static func theRevealSwingsPastItsEdge(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        let shell = sidebar.shell
        sidebar.hide(animated: false)
        sidebar.show()
        let resting = shell.sidebarHost.superview!.frame.maxX
        expect(shell.sidebarHost.superview!.frame.minX == 5, "the floating sidebar rests 5 pt inside the window, as in Arc")
        expect(panel.frame.width >= resting + FloatingSidebarGeometry.revealOvershoot(sidebarWidth: shell.sidebarWidth),
               "while the spring runs the panel reaches past the sidebar's resting edge, so the swing isn't cut off")
        drainAnimations()
        expect(sidebar.isShown && panel.frame.width == resting, "once it has settled the panel ends at the sidebar's edge again")
        // A hide that interrupts the spring leaves nothing behind for the next reveal.
        sidebar.hide(animated: false)
        sidebar.show()
        sidebar.hide(animated: true)
        drainAnimations()
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && panel.frame.width == resting, "a reveal after an interrupted one settles the same way")
        sidebar.hide(animated: false)
    }

    // promise: #350
    /// GitHub #350, seen by Victor with the window zoomed to the screen: as the hidden sidebar came out,
    /// the window's shadow and its dark outline went away along its whole top edge, and came back when
    /// the sidebar left. The click-through panel that carries the sidebar's shadow reached 11 pt above
    /// the window (8 before the sidebar moved 3 pt out), under the menu bar, and macOS gives the menu
    /// bar its frosted backing over any window that lies under it, which covers the shadow behind it.
    /// What reaches past the window is cut off by the window's outline anyway (#341).
    @MainActor
    private static func thePanelsStayInsideTheWindow(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        sidebar.hide(animated: false)
        sidebar.show()
        let shadow = window.childWindows!.first { $0 !== panel && $0.ignoresMouseEvents }!
        for (name, p) in [("sidebar", panel), ("shadow", shadow)] {
            expect(window.frame.contains(p.frame), "the \(name) panel stays inside the window's frame while the sidebar comes out")
        }
        drainAnimations()
        for (name, p) in [("sidebar", panel), ("shadow", shadow)] {
            expect(window.frame.contains(p.frame), "the \(name) panel stays inside the window's frame at rest")
        }
        let slider = shell_slider(panel)!, carrier = shadow.contentView!.subviews.first!
        let body = panel.convertToScreen(slider.convert(slider.bounds, to: nil))
        let cast = shadow.convertToScreen(carrier.convert(carrier.bounds, to: nil))
        expect(abs(body.minX - cast.minX) < 0.01 && abs(body.minY - cast.minY) < 0.01 && body.size == cast.size,
               "the shadow still sits under the sidebar")
        expect(shadow.frame.maxX > panel.frame.maxX && shadow.frame.maxX <= window.frame.maxX,
               "with room for it beside the sidebar, inside the window")
        // A window barely wider than its sidebar: neither panel passes its right edge.
        let wide = sidebar.shell.sidebarWidth
        sidebar.hide(animated: false)
        sidebar.shell.sidebarWidth = window.frame.width - 6
        sidebar.show()
        expect(window.frame.contains(panel.frame) && window.frame.contains(shadow.frame), "nor in a window as narrow as its sidebar")
        sidebar.hide(animated: false)
        sidebar.shell.sidebarWidth = wide
    }

    // promise: #315
    /// GitHub #315: the hidden sidebar comes out at the left edge over a page in full screen (a video),
    /// as in Arc 1.172.1 (offline copy, 10 Nov 2026: the floating sidebar over a full-screen element).
    /// A sidebar shown beside the page is out of sight while the page is full screen, so it may come
    /// out then too (inferred, not measured).
    private static func revealsOverAFullscreenPage() {
        expect(FloatingSidebarGeometry.mayReveal(sidebarShown: false, pageFullscreen: true),
               "the hidden sidebar comes out over a page in full screen")
        expect(FloatingSidebarGeometry.mayReveal(sidebarShown: true, pageFullscreen: true),
               "a shown sidebar, out of sight under the page's full screen, comes out too")
        expect(FloatingSidebarGeometry.mayReveal(sidebarShown: false, pageFullscreen: false),
               "the hidden sidebar comes out in a window")
        expect(!FloatingSidebarGeometry.mayReveal(sidebarShown: true, pageFullscreen: false),
               "a sidebar beside the page doesn't float")
    }

    // promise: #293
    /// GitHub #293: the hidden sidebar is less jumpy, as in Arc 1.172.1 (120 fps, 9 Nov 2026). The pointer
    /// waits 0.1 s in the strip before it comes out, so brushing the edge doesn't flash it; it stays out
    /// until 81 pt past its width; it springs in and eases out on Arc's curves; and its shadow is a soft
    /// one under it, not the hard outline a window shadow drew round the panel.
    @MainActor
    private static func arcsReveal(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        var dwell = FloatingSidebarRevealDwell()
        expect(!dwell.sample(inStrip: true, at: 10.0), "arriving at the edge doesn't reveal at once")
        expect(!dwell.sample(inStrip: true, at: 10.06), "nor 60 ms later")
        expect(!dwell.sample(inStrip: false, at: 10.08), "leaving the strip doesn't reveal")
        expect(!dwell.sample(inStrip: true, at: 10.12), "coming back starts the wait over")
        expect(!dwell.sample(inStrip: true, at: 10.206), "a brush Arc ignored (86 ms) doesn't reveal")
        expect(!dwell.sample(inStrip: true, at: 10.219), "nor anything shorter than Arc's wait")
        expect(dwell.sample(inStrip: true, at: 10.22), "0.1 s in the strip reveals")
        dwell.reset()
        expect(!dwell.sample(inStrip: true, at: 11), "after a reveal the next one waits again")

        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 950)
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 344, y: 300), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "a 264 pt sidebar stays out with the pointer at x 344, as in Arc")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 346, y: 300), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "and goes at x 346, where Arc's went")

        expect(!panel.hasShadow, "the sidebar's panel draws no window shadow (its rim outlined the sidebar)")
        let shadow = window.childWindows!.first { $0 !== panel && $0.ignoresMouseEvents }
        expect(shadow != nil, "a click-through panel carries the sidebar's shadow")
        let order = window.childWindows!
        let shell = sidebar.shell
        expect(shadow.map { s in order.firstIndex { $0 === s }! < order.firstIndex { $0 === panel }! } == true,
               "the shadow sits under the sidebar")
        let layer = shadow?.contentView?.subviews.first?.layer
        expect(layer.map { $0.shadowOpacity > 0 && $0.shadowPath != nil && $0.mask != nil } == true,
               "the shadow is a soft layer shadow with the sidebar cut out of it")
        let slider = shell_slider(panel)
        let spring = slider?.layer?.animation(forKey: "slide") as? CASpringAnimation
        // Arc's spring, refitted on 11 Nov (#350): the 9 Nov one (759, 46.3, 23.3) swung 2 % past, Arc's 1.5 %.
        let arc = FloatingSidebarSpring.reveal(travel: Double(sidebar.shell.sidebarWidth + FloatingSidebarGeometry.margin))
        expect(spring.map { $0.stiffness == CGFloat(arc.stiffness) && $0.damping == CGFloat(arc.damping)
                   && $0.initialVelocity == CGFloat(arc.initialVelocity) && $0.isAdditive } == true,
               "the reveal is Arc's spring")
        expect(arc.stiffness == 1134 && arc.initialVelocity == 9.1 && arc.damping > 54 && arc.damping < 58,
               "Arc's stiffness and start, damped a little more for a sidebar wider than Arc's 264 pt")
        sidebar.hide(animated: true)
        let ease = slider?.layer?.animation(forKey: "slide")
        expect(ease.map { !($0 is CASpringAnimation) && abs($0.duration - 0.102) < 0.001 } == true, "the hide is Arc's 0.1 s ease")
        expect(shadow?.parent === window, "the shadow leaves with the sidebar, not before it")
        drainAnimations()
        expect(shadow?.parent == nil && shadow?.isVisible == false, "and is gone once the sidebar is")
        // The shell's own mouse-moved path waits too: it used to call show() at once, which is how the
        // edge still flashed with the poll's wait in place.
        var clock: TimeInterval = 100
        sidebar.now = { clock }
        sidebar.keyWindow = { window }
        sidebar.hide(animated: false)
        sidebar.edgeHovered()
        expect(!sidebar.isShown, "a move into the strip doesn't reveal at once")
        expect(sidebar.staged && shell.sidebarDetached && panel.parent === window && panel.ignoresMouseEvents,
               "it stages the sidebar in its panel during the wait, out of sight and letting clicks through")
        clock = 100.05
        sidebar.edgeSample(inStrip: false)
        expect(!sidebar.staged && !shell.sidebarDetached && panel.parent == nil && shell.sidebarHost.superview === shell,
               "leaving the strip before the wait is over puts the sidebar back")
        clock = 100.1
        sidebar.edgeHovered()
        clock = 100.18
        sidebar.edgeHovered()
        expect(!sidebar.isShown, "coming back waits again: 80 ms is not enough")
        clock = 100.2
        sidebar.edgeHovered()
        expect(sidebar.isShown && !sidebar.staged && !panel.ignoresMouseEvents, "it reveals once the pointer has waited 0.1 s")
        sidebar.now = { ProcessInfo.processInfo.systemUptime }
        drainAnimations()
        expect(sidebar.isShown && shadow?.parent === window, "the shadow comes back with the sidebar")
    }

    // promise: #315
    /// GitHub #315: in full screen Arc's floating sidebar has no traffic lights (Arc 1.172.1, offline
    /// copy, 10 Nov 2026: the toggle 20 pt into the panel, as in the docked full-screen sidebar); in a
    /// window it draws them where the hidden window's lights were.
    @MainActor
    private static func noStandInLightsInFullScreen(sidebar: FloatingSidebarController, panel: NSWindow) {
        func lightsShown() -> Bool {
            shell_slider(panel)?.subviews.contains { $0 is FloatingTrafficLights && !$0.isHidden } == true
        }
        sidebar.show()
        expect(lightsShown(), "a windowed floating sidebar draws stand-in lights")
        sidebar.hide(animated: false)
        sidebar.windowFullScreen = { true }
        sidebar.show()
        expect(!lightsShown(), "a full-screen floating sidebar has no lights")
        sidebar.hide(animated: false)
        sidebar.windowFullScreen = { false }
    }

    // promise: #341
    /// GitHub #341: a child panel isn't clipped by the window it floats over, so the sidebar sliding
    /// in from the window's edge (and its shadow) drew square corners past the window's rounded ones.
    /// Arc draws its sidebar inside its window, so the window's corners clip it the whole way in.
    @MainActor
    private static func staysInsideTheWindowsCorners(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        sidebar.windowCornerRadius = { 26 }
        sidebar.show()
        let shadow = window.childWindows!.first { $0 !== panel && $0.ignoresMouseEvents }!
        for (name, p) in [("sidebar", panel), ("shadow", shadow)] {
            let mask = p.contentView?.layer?.mask
            let inPanel = window.frame.offsetBy(dx: -p.frame.minX, dy: -p.frame.minY)
            expect(mask.map { $0.frame == inPanel && $0.cornerRadius == 26 && $0.cornerCurve == .continuous } == true,
                   "the \(name) panel is clipped to the window's rounded outline")
            // The panel's top-left pixel sits on the window's left edge, just below its top: inside the
            // window's frame, but outside its rounded corner.
            let corner = NSPoint(x: 0.5, y: p.frame.height - 0.5)
            expect(mask.map { !shows(corner, through: $0) && shows(NSPoint(x: 0.5, y: p.frame.height / 2), through: $0) } == true,
                   "the \(name) panel draws nothing past the window's corner, and still draws along its edge")
        }
        sidebar.hide(animated: false)
        sidebar.windowFullScreen = { true }
        sidebar.show()
        expect(panel.contentView?.layer?.mask?.cornerRadius == 0, "full screen has square corners, so nothing is cut off there")
        sidebar.hide(animated: false)
        sidebar.windowFullScreen = { false }
    }

    /// Whether a mask layer with a rounded rect (circular corners, as near as matters) lets a point through.
    private static func shows(_ p: NSPoint, through mask: CALayer) -> Bool {
        let f = mask.frame, r = mask.cornerRadius
        guard f.contains(p) else { return false }
        let cx = min(max(p.x, f.minX + r), f.maxX - r), cy = min(max(p.y, f.minY + r), f.maxY - r)
        return hypot(p.x - cx, p.y - cy) <= r
    }

    /// The view that slides inside the sidebar panel.
    @MainActor
    private static func shell_slider(_ panel: NSWindow) -> NSView? {
        panel.contentView?.subviews.first
    }

    private static func drainAnimations() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
}

// Lightweight dependencies for compiling the production controller without CEF.
// They provide layout/theme data only; lifecycle and animation code is not copied.
struct SpacePalette {
    var vibrant = false
    var isDark = false
}

final class PaletteBackgroundView: NSView {
    var palette: SpacePalette
    init(palette: SpacePalette) { self.palette = palette; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
}

enum LittleWindow {
    static func cornerRadius(of window: NSWindow) -> CGFloat { 16 }
}

enum CraMetrics {
    static let contentInset: CGFloat = 10
    static let titleRowCenter: CGFloat = 24
}

final class CraTuning {
    static let shared = CraTuning()
    let material: NSVisualEffectView.Material = .sidebar
    let darkBlur = false
    let liftActive: CGFloat = 0.1
}

final class ResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onBegin: (() -> Void)?
    var onResize: ((_ translation: CGFloat, _ speed: CGFloat) -> Void)?
    var onEnd: (() -> Void)?
}

final class ShellView: NSView {
    let sidebarHost = NSView()
    let resizeHandle = ResizeHandleView()
    var sidebarWidth: CGFloat = 328
    var sidebarResizable = true
    var contentFullscreen = false
    var edgeToEdge = false
    /// The app's: edge to edge, or full screen with the sidebar hidden (#315).
    var fillsWindow: Bool { edgeToEdge }
    var sidebarDetached = false
    var floatingSidebar = false
    struct Frames { let sidebar: NSRect }

    override init(frame: NSRect) {
        super.init(frame: frame)
        sidebarHost.wantsLayer = true
        addSubview(sidebarHost)
        addSubview(resizeHandle)
    }
    required init?(coder: NSCoder) { fatalError() }

    func frames(sidebarVisible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat) -> Frames {
        let margin = FloatingSidebarGeometry.margin
        return Frames(sidebar: NSRect(x: margin, y: margin, width: width, height: bounds.height - 2 * margin))
    }
}
