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
