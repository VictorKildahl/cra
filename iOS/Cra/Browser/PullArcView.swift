import UIKit

/// The pull-to-refresh ring: a gradient arc that grows clockwise from the top, clear at its
/// flat start. Its end ink goes from clear to the status bar's colour at 90 % as the pull fills,
/// and a separate semicircular tip in that same ink sits on top of the stroke, so at the full
/// circle the rounded end covers the start's seam. Reaching the line gives a clockwise bump,
/// stronger the faster the pull, and a short pull unwinds back instead of fading.
final class PullArcView: UIView {
    private let gradient = CAGradientLayer()
    private let arc = CAShapeLayer()
    private let tip = CAShapeLayer()
    /// The second lap's start: a solid arc over the full ring's seam, with its own round end.
    private let loop = CAShapeLayer()
    private let loopTip = CAShapeLayer()
    private let stroke: CGFloat = 4.5
    private var rendered: CGFloat = 0
    private var wasComplete = false

    private var loopExtra: CGFloat = 0
    private var bumpLink: CADisplayLink?
    private var bumpAt: CFTimeInterval = 0
    private var bumpPeak: CGFloat = 0
    private var bumpDecay: CGFloat = 8
    private let bumpDuration: TimeInterval = 0.26

    private var successLink: CADisplayLink?
    private var successFrom: CGFloat = 0
    private var successAt: CFTimeInterval = 0
    private let successDuration: TimeInterval = 0.2

    private var retractLink: CADisplayLink?
    private var retractFrom: CGFloat = 0
    private var retractAt: CFTimeInterval = 0
    private let retractDuration: TimeInterval = 0.22

    /// The pull's speed in points a second, for the bump at the line.
    var speed: CGFloat = 0

