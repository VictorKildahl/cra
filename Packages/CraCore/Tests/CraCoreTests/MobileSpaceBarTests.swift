import CraCore
import CoreGraphics
import Testing

/// The Spaces sheet's bar of icons (issue #885): it scrolls when the icons don't fit, so the sheet
/// never grows past the screen with it.
struct MobileSpaceBarTests {
    /// Eight Spaces on an iPhone 13 mini (375 pt): 475 pt of icons, wider than the screen. Before
    /// #885 the bar took that width and pushed the whole sheet off both edges.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/885"))
    func eightSpacesScrollOnAMini() {
        #expect(MobileSpaceBar.iconsWidth(count: 8) == 475)
        #expect(MobileSpaceBar.scrolls(count: 8, width: 375))
        #expect(MobileSpaceBar.scrolls(count: 12, width: 440))
    }

    /// What fits stays centred and still, as before: six Spaces (349 pt) on a mini, seven on a 440 pt Pro Max.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/885"))
    func whatFitsStaysStill() {
        #expect(!MobileSpaceBar.scrolls(count: 6, width: 375))
        #expect(MobileSpaceBar.scrolls(count: 7, width: 375))
        #expect(!MobileSpaceBar.scrolls(count: 7, width: 440))
        #expect(!MobileSpaceBar.scrolls(count: 2, width: 320))
        #expect(MobileSpaceBar.iconsWidth(count: 1) == 34)
        #expect(MobileSpaceBar.iconsWidth(count: 0) == 0)
    }
}
