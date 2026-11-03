import AppKit

/// Arc's loading bar at the top middle of the window chrome (LoadingIndicator has Arc's
/// numbers): a pill that pulses while the server hasn't answered, widening into a track that a
/// segment sweeps until the page has loaded, then a flash that shrinks away. Like Arc, it moves
/// whatever Reduce Motion says. The mouse goes through it to the window behind.
final class LoadingIndicatorView: NSView {
    private let track = CALayer()
    private let segment = CALayer()
    private(set) var phase: LoadingIndicator.Phase = .hidden
    var isDark = true { didSet { if isDark != oldValue { applyColors() } } }
    /// The track's width; the pill's while waiting.
    private var width = CGFloat(LoadingIndicator.pillWidth)
    /// The whole track lit (the pill, the widening, the flash) rather than dim under the segment.
    private var lit = true
    /// Bumped on each phase change, so a step scheduled for an earlier phase does nothing.
    private var generation = 0

    private static let height = CGFloat(LoadingIndicator.height)
    private static let trackWidth = CGFloat(LoadingIndicator.trackWidth)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        track.cornerRadius = Self.height / 2
        track.cornerCurve = .continuous
        track.masksToBounds = true
        track.opacity = 0
        segment.anchorPoint = CGPoint(x: 0, y: 0.5)
        segment.isHidden = true
        track.addSublayer(segment)
        layer?.addSublayer(track)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.position = CGPoint(x: bounds.midX, y: bounds.midY)
        track.bounds.size = CGSize(width: width, height: Self.height)
        segment.position.y = Self.height / 2
        segment.bounds.size.height = Self.height
        CATransaction.commit()
    }

    /// `animated` NO (another tab came to the front, or a new tab's first load) skips the
    /// widening, the fade-in and the flash; the pulse and the sweep run either way.
    func setPhase(_ new: LoadingIndicator.Phase, animated: Bool) {
        guard new != phase else { return }
        let old = phase
        phase = new
        generation &+= 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        switch new {
        case .hidden: animated ? finish(from: old) : stop()
        case .waiting: pulse()
        case .loading:
            if old == .waiting, animated { expand() } else { sweep(from: 0, fadeIn: animated && old == .hidden) }
        }
    }

    private func stop() {
        track.removeAllAnimations()
        segment.removeAllAnimations()
        segment.isHidden = true
        track.opacity = 0
    }

    private func setWidth(_ w: CGFloat) {
        width = w
        track.bounds.size.width = w
    }

    private func pulse() {
        stop()
        setWidth(CGFloat(LoadingIndicator.pillWidth))
        setLit(true)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        let k = LoadingIndicator.pulseKeyframes
        a.values = k.map { Float($0.opacity) }
        a.keyTimes = k.map { NSNumber(value: $0.time) }
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: k.count - 1)
        a.duration = LoadingIndicator.pulsePeriod
        a.repeatCount = .infinity
        track.add(a, forKey: "pulse")
    }

    /// The pulsing pill widens into the track, lit, and the sweep picks up as its tail sets off.
    private func expand() {
        let opacity = track.presentation()?.opacity ?? track.opacity
        track.removeAllAnimations()
        track.opacity = 1
        let from = width
        setWidth(Self.trackWidth)
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = from
        grow.toValue = Self.trackWidth
        grow.duration = LoadingIndicator.expandDuration
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        track.add(grow, forKey: "grow")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 1
        fade.duration = 0.15
        track.add(fade, forKey: "fade")
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + LoadingIndicator.expandDuration) { [weak self] in
            guard let self, self.generation == g else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.sweep(from: LoadingIndicator.sweepTailStart, fadeIn: false)
            CATransaction.commit()
        }
    }

    /// `start`: where in the cycle (0...1) the sweep begins.
    private func sweep(from start: Double, fadeIn: Bool) {
        stop()
        setWidth(Self.trackWidth)
        track.opacity = 1
        setLit(false)
        segment.isHidden = false
        segment.position.x = 0
        segment.bounds.size.width = 0
        let w = Double(Self.trackWidth)
        let k = LoadingIndicator.sweepKeyframes
        for (key, values) in [("position.x", k.map { $0.start * w }), ("bounds.size.width", k.map { ($0.end - $0.start) * w })] {
            let a = CAKeyframeAnimation(keyPath: key)
            a.values = values
            a.keyTimes = k.map { NSNumber(value: $0.time) }
            a.calculationMode = .linear
            a.duration = LoadingIndicator.sweepPeriod
            a.timeOffset = start * LoadingIndicator.sweepPeriod
            a.repeatCount = .infinity
            segment.add(a, forKey: key)
        }
        if fadeIn {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.15
            track.add(fade, forKey: "fade")
        }
    }

    /// Loaded: the whole track lights up and shrinks toward its middle as it fades. A pill that
    /// never got an answer (stopped, failed, a same-page navigation) just fades.
    private func finish(from old: LoadingIndicator.Phase) {
        let opacity = track.presentation()?.opacity ?? track.opacity
        let from = track.presentation()?.bounds.size.width ?? width
        stop()
        setLit(true)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = old == .waiting ? opacity : 1
        fade.toValue = 0
        fade.duration = old == .waiting ? 0.2 : LoadingIndicator.finishDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        track.add(fade, forKey: "fade")
        guard old == .loading else { return }
        setWidth(CGFloat(LoadingIndicator.finishWidth))
        let shrink = CABasicAnimation(keyPath: "bounds.size.width")
        shrink.fromValue = from
        shrink.toValue = LoadingIndicator.finishWidth
        shrink.duration = LoadingIndicator.finishDuration
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        track.add(shrink, forKey: "shrink")
    }

    private func setLit(_ on: Bool) {
        lit = on
        applyColors()
    }

    private func applyColors() {
        let ink = isDark ? NSColor.white : NSColor.black
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.backgroundColor = ink.withAlphaComponent(lit ? LoadingIndicator.brightAlpha : LoadingIndicator.trackAlpha).cgColor
        segment.backgroundColor = ink.withAlphaComponent(LoadingIndicator.brightAlpha).cgColor
        CATransaction.commit()
    }
}
