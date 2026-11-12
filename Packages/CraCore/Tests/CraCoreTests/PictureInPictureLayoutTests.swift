import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's Picture in Picture window: where it opens and what its top bar shows (#246).
struct PictureInPictureLayoutTests {
    @Test(arguments: [("https://www.youtube.com/watch?v=x", "www.youtube.com"), ("http://127.0.0.1:8080/video.html", "127.0.0.1"),
                      ("file:///Users/me/clip.mp4", "File on your device"), ("about:blank", "")])
    func addressIsTheHost(url: String, address: String) {
        #expect(PictureInPictureLayout.address(of: url) == address)
    }

    /// Back to tab on the left, close on the right (Cra had them the other way round), the
    /// address centred on the window between them and clear of both.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/246"))
    func topBarIsArcs() {
        let bar = PictureInPictureLayout.topBar(width: 223, buttonSize: 26, addressWidth: 85)
        #expect(bar.back == CGRect(x: 13, y: 13, width: 26, height: 26))
        #expect(bar.close == CGRect(x: 184, y: 13, width: 26, height: 26))
        let a = try! #require(bar.address)
        #expect(a.midX == 111.5 && a.midY == 26 && a.width == 85)
        #expect(a.minX >= bar.back.maxX + 8 && a.maxX <= bar.close.minX - 8)
    }

    @Test func longAddressIsCutToTheRoomAndDroppedWithoutRoom() {
        let bar = PictureInPictureLayout.topBar(width: 223, buttonSize: 26, addressWidth: 400)
        #expect(bar.address?.width == 2 * (111.5 - 39 - 8))
        #expect(PictureInPictureLayout.topBar(width: 110, buttonSize: 26, addressWidth: 85).address == nil)
        #expect(PictureInPictureLayout.topBar(width: 223, buttonSize: 26, addressWidth: 0).address == nil)
    }

    /// Arc's size classes: buttons 12 pt + 8 pt padding in below 280 pt, 16 + 8 below 400, 16 + 10
    /// from there, where Back to Tab also shows its words.
    @Test func controlsMoveInWithTheWindowsSize() {
        #expect([223, 279, 280, 399, 400, 801].map { PictureInPictureLayout.buttonCentreInset(width: $0) } == [26, 26, 30, 30, 32, 32])
        #expect(!PictureInPictureLayout.labelsBackToTab(width: 399) && PictureInPictureLayout.labelsBackToTab(width: 400))
        let bar = PictureInPictureLayout.topBar(width: 801, buttonSize: 26, backWidth: 110, addressWidth: 85)
        #expect(bar.back == CGRect(x: 19, y: 19, width: 110, height: 26))
        #expect(bar.close == CGRect(x: 756, y: 19, width: 26, height: 26))
        #expect(bar.address?.midX == 400.5)
    }

    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let visible = CGRect(x: 0, y: 80, width: 1920, height: 975)