    /// The status bar's ink: white over a dark bar, dark grey over a light one.
    var color: UIColor = .white {
        didSet {
            guard color != oldValue else { return }
            updateInk(rendered)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(gradient)
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        arc.fillColor = nil
        arc.strokeColor = UIColor.white.cgColor
        arc.lineWidth = stroke
        arc.lineCap = .butt
        gradient.mask = arc
        tip.strokeColor = nil
        // Above the gradient, so at the full circle the rounded end is drawn over the start.
        layer.addSublayer(tip)
        loop.fillColor = nil
        loop.strokeColor = UIColor.white.cgColor
        loop.lineWidth = stroke
        loop.lineCap = .butt
        loop.isHidden = true
        // Over the full ring's seam: this is where the second lap starts.
        layer.addSublayer(loop)
        loopTip.strokeColor = nil
        loopTip.isHidden = true
        layer.addSublayer(loopTip)
        updateInk(0)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The ring is easing away after a release; the next pull waits for it.
    private(set) var isLeaving = false

    /// 0...1 through the pull. At 1 the ring is whole and gives its bump, once per crossing.
    var progress: CGFloat = 0 {
        didSet {
            guard !isLeaving else { return }
            let value = max(0, min(1, progress))
            guard value != oldValue else { return }
            render(value, fadeIn: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        arc.frame = bounds
        tip.frame = bounds
        let inset = stroke / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        arc.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2,
                                endAngle: .pi * 1.5, clockwise: true).cgPath
        loop.frame = bounds
        loopTip.frame = bounds
        loop.path = arc.path
        placeLoopTip(loopExtra)
        placeTip(rendered)
    }

    /// Draws `value` through the arc. The pull fades in quickly at the start; the retract stays
    /// solid while its tip travels back to the top.
    private func render(_ raw: CGFloat, fadeIn: Bool) {
        let value = max(0, min(1, raw))
        rendered = value
        // Follow the finger frame for frame: no implicit easing on the layer's own changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.strokeEnd = value
        placeTip(value)
        updateInk(value)
        gradient.locations = [NSNumber(value: 0), NSNumber(value: Double(max(value, 0.001)))]
        CATransaction.commit()
        alpha = fadeIn ? min(1, value / 0.08) : (value > 0 ? 1 : 0)
        if value < 0.999 {
            stopBump(hide: true)
            wasComplete = false
        } else if !wasComplete {
            wasComplete = true
            bump()
        }
    }

    /// The arc's end ink, from clear at the start to 90 % at the full circle. The tip shares it.
    private func updateInk(_ value: CGFloat) {
        let ink = color.withAlphaComponent(0.9 * value)
        gradient.colors = [color.withAlphaComponent(0).cgColor, ink.cgColor]
        tip.fillColor = ink.cgColor
        loop.strokeColor = ink.cgColor
        loopTip.fillColor = ink.cgColor
    }

    /// The semicircular end, above the gradient, its flat edge on the stroke's butt end.
    private func placeTip(_ value: CGFloat) {
        let inset = stroke / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        let end = -.pi / 2 + 2 * .pi * value
        let point = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
        let path = UIBezierPath()
        path.addArc(withCenter: point, radius: inset, startAngle: end, endAngle: end + .pi, clockwise: true)
        path.close()
        tip.path = path.cgPath
        tip.isHidden = value <= 0.001
    }

    /// The pull did not reach the line: the tip unwinds back to the top rather than the ring
    /// vanishing.
    func dismiss() {
        guard !isLeaving else { return }
        guard rendered > 0.001 else { progress = 0; return }
        isLeaving = true
        stopBump(hide: true)
        transform = .identity
        retractFrom = rendered
        retractAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(retractStep))
        link.add(to: .main, forMode: .common)
        retractLink = link
    }

    @objc private func retractStep() {
        let t = min(1, (CACurrentMediaTime() - retractAt) / retractDuration)
        let eased = 1 - pow(1 - t, 3)
        render(retractFrom * (1 - eased), fadeIn: false)
        guard t >= 1 else { return }
        retractLink?.invalidate()
        retractLink = nil
        isLeaving = false
        progress = 0
    }

    /// The pull reached the line: the solid second lap runs all the way round as the ring fades.
    func fulfilled() {
        guard !isLeaving else { return }
        isLeaving = true
        stopBump(hide: false)
        successFrom = loopExtra
        successAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(successStep))
        link.add(to: .main, forMode: .common)
        successLink = link
    }

    @objc private func successStep() {
        let t = min(1, (CACurrentMediaTime() - successAt) / successDuration)
        let eased = 1 - pow(1 - t, 3)
        let extra = successFrom + (80 * .pi / 180) * eased
        renderLoop(extra)
        alpha = 1 - eased
        guard t >= 1 else { return }
        successLink?.invalidate()
        successLink = nil
        alpha = 0
        stopBump(hide: true)
        transform = .identity
        isLeaving = false
        progress = 0
    }

    /// At the line the ring starts a second lap over the first. Its length springs out and back,
    /// its peak growing with how fast the pull was going.
    private func bump() {
        guard !isLeaving else { return }
        stopBump(hide: true)
        let fast = min(1, max(0, speed) / 2000)
        bumpPeak = (1 + 29 * fast) * .pi / 180
        // A slow pull damps at once; a faster one lets the spring swing again.
        bumpDecay = 8 - 5 * fast
        bumpAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(bumpStep))
        link.add(to: .main, forMode: .common)
        bumpLink = link
    }

    @objc private func bumpStep() {
        let t = min(1, (CACurrentMediaTime() - bumpAt) / bumpDuration)
        // The first out-swing is exactly the peak; each later swing is smaller, and disappears
        // quickly for a slow pull.
        let extra = bumpPeak * (exp(-bumpDecay * t) / exp(-bumpDecay * 0.25)) * abs(sin(2 * .pi * t))
        renderLoop(extra)
        guard t >= 1 else { return }
        stopBump(hide: true)
    }

    /// The second lap's arc: solid ink from the top, with its own round end.
    private func renderLoop(_ extra: CGFloat) {
        loopExtra = extra
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        loop.strokeEnd = min(1, extra / (2 * .pi))
        loop.isHidden = extra <= 0.0001
        placeLoopTip(extra)
        loopTip.isHidden = extra <= 0.0001
        CATransaction.commit()
    }

    private func placeLoopTip(_ extra: CGFloat) {
        let inset = stroke / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        let end = -.pi / 2 + extra
        let point = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
        let path = UIBezierPath()
        path.addArc(withCenter: point, radius: inset, startAngle: end, endAngle: end + .pi, clockwise: true)
        path.close()
        loopTip.path = path.cgPath
    }

    private func stopBump(hide: Bool) {
        bumpLink?.invalidate()
        bumpLink = nil
        guard hide else { return }
        loopExtra = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        loop.strokeEnd = 0
        loop.isHidden = true
        loopTip.isHidden = true
        CATransaction.commit()
    }
}
