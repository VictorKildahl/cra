import CraCore
import UIKit

/// The pull-to-refresh ring: a gradient arc that grows clockwise from the top, clear at its
/// flat start. Its end ink goes from clear to the status bar's colour at 90 % as the pull fills,
/// and a separate semicircular tip in that same ink sits on top of the stroke, so at the full
/// circle the rounded end covers the start's seam. Reaching the line gives a clockwise bump,
/// stronger the faster the pull, and a short pull unwinds back instead of fading. Its timing and
/// spring are `MobilePullRing`'s.
final class PullArcView: UIView {
    /// What the ring is doing after a release: it only ever plays one of these.
    private enum Playing { case bump, retract, success }

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

    private var link: CADisplayLink?
    private var playing: Playing?
    private var playFrom: CGFloat = 0
    private var playAt: CFTimeInterval = 0
    private var playDuration: TimeInterval = 0
    private var bump = MobilePullRing.bump(speed: 0)

    /// The pull's speed in points a second, for the bump at the line.
    var speed: CGFloat = 0

    /// The status bar's ink (`MobilePullRing.ink`).
    var color: UIColor = .white {
        didSet {
            guard color != oldValue else { return }
            applyInk()
        }
    }

    /// The ring is easing away after a release; the next pull waits for it.
    private(set) var isLeaving = false

    /// 0...1 through the pull. At 1 the ring is whole and gives its bump, once per crossing.
    var progress: CGFloat = 0 {
        didSet {
            guard !isLeaving, progress != oldValue else { return }
            render(progress)
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
        applyInk()
        fadeInk(0)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        arc.frame = bounds
        tip.frame = bounds
        let path = ringPath
        arc.path = path
        loop.frame = bounds
        loopTip.frame = bounds
        loop.path = path
        placeLoopTip(loopExtra)
        placeTip(rendered)
    }

    // MARK: Drawing

    /// The pull did not reach the line: the tip unwinds back to the top rather than the ring
    /// vanishing.
    func dismiss() {
        guard !isLeaving else { return }
        guard rendered > 0.001 else { progress = 0; return }
        isLeaving = true
        stopBump(hide: true)
        play(.retract, from: rendered, for: MobilePullRing.retractDuration)
    }

    /// The pull reached the line: the solid second lap runs all the way round as the ring fades.
    func fulfilled() {
        guard !isLeaving else { return }
        isLeaving = true
        stopBump(hide: false)
        play(.success, from: loopExtra, for: MobilePullRing.successDuration)
    }

    /// Draws the ring `raw` (0...1) of the way round. While the finger pulls, it fades in over
    /// the first few points; unwinding, it stays whole until it is gone.
    private func render(_ raw: CGFloat) {
        let value = max(0, min(1, raw))
        rendered = value
        // Follow the finger frame for frame: no implicit easing on the layer's own changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.strokeEnd = value
        placeTip(value)
        fadeInk(value)
        gradient.locations = [NSNumber(value: 0), NSNumber(value: Double(max(value, 0.001)))]
        CATransaction.commit()
        alpha = isLeaving ? (value > 0 ? 1 : 0) : min(1, value / 0.08)
        if value < 0.999 {
            stopBump(hide: true)
            wasComplete = false
        } else if !wasComplete {
            wasComplete = true
            startBump()
        }
    }

    /// The ink everything here draws: clear at the ring's start, 90 % at its end. Set once per
    /// colour; the pull's strength fades it, so a frame makes no new colours.
    private func applyInk() {
        let ink = color.withAlphaComponent(0.9)
        gradient.colors = [color.withAlphaComponent(0).cgColor, ink.cgColor]
        tip.fillColor = ink.cgColor
        loop.strokeColor = ink.cgColor
        loopTip.fillColor = ink.cgColor
    }

    /// How strongly the ink shows: nil at the top, whole at the refresh line.
    private func fadeInk(_ value: CGFloat) {
        let fade = Float(min(1, max(0, value)))
        gradient.opacity = fade
        tip.opacity = fade
        loop.opacity = fade
        loopTip.opacity = fade
    }

    /// The ring's whole circle, inside the stroke.
    private var ringPath: CGPath {
        let radius = max(0, min(bounds.width, bounds.height) / 2 - stroke / 2)
        return UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                            startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
    }

    /// The stroke's round end at `angle`, its flat edge on the stroke's butt end.
    private func tipPath(at angle: CGFloat) -> CGPath {
        let radius = max(0, min(bounds.width, bounds.height) / 2 - stroke / 2)
        let point = CGPoint(x: bounds.midX + radius * cos(angle), y: bounds.midY + radius * sin(angle))
        let path = UIBezierPath(arcCenter: point, radius: stroke / 2, startAngle: angle,
                                endAngle: angle + .pi, clockwise: true)
        path.close()
        return path.cgPath
    }

    /// The semicircular end, above the gradient, its flat edge on the stroke's butt end.
    private func placeTip(_ value: CGFloat) {
        tip.path = tipPath(at: -.pi / 2 + 2 * .pi * value)
        tip.isHidden = value <= 0.001
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
        loopTip.path = tipPath(at: -.pi / 2 + extra)
    }

    // MARK: Motion

    /// At the line the ring starts a second lap over the first. Its length springs out and back,
    /// its peak growing with how fast the pull was going.
    private func startBump() {
        guard !isLeaving else { return }
        stopBump(hide: true)
        bump = MobilePullRing.bump(speed: speed)
        play(.bump, from: 0, for: MobilePullRing.bumpDuration)
    }

    private func play(_ animation: Playing, from: CGFloat, for duration: TimeInterval) {
        stopPlaying()
        playing = animation
        playFrom = from
        playDuration = duration
        playAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = min(1, (CACurrentMediaTime() - playAt) / playDuration)
        switch playing {
        case .bump:
            renderLoop(MobilePullRing.lap(bump, at: t))
            guard t >= 1 else { return }
            stopPlaying()
            stopBump(hide: true)
        case .retract:
            render(playFrom * (1 - Self.eased(t)))
            guard t >= 1 else { return }
            stopPlaying()
            isLeaving = false
            progress = 0
        case .success:
            let eased = Self.eased(t)
            renderLoop(playFrom + MobilePullRing.successTurn * eased)
            alpha = 1 - eased
            guard t >= 1 else { return }
            stopPlaying()
            alpha = 0
            stopBump(hide: true)
            isLeaving = false
            progress = 0
        case nil:
            break
        }
    }

    private static func eased(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    private func stopPlaying() {
        link?.invalidate()
        link = nil
        playing = nil
    }

    /// Takes away the second lap's spring; `hide` also clears the lap the seam spring drew.
    private func stopBump(hide: Bool) {
        if playing == .bump { stopPlaying() }
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
