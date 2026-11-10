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

    /// Arc's limits: never below 224 × 126 for 16:9 (the 223 × 125.5 window in #246 was Arc's
    /// minimum), at most 61.7 % of the screen's width and the visible height less 20.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/246"))
    func sizeStaysInArcsLimits() {
        let l = PictureInPictureLayout.sizeLimits(aspect: 16.0 / 9, screen: screen, visible: visible)
        #expect(l.min == CGSize(width: 224, height: 126))
        #expect(l.max == CGSize(width: 1184, height: 955))
        // Portrait: 224 wide at least, not 126 tall.
        #expect(PictureInPictureLayout.sizeLimits(aspect: 9.0 / 16, screen: screen, visible: visible).min == CGSize(width: 224, height: 398))
        // A remembered frame below the minimum (Cra allowed 160 × 90) opens at Arc's minimum.
        let small = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, screen: screen, visible: visible,
                                                        remembered: CGRect(x: 100, y: 500, width: 160, height: 90))
        #expect(small == CGRect(x: 100, y: 464, width: 224, height: 126))
        // One wider than the screen allows opens at the widest Arc allows.
        let wide = PictureInPictureLayout.initialFrame(aspect: 16.0 / 9, screen: screen, visible: visible,
                                                       remembered: CGRect(x: 0, y: 100, width: 1600, height: 900))
        #expect(wide.size == CGSize(width: 1184, height: 666))
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
