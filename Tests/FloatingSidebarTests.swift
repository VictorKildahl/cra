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
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 15.9, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the window hides after release")
        for button in [1, 2, 4] {
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar beyond the leave slack during a gesture")
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 15.9, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar outside the moving window during a gesture")
        }
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
        expect(spring.map { $0.stiffness == 759 && $0.damping == 46.3 && $0.initialVelocity == 23.3 && $0.isAdditive } == true,
               "the reveal is Arc's spring")
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
    /// GitHub #341: the hidden sidebar stays inside the window's rounded corners on its way in and out,
    /// as Arc's does. Its panels are square and start at the window's left edge, so each one's content
    /// is masked with the window's frame and corner radius, and the sidebar and its shadow slide under it.
    @MainActor
    private static func staysInsideTheWindowsCorners(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        expect(FloatingSidebarGeometry.windowClip(window: CGRect(x: 100, y: 50, width: 1400, height: 880),
                                                  panel: CGRect(x: 100, y: 58, width: 336, height: 864))
               == CGRect(x: 0, y: -8, width: 1400, height: 880), "the window's frame, seen from a panel 8 pt inside it")
        sidebar.windowCornerRadius = { 16 }
        sidebar.show()
        let shadow = window.childWindows!.first { !($0 is FloatingSidebarPanel) }!
        /// Whether a panel's content is masked to the browser window exactly, with `radius` corners.
        func clips(_ w: NSWindow, radius: CGFloat) -> Bool {
            guard let content = w.contentView, let mask = content.layer?.mask else { return false }
            return w.convertToScreen(content.convert(mask.frame, to: nil)) == window.frame
                && mask.cornerRadius == radius && mask.backgroundColor?.alpha == 1
        }
        expect(clips(panel, radius: 16), "the sidebar's panel is cut to the window's frame and corners")
        expect(clips(shadow, radius: 16), "and so is its shadow's")
        expect(shell_slider(panel)?.layer?.mask == nil && shell_slider(panel)?.layer?.animation(forKey: "slide") != nil,
               "the mask belongs to the panel, not to the sidebar that slides under it")
        let frame = window.frame
        window.setFrame(frame.insetBy(dx: 0, dy: 40), display: false)
        sidebar.reposition()
        expect(clips(panel, radius: 16) && clips(shadow, radius: 16), "both follow the window when it is resized")
        window.setFrame(frame, display: false)
        sidebar.hide(animated: false)
        sidebar.windowFullScreen = { true }
        sidebar.show()
        expect(clips(panel, radius: 0), "a full-screen window has square corners")
        sidebar.hide(animated: false)
        sidebar.windowFullScreen = { false }
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
