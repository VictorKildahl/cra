import CoreGraphics
import CraCore
import Testing

/// The Picture in Picture window's scrubber, as in Arc 1.172 (reported missing by a user, 11 Nov).
struct PictureInPictureScrubberTests {
    private let size = CGSize(width: 782, height: 440)

    /// A stream has no end, so nothing to scrub; neither has a video that has not loaded.
    @Test func onlyAVideoWithAnEndHasAScrubber() {
        #expect(PictureInPictureScrubber.shows(duration: 240))
        #expect(!PictureInPictureScrubber.shows(duration: 0))
        #expect(!PictureInPictureScrubber.shows(duration: .infinity))
        #expect(!PictureInPictureScrubber.shows(duration: .nan))
    }

    /// 5 pt tall, 8 pt above the bottom and 16 pt in; 4 pt above and 12 pt in on a tiny window.
    @Test func theCapsuleSitsAlongTheBottom() {
        #expect(PictureInPictureScrubber.track(in: size) == CGRect(x: 16, y: 8, width: 750, height: 5))
        #expect(PictureInPictureScrubber.track(in: CGSize(width: 224, height: 126)) == CGRect(x: 12, y: 4, width: 200, height: 5))
    }

    /// The band that takes a press is 15 pt around the capsule, and leaves the bottom 8 pt to the
    /// window's resize edge.
    @Test func theDragAreaLeavesTheResizeEdge() {
        #expect(PictureInPictureScrubber.dragArea(in: size) == CGRect(x: 16, y: 8, width: 750, height: 10))
        #expect(PictureInPictureScrubber.dragArea(in: CGSize(width: 224, height: 126)) == CGRect(x: 12, y: 8, width: 200, height: 6))
        let area = PictureInPictureScrubber.dragArea(in: size)
        #expect(PictureInPictureGesture.edge(at: CGPoint(x: area.midX, y: area.minY), in: size) == .none)
    }

    @Test func theFillFollowsTheVideo() {
        #expect(PictureInPictureScrubber.fraction(position: 60, duration: 240) == 0.25)
        #expect(PictureInPictureScrubber.fraction(position: -1, duration: 240) == 0)
        #expect(PictureInPictureScrubber.fraction(position: 300, duration: 240) == 1)
        #expect(PictureInPictureScrubber.fraction(position: 10, duration: 0) == 0)
    }

    /// Each 60 pt up halves the rate, rounded to the nearest step, down to 1/16.
    @Test func draggingUpSlowsTheSeek() {
        let expected: [(CGFloat, Double)] = [(0, 1), (29, 1), (31, 0.5), (60, 0.5), (120, 0.25), (180, 0.125), (240, 0.0625), (900, 0.0625), (-200, 1)]
        for (dy, rate) in expected { #expect(PictureInPictureScrubber.rate(above: dy) == rate, "\(dy)") }
    }

    /// A press goes to that spot on the capsule; past its ends it is the start or the end.
    @Test func aPressSeeksToThatSpot() throws {
        let middle = try #require(PictureInPictureScrubber(press: CGPoint(x: 16 + 375, y: 10), in: size, duration: 240))
        #expect(middle.position == 120)
        #expect(try #require(PictureInPictureScrubber(press: CGPoint(x: 2, y: 10), in: size, duration: 240)).position == 0)
        #expect(try #require(PictureInPictureScrubber(press: CGPoint(x: 780, y: 10), in: size, duration: 240)).position == 240)
        #expect(PictureInPictureScrubber(press: CGPoint(x: 100, y: 10), in: size, duration: 0) == nil)
    }

    /// Along the capsule the video follows the pointer. Higher up, the same way along moves it
    /// less, from where it is; back down it is fast again and does not jump.
    @Test func aDragSeeksAtTheRateOfItsHeight() throws {
        var drag = try #require(PictureInPictureScrubber(press: CGPoint(x: 16, y: 10), in: size, duration: 240))
        #expect(drag.move(to: CGPoint(x: 16 + 375, y: 10)) == 120)
        // 75 pt further is a tenth of the capsule: 24 s at full rate, 6 s at a quarter.
        #expect(drag.move(to: CGPoint(x: 16 + 450, y: 130)) == 126)
        #expect(drag.move(to: CGPoint(x: 16 + 525, y: 10)) == 150)
        #expect(drag.move(to: CGPoint(x: 5000, y: 10)) == 240)
        #expect(drag.move(to: CGPoint(x: -5000, y: 10)) == 0)
    }
}
