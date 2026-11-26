import CraCore
import UIKit

/// The incognito mask: two hollow eggs leaning in, a pupil in each, and eyelids that fill them.
/// Turning incognito on drops the lids over the eyes; turning it off lifts them away.
final class IncognitoEyesView: UIView {
    /// The drawing's own canvas.
    static let size = CGSize(width: 28, height: 17)
    /// Where each egg sits across the canvas, and how far it leans.
    private static let eggs: [(x: CGFloat, angle: CGFloat)] = [(7, 0.16), (21, -0.16)]
    private static let eggSize = CGSize(width: 11.8, height: 14.2)
    /// The pupils look a little to the left; closing moves them 1 pt right.
    private static let pupilLook = CGPoint(x: -2, y: 0)
    private static let pupilDiameter: CGFloat = 6
    /// How far the pupils dip while the toggle is held, and how quickly.
    private static let pupilNudge: CGFloat = 0.7
    private static let pressDuration: TimeInterval = 0.1
    /// The lids' and pupils' curve: a slow start and a quick, soft landing.
    private static let blinkTiming = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.15, 1)
    /// With the eyes shut the pupils sit 1 pt right of their open look, a straight move.
    private static let pupilClosed = CGPoint(x: pupilLook.x + 1, y: pupilLook.y)
    /// The eye's rim.
    private static let rimWidth: CGFloat = 1.5

    private let outline = CAShapeLayer()
    private let pupils = CAShapeLayer()
    /// Each eye's filled egg over its pupil, revealed by its own mask. The right eye's lid waits
    /// a moment, so the blink rolls across the pair.
    private let lids = [CAShapeLayer(), CAShapeLayer()]
    private let lidMasks = [CALayer(), CALayer()]
    private var shapes: [CAShapeLayer] { [outline, pupils] + lids }
    /// Which blink the pending right lid belongs to: a new toggle cancels an older one's start,
    /// so repeated presses cannot stack the delay.
    private var blinks = MobileMotion.Ticket()
    private var pupilsDown = false
    /// Whether the lids are over the eyes.
    private(set) var closed = false

    /// The mask's ink. The sheet sets it with the microphone's, so the two match exactly.
    var ink: UIColor = .black {
        didSet { if ink != oldValue { applyInk() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for shape in shapes {
            shape.frame = bounds
            layer.addSublayer(shape)
        }
        outline.fillColor = UIColor.clear.cgColor
        outline.lineWidth = Self.rimWidth
        // The lids are the eggs filled in, each with a mask that comes down over it. Its height
        // is the lid's own state, set by `setClosed`; layout leaves it alone.
        for (lid, mask) in zip(lids, lidMasks) {
            mask.bounds = CGRect(x: 0, y: 0, width: Self.size.width, height: 0)
            mask.backgroundColor = UIColor.black.cgColor
            mask.anchorPoint = .zero
            lid.mask = mask
        }
        applyInk()
        // The eyes start looking a little left, not straight ahead.
        pupils.transform = CATransform3DMakeTranslation(Self.pupilLook.x, Self.pupilLook.y, 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let canvas = CGRect(origin: .zero, size: Self.size)
        // Bounds and position, not frame: the pupils carry their look as a transform, and a
        // layer's frame is its transformed bounds, which would undo that look.
        for shape in shapes {
            shape.bounds = CGRect(origin: .zero, size: canvas.size)
            shape.position = CGPoint(x: canvas.midX, y: canvas.midY)
        }
        outline.path = eggPath(Self.eggs, expandedBy: 0).cgPath
        pupils.path = pupilPath()
        for (index, lid) in lids.enumerated() {
            lid.path = eggPath([Self.eggs[index]], expandedBy: Self.rimWidth / 2).cgPath
        }
    }

    /// Drops the lids over the eyes, or lifts them away. The right eye starts a moment after the
    /// left one, and the pupils move 1 pt right as they close, with no dip from the press. A new
    /// toggle cancels a pending right lid, so the wait never stacks.
    func setClosed(_ closed: Bool, animated: Bool) {
        guard closed != self.closed else { return }
        self.closed = closed
        // The press is over: the close moves straight across, not from the dip.
        pupilsDown = false
        let generation = blinks.next()
        movePupils(duration: MobileSearchMotion.incognitoBlink, animated: animated)
        let height = closed ? Self.size.height : 0
        moveLid(0, to: height, animated: animated, generation: generation)
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + MobileSearchMotion.incognitoBlinkStagger) { [weak self] in
                self?.moveLid(1, to: height, animated: true, generation: generation)
            }
        } else {
            moveLid(1, to: height, animated: false, generation: generation)
        }
    }

    /// A small dip of the pupils while the toggle is held.
    func setPupilsDown(_ down: Bool) {
        guard down != pupilsDown else { return }
        pupilsDown = down
        movePupils(duration: Self.pressDuration, animated: true)
    }

    private func moveLid(_ index: Int, to height: CGFloat, animated: Bool, generation: Int) {
        guard blinks.isCurrent(generation) else { return }
        let mask = lidMasks[index]
        let from = mask.presentation()?.bounds.height ?? mask.bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.bounds = CGRect(x: 0, y: 0, width: Self.size.width, height: height)
        CATransaction.commit()
        guard animated, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.height")
        animation.fromValue = from
        animation.toValue = height
        animation.duration = MobileSearchMotion.incognitoBlink
        animation.timingFunction = Self.blinkTiming
        mask.add(animation, forKey: "blink")
    }

    /// The pupils look a little left with the eyes open; they move 1 pt right as the eyes
    /// shut and back as they open. A held button dips them.
    private func movePupils(duration: TimeInterval, animated: Bool) {
        let rest = closed ? Self.pupilClosed : Self.pupilLook
        let target = CATransform3DMakeTranslation(rest.x, rest.y + (pupilsDown ? Self.pupilNudge : 0), 0)
        let from = pupils.presentation()?.transform ?? pupils.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pupils.transform = target
        CATransaction.commit()
        guard animated, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = duration
        animation.timingFunction = Self.blinkTiming
        pupils.add(animation, forKey: "pupils")
    }

    private func applyInk() {
        outline.strokeColor = ink.cgColor
        pupils.fillColor = ink.cgColor
        for lid in lids { lid.fillColor = ink.cgColor }
    }

    /// The eggs, each leaning in from its middle; `grow` covers the rim's own width.
    private func eggPath(_ eggs: [(x: CGFloat, angle: CGFloat)], expandedBy grow: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for egg in eggs {
            let rect = CGRect(x: -Self.eggSize.width / 2 - grow, y: -Self.eggSize.height / 2 - grow,
                              width: Self.eggSize.width + grow * 2, height: Self.eggSize.height + grow * 2)
            let oval = UIBezierPath(ovalIn: rect)
            oval.apply(CGAffineTransform(translationX: egg.x, y: bounds.midY).rotated(by: egg.angle))
            path.append(oval)
        }
        return path
    }

    private func pupilPath() -> CGPath {
        let path = UIBezierPath()
        for egg in Self.eggs {
            let rect = CGRect(x: -Self.pupilDiameter / 2, y: -Self.pupilDiameter / 2,
                              width: Self.pupilDiameter, height: Self.pupilDiameter)
            let pupil = UIBezierPath(ovalIn: rect)
            // The pupil's place in the eye is its layer's; the path is the middle.
            pupil.apply(CGAffineTransform(translationX: egg.x, y: bounds.midY).rotated(by: egg.angle))
            path.append(pupil)
        }
        return path.cgPath
    }
}
