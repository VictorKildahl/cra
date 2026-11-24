import CraCore
import Testing

struct AppIconBundleTests {
    /// GitHub #724: a picked icon on Cra.app (Finder's `Icon\r` file and its com.apple.FinderInfo flag) breaks the
    /// app's signature: `codesign --strict` refuses the attribute, and lsd kept registering the app launch-disabled
    /// with trustd busy. The app never puts an icon on itself, whatever is picked; the Dock tile (applicationIconImage
    /// and the CraDockTile plug-in) shows the pick.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/724")) func theAppNeverPutsAnIconOnItself() {
        #expect(AppIconBundle.change(bundleHasFinderIcon: false) == .none)
    }

    /// One that 0.1.54 or 0.1.55 put there comes off at the next launch or pick, so the signature holds again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/724")) func anIconAnEarlierCraPutOnTheAppComesOff() {
        #expect(AppIconBundle.change(bundleHasFinderIcon: true) == .takeOff)
    }

    /// `codesign --strict` refuses a com.apple.FinderInfo attribute on the bundle whatever it holds, and the
    /// `Icon\r` file is outside the sealed Contents: either counts as an icon on the app.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/724")) func anythingOfAFinderIconCounts() {
        #expect(!AppIconBundle.hasFinderIcon(finderInfo: nil, iconFile: false))
        #expect(AppIconBundle.hasFinderIcon(finderInfo: [UInt8](repeating: 0, count: 32), iconFile: false))
        #expect(AppIconBundle.hasFinderIcon(finderInfo: nil, iconFile: true))
    }

    /// Finder's custom icon flag (kHasCustomIcon, 0x0400) is in the finder flags, bytes 8-9 of the
    /// com.apple.FinderInfo attribute, big-endian.
    @Test func findersCustomIconFlag() {
        var info = [UInt8](repeating: 0, count: 32)
        #expect(!AppIconBundle.hasCustomIcon(finderInfo: info))
        info[8] = 0x04
        #expect(AppIconBundle.hasCustomIcon(finderInfo: info))
        info[8] = 0x00
        info[9] = 0x04
        #expect(!AppIconBundle.hasCustomIcon(finderInfo: info))
        #expect(!AppIconBundle.hasCustomIcon(finderInfo: []))
        #expect(!AppIconBundle.hasCustomIcon(finderInfo: [0, 0, 0, 0, 0, 0, 0, 0, 0x04]))
    }

    /// Segments, the bundle's own, is given to the Dock like any other pick. Left to the Dock, the bundle's icon came
    /// from its cache: after 0.1.54 put a pick on Cra.app (056ae73b) that was the icon picked before, so picking
    /// Segments after Original kept Original in the Dock (Victor, 23 Nov 2026).
    @Test func theDockIsGivenSegmentsToo() {
        #expect(AppIconBundle.dockImage(picked: "segments", defaultID: "segments") == "segments")
        #expect(AppIconBundle.dockImage(picked: "original", defaultID: "segments") == "original")
        #expect(AppIconBundle.dockImage(picked: "custom", defaultID: "segments") == "custom")
    }
}
