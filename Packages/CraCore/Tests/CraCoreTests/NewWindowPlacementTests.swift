import CoreGraphics
import Testing
@testable import CraCore

struct NewWindowPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let size = CGSize(width: 1400, height: 880)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/528"))
    func aFullScreenWindowOpensTheNewOneFullScreen() {
        let full = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let p = NewWindowPlacement.of(source: full, sourceFullScreen: true, screen: screen, defaultSize: size)
        #expect(p.opensFullScreen)
        // Out of full screen it is the default size, centred on the same screen.
        #expect(p.frame == CGRect(x: 56, y: 32, width: 1400, height: 880))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/528"))
    func fullScreenOnTheSecondDisplayStaysThere() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1055)
        let p = NewWindowPlacement.of(source: CGRect(x: 1512, y: -200, width: 1920, height: 1080), sourceFullScreen: true,
                                      screen: second, defaultSize: size)
        #expect(p.opensFullScreen)
        #expect(p.frame.map(second.contains) == true)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/528"))
    func aSmallScreenShrinksTheWindowedFrame() {
        let small = CGRect(x: 0, y: 0, width: 1280, height: 775)
        let p = NewWindowPlacement.of(source: small, sourceFullScreen: true, screen: small, defaultSize: size)
        #expect(p.frame == small)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/528"))
    func aWindowedWindowOpensAWindowedOne() {
        let p = NewWindowPlacement.of(source: CGRect(x: 100, y: 100, width: 1000, height: 700), sourceFullScreen: false,
                                      screen: screen, defaultSize: size)
        #expect(!p.opensFullScreen)
    }

    @Test func aCascadePastTheScreenGoesBackToItsTopLeft() {
        let p = NewWindowPlacement.of(source: CGRect(x: 300, y: 0, width: 1200, height: 800), sourceFullScreen: false,
                                      screen: screen, defaultSize: size)
        #expect(p == .cascaded(CGRect(x: 22, y: 944 - 800 - 22, width: 1200, height: 800)))
    }

    @Test func aCascadeOnScreenStaysPut() {
        let p = NewWindowPlacement.of(source: CGRect(x: 100, y: 100, width: 1000, height: 700), sourceFullScreen: false,
                                      screen: screen, defaultSize: size)
        #expect(p == .cascaded(CGRect(x: 122, y: 78, width: 1000, height: 700)))
    }

    @Test func noWindowInUseKeepsTheDefaultPlace() {
        let p = NewWindowPlacement.of(source: nil, sourceFullScreen: false, screen: screen, defaultSize: size)
        #expect(p == .standard)
        #expect(p.frame == nil)
    }
}
