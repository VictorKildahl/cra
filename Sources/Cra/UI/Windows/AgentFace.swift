import AppKit
import CraCEF
import QuartzCore

/// The face Cra draws for an MCP agent at work (MCPAgentPresence): a pointer-shaped drop, round
/// but for its sharp top left corner, with two eyes. The same face is the agent's cursor over the
/// page, the mark on its tab's sidebar row and the start of Cra's toast while it works.
@MainActor
final class AgentFaceLayer: CALayer {
    private let body = CAShapeLayer()
    private let eyes = CALayer()
    private let left = CALayer()
    private let right = CALayer()
    private(set) var side: CGFloat = 0
    private var blinking: Timer?

    override init() {
        super.init()
        addSublayer(body)
        body.addSublayer(eyes)
        eyes.addSublayer(left)
        eyes.addSublayer(right)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// `side` points square; the sharp corner, the cursor's hotspot, is at the top left.
    func configure(side: CGFloat, fill: NSColor, eyes eyeColor: NSColor, outline: NSColor?, scale: CGFloat) {
        self.side = side
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        contentsScale = scale
        body.frame = bounds
        body.contentsScale = scale
        body.path = Self.drop(side)
        body.fillColor = fill.cgColor
        body.strokeColor = outline?.cgColor
        body.lineWidth = outline == nil ? 0 : max(1.5, side / 12)
        let eye = CGSize(width: max(1.6, side * 0.15), height: max(2.2, side * 0.23))
        let gap = side * 0.13
        eyes.bounds = CGRect(x: 0, y: 0, width: 2 * eye.width + gap, height: eye.height)
        // A little right of and below the middle: where the drop's weight is.
        eyes.position = CGPoint(x: side * 0.54, y: side * 0.47)
        for (layer, x) in [(left, 0), (right, eye.width + gap)] {
            layer.frame = CGRect(x: x, y: 0, width: eye.width, height: eye.height)
            layer.cornerRadius = eye.width / 2
            layer.backgroundColor = eyeColor.cgColor
            layer.contentsScale = scale
        }
        CATransaction.commit()
    }

    /// The drop in layer coordinates (y up): radius side/2 at three corners, a small one at the top left.
    private static func drop(_ s: CGFloat) -> CGPath {
        let big = s / 2, tip = s * 0.14
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: s - tip))
        p.addArc(tangent1End: CGPoint(x: 0, y: s), tangent2End: CGPoint(x: tip, y: s), radius: tip)
        p.addArc(tangent1End: CGPoint(x: s, y: s), tangent2End: CGPoint(x: s, y: s - big), radius: big)
        p.addArc(tangent1End: CGPoint(x: s, y: 0), tangent2End: CGPoint(x: s - big, y: 0), radius: big)
        p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: 0, y: big), radius: big)
        p.closeSubpath()
        return p
    }

    /// The eyes turn toward a direction on screen (x right, y down, as MCPAgentPresence.gaze says).
    func look(_ direction: CGVector, duration: Double = 0.18) {
        let reach = side * 0.09
        let v = MCPAgentPresence.gaze(dx: direction.dx, dy: direction.dy, reach: reach)
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        eyes.transform = CATransform3DMakeTranslation(v.dx, -v.dy, 0)
        CATransaction.commit()
    }

    func blink() {
        let close = CAKeyframeAnimation(keyPath: "transform.scale.y")
        close.values = [1, 0.1, 1]
        close.keyTimes = [0, 0.45, 1]
        close.duration = 0.16
        left.add(close, forKey: "blink")
        right.add(close, forKey: "blink")
    }

    /// Blinks now and then (every 2.5–5 s) while it is up; stops with stopBlinking().
    func startBlinking() {
        guard blinking == nil else { return }
        scheduleBlink()
    }

    private func scheduleBlink() {
        blinking = Timer.scheduledTimer(withTimeInterval: .random(in: 2.5...5), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.blinking != nil else { return }
                self.blink()
                self.scheduleBlink()
            }
        }
    }

    func stopBlinking() {
        blinking?.invalidate()
        blinking = nil
    }

    /// The click: flattens against what it presses and springs back, the sharp corner held still.
    func squish() {
        let squash = CAKeyframeAnimation(keyPath: "transform")
        squash.values = [CATransform3DIdentity, CATransform3DMakeScale(1.14, 0.8, 1), CATransform3DMakeScale(0.94, 1.06, 1), CATransform3DIdentity]
            .map { NSValue(caTransform3D: $0) }
        squash.keyTimes = [0, 0.3, 0.65, 1]
        squash.duration = 0.3
        squash.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)]
        add(squash, forKey: "squish")
    }
}

