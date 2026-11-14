import CraCore
import UIKit

/// The mark on the empty home screen. Arc Search's spins like a fidget spinner when flicked;
/// so does this one (`MobileFidget` has the physics).
final class FidgetLogoView: UIImageView {
    private var angle = 0.0
    private var speed = 0.0
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var lastTouchAngle = 0.0
    private var lastTouchTime: CFTimeInterval = 0
    private var fingerSpeed = 0.0
    private let tick = UISelectionFeedbackGenerator()

    override init(image: UIImage?) {
        super.init(image: image)
        isUserInteractionEnabled = true
        contentMode = .scaleAspectFit
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        accessibilityIdentifier = "logo"
        isAccessibilityElement = true
        accessibilityLabel = "Cra"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// How far the logo has been turned, in whole and part turns (for tests and VoiceOver).
    override var accessibilityValue: String? {
        get { String(format: "%.1f turns", abs(angle) / (2 * .pi)) }
        set {}
    }

    private func touchAngle(_ pan: UIPanGestureRecognizer) -> Double {
        guard let superview else { return 0 }
        let point = pan.location(in: superview)
        return Double(atan2(point.y - center.y, point.x - center.x))
    }

    private func turn(to newAngle: Double) {
        let quarters = MobileFidget.quarterTurns(from: angle, to: newAngle)
        if quarters > 0 { tick.selectionChanged() }
        angle = newAngle
        layer.removeAnimation(forKey: "settle")
        layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(angle)))
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        let now = CACurrentMediaTime()
        switch pan.state {
        case .began:
            link?.invalidate()
            link = nil
            lastTouchAngle = touchAngle(pan)
            lastTouchTime = now
            fingerSpeed = 0
        case .changed:
            let current = touchAngle(pan)
            // The short way round between two readings of the finger's angle.
            var delta = current - lastTouchAngle
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            let elapsed = max(0.001, now - lastTouchTime)
            fingerSpeed = fingerSpeed * 0.5 + (delta / elapsed) * 0.5
            lastTouchAngle = current
            lastTouchTime = now
            turn(to: angle + delta)
        case .ended, .cancelled:
            speed = MobileFidget.launchSpeed(angularVelocity: now - lastTouchTime < 0.1 ? fingerSpeed : 0)
            lastTick = now
            let link = CADisplayLink(target: self, selector: #selector(spin(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        default: break
        }
    }

    @objc private func spin(_ link: CADisplayLink) {
        let elapsed = min(0.05, link.timestamp - lastTick)
        lastTick = link.timestamp
        guard MobileFidget.isSpinning(speed: speed) else { return settle() }
        let next = MobileFidget.step(angle: angle, speed: speed, elapsed: elapsed)
        speed = next.speed
        turn(to: next.angle)
    }

    /// Slow enough: come upright with a small bounce.
    private func settle() {
        link?.invalidate()
        link = nil
        let rest = MobileFidget.restAngle(from: angle, speed: speed)
        let spring = CASpringAnimation(keyPath: "transform.rotation.z")
        spring.fromValue = angle
        spring.toValue = rest
        spring.initialVelocity = CGFloat(speed)
        spring.damping = 9
        spring.stiffness = 120
        spring.mass = 1
        spring.duration = spring.settlingDuration
        layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(rest)))
        layer.add(spring, forKey: "settle")
        angle = rest
        speed = 0
    }
}

/// A view that takes no touches itself, only its subviews do: the page container, so that the
/// logo under it can be flicked while no page is open.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
