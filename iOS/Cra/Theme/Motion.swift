import CraCore
import UIKit

extension UIView {
    /// Animates with one of the springs fitted to Arc Search (`MobileMotion`).
    static func animate(spring: MobileMotion.Spring, animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
        let timing = UISpringTimingParameters(mass: 1, stiffness: spring.stiffness, damping: spring.damping, initialVelocity: .zero)
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: timing)
        animator.isInterruptible = true
        animator.addAnimations(animations)
        if let completion { animator.addCompletion { _ in completion() } }
        animator.startAnimation()
    }
}
