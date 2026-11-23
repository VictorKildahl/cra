import CraCore
import UIKit

extension UIView {
    /// Animates with one of the springs fitted to Arc Search (`MobileMotion`), optionally
    /// carrying a velocity into it: the components are fractions of the whole distance a second.
    static func animate(spring: MobileMotion.Spring, initialVelocity: CGVector = .zero,
                        animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
        let timing = UISpringTimingParameters(mass: 1, stiffness: spring.stiffness, damping: spring.damping,
                                              initialVelocity: initialVelocity)
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: timing)
        animator.isInterruptible = true
        animator.addAnimations(animations)
        if let completion { animator.addCompletion { _ in completion() } }
        animator.startAnimation()
    }
}

extension UIView {
    /// Plays a flick's landing worked out ahead (`MobileMotion.FlickLanding.frames`) on the
    /// render server, so it stays smooth while the app is busy showing the page that arrives.
    /// The view is laid out at its full size and drawn smaller; `corner` is how round it looks at
    /// the start, squaring off as it grows. The view is left where it lands, so taking the
    /// animation off (`flickLandingKey`) leaves nothing to jump.
    func playLanding(_ frames: [MobileMotion.FlickLanding.Frame], every step: Double, corner: CGFloat,
                     completion: @escaping () -> Void) {
        guard let last = frames.last, frames.count > 1 else { return completion() }
        let duration = Double(frames.count - 1) * step
        let times = frames.indices.map { NSNumber(value: Double($0) / Double(frames.count - 1)) }
        func keyframes(_ path: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.keyTimes = times
            animation.calculationMode = .linear
            return animation
        }
        func turned(_ frame: MobileMotion.FlickLanding.Frame) -> CATransform3D {
            CATransform3DMakeAffineTransform(CGAffineTransform(rotationAngle: frame.angle).scaledBy(x: frame.scale, y: frame.scale))
        }
        let group = CAAnimationGroup()
        group.animations = [
            keyframes("position", frames.map { NSValue(cgPoint: $0.center) }),
            keyframes("transform", frames.map { NSValue(caTransform3D: turned($0)) }),
            keyframes("cornerRadius", frames.map { corner * (1 - $0.grown) / max($0.scale, 0.01) }),
        ]
        group.duration = duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        center = last.center
        transform = .identity
        layer.cornerRadius = 0
        layer.add(group, forKey: Self.flickLandingKey)
        CATransaction.commit()
    }

    static let flickLandingKey = "flick-landing"
}
