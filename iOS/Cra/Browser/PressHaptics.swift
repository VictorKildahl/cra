import CraCore
import UIKit

/// Plays the ticks a control reports (MobilePressHaptics): a light impact as the finger comes
/// down, a soft one as it lets go, or a very subtle selection tick for the address. With
/// `-CraCountHaptics YES` each control counts its ticks in its accessibility value, and a hidden
/// `haptic-count` element keeps the running total for UI tests: the simulator plays no haptics.
@MainActor
enum PressHaptics {
    private static let counts = LaunchOptions.value("CraCountHaptics") == "YES"
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static weak var counter: UIView?
    private static var total = 0

    /// Adds the test's running total to `view`: 1 pt, accessible and out of the way. It outlives
    /// a tick whose control the action then puts away, as the page menu's do.
    static func installCounter(in view: UIView) {
        guard counts, counter == nil else { return }
        let counter = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        counter.isAccessibilityElement = true
        counter.accessibilityIdentifier = "haptic-count"
        counter.accessibilityLabel = "Haptics played"
        counter.accessibilityValue = "\(total)"
        counter.isUserInteractionEnabled = false
        view.addSubview(counter)
        self.counter = counter
    }

    /// The finger came down on `view`.
    static func press(_ view: UIView) {
        guard let tick = tick(for: view, edge: .down) else { return }
        play(tick, for: view)
    }

    /// The finger let go of `view`. The page menu calls this from the action rather than from
    /// the highlight, so the tick still plays when the action puts the control away.
    static func release(_ view: UIView) {
        guard let tick = tick(for: view, edge: .up) else { return }
        play(tick, for: view)
    }

    /// Warms the release tick for a control whose press edge is silent, so it plays as the finger
    /// lets go without a delay.
    static func prepare(_ view: UIView) {
        guard let id = view.accessibilityIdentifier,
              MobilePressHaptics.tick(for: id, edge: .down) == nil,
              MobilePressHaptics.tick(for: id, edge: .up) != nil else { return }
        soft.prepare()
    }

    /// A control highlighted under the finger: the press tick, for controls whose release tick
    /// comes from their action.
    static func highlightChanged(for view: UIView, from was: Bool, to now: Bool) {
        guard !was, now else { return }
        press(view)
    }

    /// Pull to refresh moving through a detent: the tick `MobilePullHaptics` asked for, a light
    /// impact from nearly silent upwards. The line's own tick is a heavy impact at full strength
    /// instead, firmer than any light one, so its `intensity` is not used.
    static func pullDetent(_ tick: MobilePullHaptics.Tick) {
        if tick.isFinal {
            heavy.impactOccurred(intensity: 1)
        } else {
            light.impactOccurred(intensity: CGFloat(tick.intensity))
        }
        count()
    }

    /// Pull to refresh reached its line and the finger let go: the reload starts.
    static func pullRefresh() {
        medium.impactOccurred()
        count()
    }

    /// Warms the pull's ticks, the heavier one at the line and the release's, so none of them
    /// plays late.
    static func preparePull() {
        light.prepare()
        heavy.prepare()
        medium.prepare()
    }

    private static func tick(for view: UIView, edge: MobilePressHaptics.Edge) -> MobilePressHaptics.Tick? {
        guard let id = view.accessibilityIdentifier else { return nil }
        return MobilePressHaptics.tick(for: id, edge: edge)
    }

    private static func play(_ tick: MobilePressHaptics.Tick, for view: UIView) {
        switch tick {
        case .press:
            light.impactOccurred()
            soft.prepare()
        case .release:
            soft.impactOccurred()
        case .selection:
            selection.selectionChanged()
        }
        guard counts else { return }
        let played = view.accessibilityValue.flatMap { Int($0.split(separator: " ").last ?? "") } ?? 0
        view.accessibilityValue = "ticks \(played + 1)"
        count()
    }

    /// Adds one to the test's running total, for ticks that belong to a control and for pull to
    /// refresh's, which belong to none.
    private static func count() {
        guard counts else { return }
        total += 1
        counter?.accessibilityValue = "\(total)"
    }
}