/// The face on a tab's sidebar row while an agent works in it: blinks and glances about.
@MainActor
final class AgentFaceView: NSView {
    static let side: CGFloat = 16
    private let face = AgentFaceLayer()
    private var glance: Timer?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        wantsLayer = true
        layer?.addSublayer(face)
        _ = ArcTooltipAnchorView.attach(to: self, help: "An agent is working in this tab")
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Agent working")
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(fill: NSColor) {
        let dark = (fill.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) < 0.5
        face.configure(side: Self.side, fill: fill, eyes: dark ? .white : .black, outline: nil, scale: window?.backingScaleFactor ?? 2)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            face.stopBlinking()
            glance?.invalidate()
            glance = nil
        } else {
            face.contentsScale = window?.backingScaleFactor ?? 2
            face.startBlinking()
            // It reads the page: a look one way, then the other, now and then.
            glance = glance ?? Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let pick = Int.random(in: 0..<4)
                    self.face.look(pick == 0 ? CGVector(dx: -1, dy: 0) : pick == 1 ? CGVector(dx: 1, dy: 0.3) : .zero, duration: 0.25)
                }
            }
        }
    }

    override var isHidden: Bool {
        didSet { if isHidden { glance?.invalidate(); glance = nil; face.stopBlinking() } else if window != nil { viewDidMoveToWindow() } }
    }
}

/// The agent's cursor: the face over the tab's page, gliding where the agent's pointer goes and
/// squishing when it clicks, only while the user is on that tab (MCPServer asks isWatched). It
/// lives in a click-through panel over the page, like the permission card, and fades
/// MCPServer.linger after its last move (Settings ▸ Advanced ▸ Agents).
@MainActor
final class AgentCursor {
    static let side: CGFloat = 24
    private let panel: NSPanel
    private let face = AgentFaceLayer()
    private let ripple = CAShapeLayer()
    private var point: CGPoint?
    private var fade: DispatchWorkItem?
    private var watch: Timer?
    /// The page's frame on screen, nil while the tab isn't in sight.
    let pageFrame: () -> NSRect?
    let isWatched: () -> Bool

    private static let showing = NSHashTable<NSPanel>.weakObjects()

    /// The cursors' panels over `window`, for the window's ordering of its child panels.
    static func panels(over window: NSWindow) -> [NSPanel] {
        showing.allObjects.filter { $0.parent === window && $0.isVisible }
    }

    init(pageFrame: @escaping () -> NSRect?, isWatched: @escaping () -> Bool) {
        self.pageFrame = pageFrame
        self.isWatched = isWatched
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let view = NSView()
        view.wantsLayer = true
        panel.contentView = view
        ripple.fillColor = NSColor.black.withAlphaComponent(0.06).cgColor
        ripple.strokeColor = NSColor.black.withAlphaComponent(0.4).cgColor
        ripple.lineWidth = 2
        ripple.opacity = 0
        view.layer?.addSublayer(ripple)
        face.anchorPoint = CGPoint(x: 0, y: 1)
        face.shadowColor = NSColor.black.cgColor
        face.shadowOpacity = 0.3
        face.shadowRadius = 4
        face.shadowOffset = CGSize(width: 0, height: -2)
        view.layer?.addSublayer(face)
    }

    var isShown: Bool { panel.parent != nil }

