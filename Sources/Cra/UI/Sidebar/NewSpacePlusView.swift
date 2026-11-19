import AppKit

/// Arc's feedback at the sidebar's right edge for a swipe past the last space (NewSpaceSwipe,
/// Arc's `EdgeFeedbackView`): a strip that clips a "+" disc coming in from past the edge and a soft
/// bulge of the sidebar's ink behind it. Both ride one spring toward how far the list has
/// overscrolled; the disc's ring follows the overscroll itself. It takes no clicks and is hidden at rest.
@MainActor
final class NewSpacePlusView: NSView {
    private let bulge = CAGradientLayer()
    private let disc = CALayer()
    private let fill = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let plus = CAShapeLayer()
    private var spring = NewSpaceSwipe.Spring()
    private var target: CGFloat = 0
    private var link: CADisplayLink?
    private var lastStep: CFTimeInterval = 0
    private var activated = false
    var isDark = true { didSet { if isDark != oldValue { applyLook(animated: false) } } }
    /// The sidebar's text colour, which the bulge is a wash of.
    var ink: NSColor = .white { didSet { applyInk() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        // Arc's layer: radial, from its centre to its rim, the rim clear.
        bulge.type = .radial
        bulge.startPoint = CGPoint(x: 0.5, y: 0.5)
        bulge.endPoint = CGPoint(x: 0, y: 1)
        bulge.opacity = 0
        let side = NewSpaceSwipe.disc
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        disc.bounds = box
        // 3 pt of shade under the disc.
        disc.shadowColor = NSColor.black.cgColor
        disc.shadowOpacity = 0.2
        disc.shadowRadius = 3
        disc.shadowOffset = CGSize(width: 0, height: 1.5)
        disc.opacity = 0
        fill.path = CGPath(ellipseIn: box, transform: nil)
        // The ring starts at the top and runs counter-clockwise, its line inside the disc's edge.
        let circle = CGMutablePath()
        circle.addArc(center: CGPoint(x: side / 2, y: side / 2), radius: side / 2 - NewSpaceSwipe.ring / 2,
                      startAngle: -.pi / 2, endAngle: -.pi / 2 - 2 * .pi, clockwise: true)
        ring.path = circle
        ring.fillColor = nil
        ring.lineWidth = NewSpaceSwipe.ring
        ring.lineCap = .round
        ring.strokeEnd = 0
        let arm = NewSpaceSwipe.glyph / 2, mid = side / 2
        let cross = CGMutablePath()
        cross.move(to: CGPoint(x: mid - arm, y: mid)); cross.addLine(to: CGPoint(x: mid + arm, y: mid))
        cross.move(to: CGPoint(x: mid, y: mid - arm)); cross.addLine(to: CGPoint(x: mid, y: mid + arm))
        plus.path = cross
        plus.fillColor = nil
        plus.lineWidth = NewSpaceSwipe.glyphStroke
        plus.lineCap = .round
        for l in [fill, ring, plus] { l.frame = box; disc.addSublayer(l) }
        layer?.addSublayer(bulge)
        layer?.addSublayer(disc)
        isHidden = true
        applyLook(animated: false)
        applyInk()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        place()
    }

    /// The list is `overscroll` points past the last space; 0 once the fingers lift.
    func show(overscroll: CGFloat) {
        target = NewSpaceSwipe.shown(overscroll: overscroll)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = NewSpaceSwipe.progress(overscroll: overscroll)
        CATransaction.commit()
        let on = NewSpaceSwipe.isActivated(overscroll: overscroll)
        if on != activated {
            activated = on
            applyLook(animated: true)
            if on { pop() }
        }
        guard !spring.isSettled(on: Double(target)) else { return }
        isHidden = false
        guard window != nil else { return settleNow() }
        if link == nil {
            lastStep = CACurrentMediaTime()
            let l = displayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        // A frame that came late moves the spring by no more than a few frames' worth.
        spring.advance(toward: Double(target), by: min(max(now - lastStep, 0), 0.05))
        lastStep = now
        if spring.isSettled(on: Double(target)) { settleNow() } else { place() }
    }

    /// The spring at rest where it is headed: the end of its run, and a scenario's reading.
    func settleNow() {
        spring = NewSpaceSwipe.Spring(value: Double(target))
        link?.invalidate()
        link = nil
        place()
        isHidden = target == 0
    }

    private func place() {
        let v = CGFloat(spring.value)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let f = NewSpaceSwipe.discFrame(shown: v, strip: bounds.size)
        disc.position = CGPoint(x: f.midX, y: f.midY)
        disc.opacity = Float(NewSpaceSwipe.discAlpha(shown: v))
        bulge.frame = NewSpaceSwipe.bulgeFrame(shown: v, strip: bounds.size)
        bulge.opacity = Float(NewSpaceSwipe.bulgeOpacity(shown: v))
        CATransaction.commit()
    }

    private func applyInk() {
        let c = ink.withAlphaComponent(NewSpaceSwipe.bulgeAlpha)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bulge.colors = [c.cgColor, c.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }

    private func applyLook(animated: Bool) {
        let look = NewSpaceSwipe.look(activated: activated, dark: isDark)
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(0.12) } else { CATransaction.setDisableActions(true) }
        fill.fillColor = Self.color(look.fill)
        ring.strokeColor = Self.color(look.ring)
        plus.strokeColor = Self.color(look.plus)
        CATransaction.commit()
    }

    /// The disc grows a little and comes back as it turns over.
    private func pop() {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1, NewSpaceSwipe.pop, 1]
        a.keyTimes = [0, 0.5, 1]
        a.duration = NewSpaceSwipe.popDuration
        a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        disc.add(a, forKey: "pop")
    }

    private static func color(_ c: NewSpaceSwipe.Color) -> CGColor {
        // Arc's colours on a light sidebar are Display P3.
        NSColor(displayP3Red: c.red, green: c.green, blue: c.blue, alpha: c.alpha).cgColor
    }

    /// What it shows now, for the scenarios.
    var debugLine: String {
        func n(_ x: CGFloat) -> String { String(format: "%.1f", Double(x)) }
        return "shown=\(String(format: "%.2f", spring.value)) disc=\(n(disc.position.x - NewSpaceSwipe.disc / 2))"
            + " ring=\(String(format: "%.2f", Double(ring.strokeEnd))) activated=\(activated ? 1 : 0)"
            + " bulge=\(n(bulge.frame.minX)),\(n(bulge.frame.width)) hidden=\(isHidden ? 1 : 0)"
    }
}