    /// The limits: never below 224 × 126 for 16:9 (the 223 × 125.5 window in #246 was Arc's
    /// minimum), at most the display's visible frame. Arc stops at 61.7 % of the screen's width;
    /// Cra goes to the whole visible frame (the maintainer's decision, 12 Nov).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/246"))
    func sizeStaysInTheLimits() {
        let l = PictureInPictureLayout.sizeLimits(aspect: 16.0 / 9, screen: screen, visible: visible)
        #expect(l.min == CGSize(width: 224, height: 126))
        #expect(l.max == CGSize(width: 1920, height: 975))
        // Portrait: 224 wide at least, not 126 tall.
        #expect(PictureInPictureLayout.sizeLimits(aspect: 9.0 / 16, screen: screen, visible: visible).min == CGSize(width: 224, height: 398))
        // A remembered frame below the minimum (Cra allowed 160 × 90) opens at Arc's minimum.
        let small = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, screen: screen, visible: visible,
                                                        remembered: CGRect(x: 100, y: 500, width: 160, height: 90))
        #expect(small == CGRect(x: 100, y: 464, width: 224, height: 126))
        // One wider than the display opens as wide as the display; a 16:9 video is then as tall as
        // 1080 pt, which the 975 pt of visible height cuts to 1733 × 975.
        let wide = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, screen: screen, visible: visible,
                                                       remembered: CGRect(x: 0, y: 100, width: 2400, height: 1350))
        #expect(wide.size == CGSize(width: 1733, height: 975))
    }

    // A built-in display at the origin and an external one to its right, AppKit coordinates.
    let builtIn = PictureInPictureLayout.Display(id: "BUILTIN", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                                 visible: CGRect(x: 0, y: 0, width: 1728, height: 1084))
    let external = PictureInPictureLayout.Display(id: "EXTERNAL", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                                                  visible: CGRect(x: 1728, y: 0, width: 1920, height: 1055))

    /// Left on the external display, the next video opens there at the same spot, though Chromium
    /// put its window on the display Cra's window is on. Cra checked the remembered frame against
    /// that display only, so it opened in the built-in display's top-right corner (#316).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func reopensOnTheDisplayItWasLeftOn() {
        let left = CGRect(x: 1728 + 100, y: 300, width: 480, height: 270)
        let placement = PictureInPictureLayout.Placement(frame: left, display: "EXTERNAL", displayFrame: external.frame)
        let f = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, displays: [builtIn, external], current: builtIn, remembered: placement)
        #expect(f == left)
        // A frame saved before Cra kept its display opens on the display it lies on.
        let old = PictureInPictureLayout.Placement(frame: left, display: nil, displayFrame: nil)
        #expect(PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, displays: [builtIn, external], current: builtIn, remembered: old) == left)
        // Arc's limits are the external display's: 61.7 % of 1920 wide, not of 1728.
        let big = PictureInPictureLayout.Placement(frame: CGRect(x: 1728, y: 100, width: 1184, height: 666), display: "EXTERNAL",
                                                   displayFrame: external.frame)
        #expect(PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, displays: [builtIn, external], current: builtIn, remembered: big).width == 1184)
    }

    /// The display moved (arranged to the left in System Settings): the window goes with it, at
    /// the same place on that display.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func followsTheDisplayWhenItIsRearranged() {
        let before = CGRect(x: 1728 + 100, y: 300, width: 480, height: 270)
        let placement = PictureInPictureLayout.Placement(frame: before, display: "EXTERNAL", displayFrame: external.frame)
        var moved = external
        moved.frame.origin.x = -1920
        moved.visible.origin.x = -1920
        let f = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, displays: [builtIn, moved], current: builtIn, remembered: placement)
        #expect(f == CGRect(x: -1920 + 100, y: 300, width: 480, height: 270))
    }

    /// The display it was left on isn't connected: Arc's default corner on the display in use.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func unpluggedDisplayFallsBackToTheCorner() {
        let placement = PictureInPictureLayout.Placement(frame: CGRect(x: 1728 + 100, y: 300, width: 480, height: 270), display: "EXTERNAL",
                                                         displayFrame: external.frame)
        let f = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, displays: [builtIn], current: builtIn, remembered: placement)
        #expect(f == CGRect(x: 1728 - 10 - 782, y: 1084 - 10 - 440, width: 782, height: 440))
    }

    /// Dropped by a mouse drag half past an edge, the window springs back into the nearest corner
    /// of the display, 10 pt in, as Arc's does (its swipe already did). Cra left it where it was
    /// let go, half off the screen (#332).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/332"))
    func droppedPastAnEdgeGoesToTheNearestCorner() {
        let size = CGSize(width: 480, height: 270)
        let displays = [builtIn]
        func landing(_ x: CGFloat, _ y: CGFloat) -> PictureInPictureLayout.Landing? {
            PictureInPictureLayout.landing(afterDropping: CGRect(origin: CGPoint(x: x, y: y), size: size), displays: displays)
        }
        // Half past the right edge, low on the screen: bottom right (the reporter's Arc clip).
        #expect(landing(1728 - 240, 100) == .init(corner: .bottomRight, frame: CGRect(x: 1728 - 10 - 480, y: 10, width: 480, height: 270)))
        // Past the right edge, high up: top right, below the menu bar.
        #expect(landing(1500, 900)?.corner == .topRight)
        #expect(landing(1500, 900)?.frame == CGRect(x: 1238, y: 1084 - 10 - 270, width: 480, height: 270))
        // The left, top and bottom edges as well.
        #expect(landing(-200, 400)?.corner == .bottomLeft)
        #expect(landing(-200, 600)?.corner == .topLeft)
        #expect(landing(300, 1000)?.corner == .topLeft)
        #expect(landing(1200, -100)?.corner == .bottomRight)
        // Wholly on the screen it stays where it was let go, under the menu bar or Dock too.
        #expect(landing(600, 400) == nil)
        #expect(landing(600, 1117 - 270) == nil)
        #expect(landing(0, 0) == nil)
    }

    /// Across two displays side by side it is on screen, so no corner takes it (since 12 Nov it
    /// slides onto one display instead: `droppedAcrossDisplaysSlidesOntoOne`). Past the far edge of
    /// the second, it goes to that display's corner, not the first one's.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/332"))
    func droppedAcrossDisplaysStaysAndPastTheFarEdgeUsesThatDisplay() {
        let size = CGSize(width: 480, height: 270)
        let both = [builtIn, external]
        #expect(PictureInPictureLayout.landing(afterDropping: CGRect(origin: CGPoint(x: 1600, y: 300), size: size), displays: both) == nil)
        let far = PictureInPictureLayout.landing(afterDropping: CGRect(origin: CGPoint(x: 1728 + 1920 - 200, y: 100), size: size), displays: both)
        #expect(far == .init(corner: .bottomRight, frame: CGRect(x: 1728 + 1920 - 10 - 480, y: 10, width: 480, height: 270)))
        // A mirrored display (the same frame twice) doesn't count as covering the part that's off.
        #expect(PictureInPictureLayout.landing(afterDropping: CGRect(origin: CGPoint(x: 1300, y: 100), size: size),
                                               displays: [builtIn, builtIn]) != nil)
    }

    /// A window always rests on one display (the maintainer's decision, 12 Nov; before, one let
    /// go across two displays stayed across them). It slides the shortest way onto the display
    /// most of it is on. Wholly on one display it stays, under the menu bar too.
    @Test func droppedAcrossDisplaysSlidesOntoOne() {
        let size = CGSize(width: 480, height: 270)
        let both = [builtIn, external]
        func rest(_ x: CGFloat, _ y: CGFloat) -> PictureInPictureLayout.Rest? {
            PictureInPictureLayout.rest(afterDropping: CGRect(origin: CGPoint(x: x, y: y), size: size), from: nil, displays: both)
        }
        // 128 pt on the built-in display and 352 pt on the external one: onto the external one.
        #expect(rest(1600, 300) == .init(frame: CGRect(x: 1728, y: 300, width: 480, height: 270), corner: nil))
        // Most of it on the built-in display: back onto that one.
        #expect(rest(1400, 300) == .init(frame: CGRect(x: 1728 - 480, y: 300, width: 480, height: 270), corner: nil))
        #expect(rest(600, 400) == nil)
        #expect(rest(600, 1117 - 270) == nil)
        // Past the outer edge it still springs into the corner, as in Arc (#332).
        #expect(rest(1728 + 1920 - 200, 100) == .init(frame: CGRect(x: 1728 + 1920 - 10 - 480, y: 10, width: 480, height: 270), corner: .bottomRight))
    }

    /// Dragged to another display, the window takes the same share of that display's width
    /// (the maintainer's decision, 12 Nov), around its centre, and stays on that display.
    @Test func draggedToAnotherDisplayKeepsItsShareOfTheWidth() throws {
        let both = [builtIn, external]
        // A quarter of the built-in display (432 of 1728) is a quarter of the external one: 480.
        let moved = PictureInPictureLayout.rest(afterDropping: CGRect(x: 2000, y: 300, width: 432, height: 243), from: builtIn, displays: both)
        #expect(moved == .init(frame: CGRect(x: 1976, y: 287, width: 480, height: 270), corner: nil))
        // Let go on the display it came from: no new size.
        #expect(PictureInPictureLayout.rest(afterDropping: CGRect(x: 600, y: 300, width: 432, height: 243), from: builtIn, displays: both) == nil)
        // As wide as the built-in display, it is as wide as the external one allows: 1055 pt of
        // visible height hold a 16:9 video 1876 pt wide.
        let full = PictureInPictureLayout.rest(afterDropping: CGRect(x: 1800, y: 50, width: 1728, height: 972), from: builtIn, displays: both)
        #expect(full?.frame.size == CGSize(width: 1876, height: 1055))
        #expect(external.visible.contains(try #require(full).frame))
    }

    /// A window larger than its display allows (the displays changed) shrinks to fit it.
    @Test func aWindowLargerThanItsDisplayShrinksToFit() throws {
        let big = PictureInPictureLayout.rest(afterDropping: CGRect(x: 0, y: 0, width: 2400, height: 1350), from: nil, displays: [builtIn])
        #expect(big?.frame.size == CGSize(width: 1728, height: 972))
        #expect(builtIn.visible.contains(try #require(big).frame))
    }

    /// A frame left half off the screen (0.1.38 saved where it was dropped, or the displays changed)
    /// opens in the nearest corner, not at that spot again (#332).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/332"))
    func reopensInACornerWhenLeftHalfOffScreen() {
        let off = PictureInPictureLayout.Placement(frame: CGRect(x: 1728 - 240, y: 100, width: 480, height: 270), display: "BUILTIN",
                                                   displayFrame: builtIn.frame)
        let f = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, displays: [builtIn], current: builtIn, remembered: off)
        #expect(f == CGRect(x: 1728 - 10 - 480, y: 10, width: 480, height: 270))
    }

    @Test func firstOpensTopRightTenPointsIn() {
        let f = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, screen: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                                    visible: CGRect(x: 0, y: 0, width: 1728, height: 1084), remembered: nil)
        #expect(f == CGRect(x: 1728 - 10 - 782, y: 1084 - 10 - 440, width: 782, height: 440))
    }

    /// The centre cluster follows Arc's size classes (#262). Arc's glyphs, measured on its windows:
    /// play/pause only and about 23.5 pt at 224 and 277 pt wide; the ±15 pair in ~31 pt circles and a
    /// 37–40 pt play/pause from 396 pt. Cra's fixed 22 pt play (14 pt of pause ink) and 17 pt skips
    /// were smaller than Arc's smallest at every size, and the skips crowded a tiny window.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/262"))
    func centreControlsGrowWithArcsSizeClasses() {
        let tiny = PictureInPictureLayout.centreControls(width: 224)
        #expect(!tiny.showsSkips && tiny.playPointSize == 28)
        #expect(PictureInPictureLayout.centreControls(width: 279) == tiny)
        let small = PictureInPictureLayout.centreControls(width: 285)
        #expect(small.showsSkips && small.playPointSize == 44 && small.skipPointSize == 28)
        #expect(PictureInPictureLayout.centreControls(width: 801).playPointSize == 44)
        // Never smaller than before at any size, and the cluster, hover discs and all, fits between
        // the corner buttons of the narrowest window that shows it.
        for w in [224.0, 279, 280, 285, 399, 400, 801, 1066] {
            let c = PictureInPictureLayout.centreControls(width: w)
            #expect(c.playPointSize > 22 && c.playDiameter >= 48)
            #expect(!c.showsSkips || (c.skipPointSize > 17 && c.clusterWidth <= w - 2 * PictureInPictureLayout.buttonCentreInset(width: w)))
        }
    }
}