    /// Over the page now (the page may have moved with the sidebar or a split), or nil when it can't be.
    private func place(in window: NSWindow) -> NSRect? {
        guard let frame = pageFrame() else { return nil }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            Self.showing.add(panel)
        }
        return frame
    }

    /// The pointer went to `css` (page CSS pixels from the viewport's top left) over `duration`;
    /// `zoom` is CSS pixels to points. The first move after a while starts there, fading in.
    func move(to css: CGPoint, zoom: CGFloat, duration: Double, in window: NSWindow) {
        guard isWatched(), let frame = place(in: window) else { return hide() }
        let target = CGPoint(x: css.x * zoom, y: frame.height - css.y * zoom)
        let scale = window.backingScaleFactor
        if face.side == 0 || face.contentsScale != scale {
            face.configure(side: Self.side, fill: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1), eyes: .white, outline: .white, scale: scale)
        }
        CATransaction.begin()
        if point == nil || face.opacity == 0 {
            CraLog.note("mcp cursor: shown over the watched tab")
            CATransaction.setDisableActions(true)
            face.position = target
            face.opacity = 1
            face.startBlinking()
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.duration = 0.15
            face.add(appear, forKey: "appear")
        } else {
            CATransaction.setAnimationDuration(max(duration, 0.016))
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
            face.position = target
        }
        CATransaction.commit()
        if let point, hypot(target.x - point.x, target.y - point.y) > 1 {
            face.look(CGVector(dx: target.x - point.x, dy: point.y - target.y))
        }
        point = target
        keepUp()
    }

    /// The page scrolls under the pointer at `css`: the cursor shows there (it may have faded while
    /// the agent read the page) and looks the way the page goes, nudging that way like a flick of
    /// the wheel, so a moving page always has the cursor that moved it on it.
    func scroll(at css: CGPoint, toward direction: CGVector, zoom: CGFloat, in window: NSWindow) {
        move(to: css, zoom: zoom, duration: 0, in: window)
        guard isShown, point != nil else { return }
        CraLog.note("mcp cursor: scrolling")
        face.look(direction, duration: 0.25)
        let length = hypot(direction.dx, direction.dy)
        guard length > 0 else { return }
        let nudge = CAKeyframeAnimation(keyPath: "transform.translation")
        let reach: CGFloat = 4
        let step = CGSize(width: direction.dx / length * reach, height: -direction.dy / length * reach)
        nudge.values = [CGSize.zero, step, CGSize.zero].map { NSValue(size: $0) }
        nudge.keyTimes = [0, 0.35, 1]
        nudge.duration = 0.45
        nudge.isAdditive = true
        nudge.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        face.add(nudge, forKey: "nudge")
    }

    /// A press at the pointer: the face squishes and a ring spreads from its tip.
    func press() {
        guard isShown, let point, isWatched() else { return }
        face.squish()
        let r: CGFloat = 20
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ripple.frame = CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)
        ripple.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r), transform: nil)
        CATransaction.commit()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.6
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fadeOut]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "ripple")
        keepUp()
    }

    /// Up until a while after the last move, and gone at once when the user leaves the tab.
    private func keepUp() {
        fade?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MCPServer.shared.linger.seconds, execute: work)
        if watch == nil {
            watch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.panel.parent else { return }
                    if !self.isWatched() { self.hide() } else { _ = self.place(in: window) }
                }
            }
        }
    }

    func hide() {
        fade?.cancel()
        fade = nil
        watch?.invalidate()
        watch = nil
        face.stopBlinking()
        point = nil
        guard isShown else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.point == nil else { return }
                Self.showing.remove(self.panel)
                self.panel.parent?.removeChildWindow(self.panel)
                self.panel.orderOut(nil)
            }
        }
        face.opacity = 0
        CATransaction.commit()
    }
}

/// MCPInput's pointer in one tab: its moves and presses go to the tab's cursor, page CSS pixels
/// turned into points by the page's zoom (Chromium's level, 1.2 per step).
@MainActor
final class AgentPointer: MCPPointerWatcher {
    private let cursor: AgentCursor
    private weak var browser: CraBrowser?
    private weak var window: MainWindowController?

    init(cursor: AgentCursor, browser: CraBrowser, window: MainWindowController) {
        self.cursor = cursor
        self.browser = browser
        self.window = window
    }

    var isWatched: Bool { cursor.isWatched() }

    func moved(to point: CGPoint, duration: Double) {
        guard let browser, let nsWindow = window?.window else { return }
        cursor.move(to: point, zoom: CGFloat(pow(1.2, browser.zoomLevel())), duration: duration, in: nsWindow)
    }

    func pressed() { cursor.press() }

    func scrolls(at point: CGPoint, toward direction: CGVector) {
        guard let browser, let nsWindow = window?.window else { return }
        cursor.scroll(at: point, toward: direction, zoom: CGFloat(pow(1.2, browser.zoomLevel())), in: nsWindow)
    }
}
