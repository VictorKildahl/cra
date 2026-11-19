/// Which two-finger gesture has the Picture in Picture window: a swipe, which moves it and throws
/// it into a corner, or a pinch, which resizes it (#534, #573).
///
/// A trackpad says that two fingers are down before it knows what they will do. At touch-down a
/// scroll with the phase "may begin" comes (and a magnify with it, which Chromium skips too), and
/// that scroll is cancelled when the trackpad gives up on it, which can be as late as the lift,
/// after the whole pinch. 0.1.49 took the window for a swipe on that first scroll and would not
/// let a pinch have it while the swipe held it, so a pinch after resting fingers did nothing; the
/// `cra://debug?pipPinch` hook the scenario used called the pinch's code straight and never sent
/// that scroll. Here resting fingers don't keep the window from a pinch: a pinch takes it from a
/// swipe that hasn't moved it, and the scroll's end is let go whenever it comes. A swipe that has
/// moved the window keeps it (the trackpad locks a scroll once it has begun) and a pinch keeps it
/// from a swipe.
public struct PictureInPictureFingers: Sendable, Equatable {
    /// An event's phase, as AppKit's `NSEvent.Phase` names it; `none` for an event without phases
    /// (a mouse wheel, or a magnify from something that isn't a trackpad).
    public enum Phase: Sendable, Equatable {
        case none, mayBegin, began, changed, ended, cancelled
    }

    public enum Holder: Sendable, Equatable {
        case nothing, swipe, pinch
    }

    /// What the window does with an event. A start ends whatever the fingers had before it.
    public enum Step: Sendable, Equatable {
        /// Nothing.
        case ignore
        /// Fingers on the window that may swipe it: it stops flying and starts following them.
        case startSwipe
        /// The swipe goes on (and begins, if the fingers moved without a touch-down first).
        case swipe
        /// The fingers lifted from a swipe: the window is thrown.
        case endSwipe
        /// A pinch takes the window. `fromSwipe`: resting fingers had it for a swipe that never
        /// moved it, which ends without a throw.
        case startPinch(fromSwipe: Bool)
        case pinch
        /// The fingers lifted from a pinch: the size is kept.
        case endPinch
        /// A magnify without phases: one step of a pinch, begun and ended at once.
        case pinchOnce(fromSwipe: Bool)
    }

    public private(set) var holder: Holder = .nothing

    public init() {}

    /// A scroll with `phase` (its momentum left out: the window's flight is the momentum).
    public mutating func scroll(_ phase: Phase) -> Step {
        // Fingers touching down again mean the pinch's end was lost: they start over. Anything
        // else from the scroll during a pinch (the fingers drifting) leaves the pinch the window.
        guard holder != .pinch || phase == .mayBegin else { return .ignore }
        switch phase {
        case .mayBegin, .began:
            holder = .swipe
            return .startSwipe
        case .changed:
            holder = .swipe
            return .swipe
        case .ended, .cancelled:
            guard holder == .swipe else { return .ignore }
            holder = .nothing
            return .endSwipe
        case .none:
            return .ignore
        }
    }

    /// A magnify with `phase`; `swipeMoved`: whether the swipe holding the window has moved it.
    public mutating func magnify(_ phase: Phase, swipeMoved: Bool) -> Step {
        let fromSwipe = holder == .swipe
        if fromSwipe, swipeMoved { return .ignore }
        switch phase {
        case .mayBegin:
            // Only fingers resting: Chromium leaves these out of a pinch as well.
            return .ignore
        case .began, .changed:
            // A new beginning within a pinch: the last one's end was lost, this one starts afresh.
            guard holder != .pinch || phase == .began else { return .pinch }
            holder = .pinch
            return .startPinch(fromSwipe: fromSwipe)
        case .ended, .cancelled:
            guard holder == .pinch else { return .ignore }
            holder = .nothing
            return .endPinch
        case .none:
            guard holder != .pinch else { return .pinch }
            holder = .nothing
            return .pinchOnce(fromSwipe: fromSwipe)
        }
    }

    /// The window was pressed with the mouse, or went away: whatever the fingers had is over.
    public mutating func reset() { holder = .nothing }
}
