import CraCore
import UIKit

/// The empty home screen's dots. A finger pressed anywhere swells the dots under it; lifted, it
/// sends a ring across the screen (`MobileRipples` has the waves). A dot is a layer that only
/// changes while something moves, and the display link runs only then.
final class DotFieldView: UIView {
    private var ripples = MobileRipples(travels: !UIAccessibility.isReduceMotionEnabled)
    private var centres: [CGPoint] = []
    private var dots: [CALayer] = []
    /// What each dot shows, so a frame touches only the dots that changed.
    private var shown: [(level: Double, offset: CGVector)] = []
    private var link: CADisplayLink?
    private var fingers: [ObjectIdentifier: Int] = [:]
    private var nextFinger = 0
    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private var restOpacity: Float = 0
    private var peakOpacity: Float = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // For the UI tests and VoiceOver: how many rings the field has sent.
        isAccessibilityElement = true
        accessibilityIdentifier = "dot-field"
        accessibilityLabel = "Dots"
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: DotFieldView, _) in view.applyColors() }
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var accessibilityValue: String? {
        get { "\(ripples.ringsStarted) \(ripples.ringsStarted == 1 ? "ring" : "rings")" }
        set {}
    }

    @objc private func reduceMotionChanged() {
        ripples.travels = !UIAccessibility.isReduceMotionEnabled
    }

    // MARK: Dots

    override func layoutSubviews() {
        super.layoutSubviews()
        let grid = MobileRipples.grid(in: bounds.size)
        guard grid != centres else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dots.forEach { $0.removeFromSuperlayer() }
        centres = grid
        let side = MobileRipples.peakDiameter
        dots = grid.map { centre in
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            dot.cornerRadius = side / 2
            dot.position = centre
            layer.addSublayer(dot)
            return dot
        }
        // Not a level any dot has: the first draw sets every one.
        shown = Array(repeating: (-1, .zero), count: grid.count)
        applyColors()
        CATransaction.commit()
    }

    /// Dark: the recording's blue-grey, 2 pt dots at #2b2b2e on #121212 and 6.5 pt ones at
    /// #6e717b. Light mirrors it.
    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let color = (dark ? Palette.rgb(0x7b7f8b) : Palette.rgb(0x5f6270)).cgColor
        restOpacity = dark ? 0.24 : 0.2
        peakOpacity = dark ? 0.9 : 0.72
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dots.forEach { $0.backgroundColor = color }
        CATransaction.commit()
        shown = Array(repeating: (-1, .zero), count: centres.count)
        draw(at: CACurrentMediaTime())
    }

    private func draw(at time: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in dots.indices {
            let state = ripples.state(at: centres[index], time: time)
            let before = shown[index]
            let moved = abs(state.offset.dx - before.offset.dx) > 0.05 || abs(state.offset.dy - before.offset.dy) > 0.05
                || (state.offset == .zero) != (before.offset == .zero)
            let changed = abs(state.level - before.level) > 0.002 || (state.level == 0) != (before.level == 0)
            guard changed || moved else { continue }
            shown[index] = state
            let dot = dots[index]
            let scale = MobileRipples.diameter(level: state.level) / MobileRipples.peakDiameter
            dot.transform = CATransform3DMakeScale(scale, scale, 1)
            dot.opacity = restOpacity + (peakOpacity - restOpacity) * Float(MobileRipples.emphasis(level: state.level))
            dot.position = CGPoint(x: centres[index].x + state.offset.dx, y: centres[index].y + state.offset.dy)
        }
        CATransaction.commit()
    }

    // MARK: Motion

    private func run() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let time = link.targetTimestamp
        ripples.prune(time: time)
        draw(at: time)
        guard ripples.isStill else { return }
        link.invalidate()
        self.link = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window == nil else { return }
        ripples.liftAll()
        fingers.removeAll()
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        for touch in touches {
            fingers[ObjectIdentifier(touch)] = nextFinger
            ripples.press(nextFinger, at: touch.location(in: self), time: now)
            nextFinger += 1
        }
        haptic.impactOccurred(intensity: 0.55)
        run()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        for touch in touches {
            guard let finger = fingers[ObjectIdentifier(touch)] else { continue }
            ripples.move(finger, to: touch.location(in: self), time: now)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    private func lift(_ touches: Set<UITouch>) {
        let now = CACurrentMediaTime()
        for touch in touches {
            guard let finger = fingers.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            ripples.lift(finger, time: now)
        }
        run()
    }
}

/// "Tap to search" and an arrow down to the pill, over the empty home screen's dots, as in the
/// recording: 17 pt grey text 64 pt above the pill's top, the arrow 35 pt above it. Touches go
/// through it to the dots.
final class SearchHintView: UIView {
    private let label = UILabel()
    private let arrow = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.text = "Tap to search"
        label.font = .systemFont(ofSize: 17)
        label.textColor = Palette.dynamic(light: Palette.rgb(0x8a8a8e), dark: Palette.rgb(0x8e8e93))
        label.textAlignment = .center
        arrow.image = UIImage(systemName: "arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .light))
        arrow.tintColor = Palette.dynamic(light: Palette.rgb(0xa5a5aa), dark: Palette.rgb(0x6c6c70))
        arrow.contentMode = .center
        arrow.isAccessibilityElement = false
        addSubview(label)
        addSubview(arrow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Puts the hint over a pill whose top edge is at `pillTop`, centred on `centerX`.
    func place(centerX: CGFloat, pillTop: CGFloat) {
        frame = CGRect(x: centerX - 100, y: pillTop - 80, width: 200, height: 56)
        label.frame = CGRect(x: 0, y: 4, width: 200, height: 24)
        arrow.frame = CGRect(x: 90, y: 35, width: 20, height: 20)
    }
}
