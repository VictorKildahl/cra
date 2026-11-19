import CraCore
import Testing

/// Which two-finger gesture has the Picture in Picture window: a swipe or a pinch (#534, #573).
struct PictureInPictureFingersTests {
    private typealias Step = PictureInPictureFingers.Step

    /// A trackpad pinch as the trackpad can send it: two fingers touch down (a scroll that may begin,
    /// and a magnify that may begin), the magnify begins and changes, ends, and only then, as the
    /// fingers lift, is the scroll cancelled. 0.1.49 gave the window to the swipe at touch-down and
    /// then refused the pinch every step, so pinching did nothing (#573).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/573")) func aPinchAfterRestingFingersResizes() {
        var f = PictureInPictureFingers()
        #expect(f.scroll(.mayBegin) == .startSwipe)
        #expect(f.magnify(.mayBegin, swipeMoved: false) == .ignore)
        #expect(f.magnify(.began, swipeMoved: false) == .startPinch(fromSwipe: true))
        #expect(f.holder == .pinch)
        #expect(f.magnify(.changed, swipeMoved: false) == .pinch)
        #expect(f.magnify(.changed, swipeMoved: false) == .pinch)
        // The swipe's own scrolls go nowhere while the pinch has the window.
        #expect(f.scroll(.changed) == .ignore)
        #expect(f.magnify(.ended, swipeMoved: false) == .endPinch)
        // The touch-down's scroll ends at the lift: nothing is thrown.
        #expect(f.scroll(.cancelled) == .ignore)
        #expect(f.holder == .nothing)
    }

    /// The pinch's first event can be a change rather than a beginning; it takes the window too.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/573")) func aPinchThatStartsWithAChangeTakesTheWindow() {
        var f = PictureInPictureFingers()
        _ = f.scroll(.mayBegin)
        #expect(f.magnify(.changed, swipeMoved: false) == .startPinch(fromSwipe: true))
        #expect(f.magnify(.changed, swipeMoved: false) == .pinch)
    }

    /// Without resting fingers first (the scroll cancelled before the pinch, or never sent), a
    /// pinch has the window from its beginning to its end.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func aPinchOnItsOwn() {
        var f = PictureInPictureFingers()
        #expect(f.magnify(.began, swipeMoved: false) == .startPinch(fromSwipe: false))
        #expect(f.magnify(.changed, swipeMoved: false) == .pinch)
        #expect(f.magnify(.ended, swipeMoved: false) == .endPinch)
        #expect(f.holder == .nothing)
    }

    /// Fingers that rest and then swipe still swipe: the magnify that may begin at touch-down
    /// doesn't take the window (it did in 0.1.49, which treated it as a pinch's start).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/573")) func restingFingersThatSwipeStillSwipe() {
        var f = PictureInPictureFingers()
        #expect(f.magnify(.mayBegin, swipeMoved: false) == .ignore)
        #expect(f.scroll(.mayBegin) == .startSwipe)
        #expect(f.magnify(.cancelled, swipeMoved: false) == .ignore)
        #expect(f.scroll(.began) == .startSwipe)
        #expect(f.scroll(.changed) == .swipe)
        #expect(f.scroll(.ended) == .endSwipe)
        #expect(f.holder == .nothing)
    }

    /// A swipe that has moved the window keeps it: a magnify mid-swipe changes nothing.
    @Test func aMovingSwipeKeepsTheWindow() {
        var f = PictureInPictureFingers()
        _ = f.scroll(.began)
        _ = f.scroll(.changed)
        #expect(f.magnify(.began, swipeMoved: true) == .ignore)
        #expect(f.magnify(.changed, swipeMoved: true) == .ignore)
        #expect(f.holder == .swipe)
        #expect(f.scroll(.ended) == .endSwipe)
    }

    /// A magnify without phases is one pinch step on its own; within a pinch, one more step.
    @Test func aMagnifyWithoutPhases() {
        var f = PictureInPictureFingers()
        #expect(f.magnify(.none, swipeMoved: false) == .pinchOnce(fromSwipe: false))
        #expect(f.holder == .nothing)
        _ = f.scroll(.mayBegin)
        #expect(f.magnify(.none, swipeMoved: false) == .pinchOnce(fromSwipe: true))
        _ = f.magnify(.began, swipeMoved: false)
        #expect(f.magnify(.none, swipeMoved: false) == .pinch)
    }

    /// A wheel without phases (a plain mouse) and the ends of gestures nothing has are ignored;
    /// a press with the mouse ends whatever the fingers had.
    @Test func strayEventsAndAPress() {
        var f = PictureInPictureFingers()
        #expect(f.scroll(.none) == .ignore)
        #expect(f.scroll(.ended) == .ignore)
        #expect(f.magnify(.ended, swipeMoved: false) == .ignore)
        _ = f.magnify(.began, swipeMoved: false)
        f.reset()
        #expect(f.holder == .nothing)
        #expect(f.scroll(.began) == .startSwipe)
    }

    /// A pinch whose end never came doesn't keep the window: the next touch-down or the next
    /// pinch's beginning starts over.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/573")) func aLostEndDoesntStrandTheWindow() {
        var f = PictureInPictureFingers()
        _ = f.magnify(.began, swipeMoved: false)
        _ = f.magnify(.changed, swipeMoved: false)
        #expect(f.magnify(.began, swipeMoved: false) == .startPinch(fromSwipe: false))
        #expect(f.holder == .pinch)
        // A scroll mid-pinch (the fingers drifting) is ignored; fingers touching down again start over.
        #expect(f.scroll(.began) == .ignore)
        #expect(f.scroll(.changed) == .ignore)
        #expect(f.scroll(.ended) == .ignore)
        #expect(f.holder == .pinch)
        #expect(f.scroll(.mayBegin) == .startSwipe)
        #expect(f.holder == .swipe)
    }
}
