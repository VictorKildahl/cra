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

    /// GitHub #739: Segments, the bundle's own icon, is left to the Dock, which draws it in the icon style picked in
    /// System Settings ▸ Appearance (Default, Dark, Clear, Tinted), as it does every app's. A picture the app hands
    /// the Dock is drawn as it is, so from 0.1.55, which gave the Dock Segments' picture, Cra's icon stayed light in
    /// a dark Dock. A pick is still given to the Dock: it isn't the bundle's icon, so only the app can show it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func segmentsIsLeftToTheDockSoItFollowsTheIconStyle() {
        #expect(AppIconBundle.dockImage(picked: "segments", defaultID: "segments", bundleIconStale: false) == nil)
        #expect(AppIconBundle.dockImage(picked: "original", defaultID: "segments", bundleIconStale: false) == "original")
        #expect(AppIconBundle.dockImage(picked: "custom", defaultID: "segments", bundleIconStale: false) == "custom")
    }

    /// GitHub #884: the icon switches with macOS's light and dark (Icon & widget style Auto, or Dark) only when it is
    /// the bundle's own, Segments, which macOS draws from its Icon Composer icon with a light and a dark look
    /// (AppIconCatalogTests). The other picks, Original among them, are pictures the Dock draws as given, as Arc's
    /// are: Arc 1.174.3's AppIcon has no dark appearance in its Assets.car.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/884")) func onlyTheBundlesOwnIconSwitchesWithLightAndDark() {
        for picked in ["segments", "original", "midnight", "custom"] {
            let switches = AppIconBundle.dockImage(picked: picked, defaultID: "segments", bundleIconStale: false) == nil
            #expect(switches == (picked == "segments"), "\(picked)")
        }
    }

    /// The one case the Dock is given Segments' picture: this launch found a Finder icon an earlier Cra put on
    /// Cra.app (0.1.54, 0.1.55; #724). The Dock's cache of the bundle's icon can then still be the icon picked
    /// before, so Segments picked after Original kept Original (Victor, 23 Nov 2026), until the next launch.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func segmentsIsGivenToTheDockWhileItsCacheMayBeStale() {
        #expect(AppIconBundle.dockImage(picked: "segments", defaultID: "segments", bundleIconStale: true) == "segments")
        #expect(AppIconBundle.dockImage(picked: "original", defaultID: "segments", bundleIconStale: true) == "original")
    }

    /// Setting applicationIconImage, even to nil, hands the Dock a picture of the bundle's icon, drawn outside the
    /// icon style: a launch with Segments never touches it, and picking Segments after a pick takes the pick back.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func aLaunchWithSegmentsLeavesTheApplicationIconAlone() {
        #expect(!AppIconBundle.setsApplicationIcon(giving: false, gaveBefore: false))
        #expect(AppIconBundle.setsApplicationIcon(giving: true, gaveBefore: false))
        #expect(AppIconBundle.setsApplicationIcon(giving: false, gaveBefore: true))
    }

    /// Settings ▸ Icon's Segments tile is the icon the Dock shows: on macOS 26 the Dock draws the Icon Composer icon
    /// (the glass Segments, #739), so the tile is its picture; on macOS 14 and 15 AppIcon.icns, the sticker. 3225cbae
    /// changed the Dock's and left the tile the sticker (giladgd on #690). The other icons are the same everywhere.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/865")) func theSegmentsTileIsTheIconTheDockShows() {
        #expect(AppIconBundle.previewName(for: "segments", defaultID: "segments", macOSMajor: 26) == "segments-glass")
        #expect(AppIconBundle.previewName(for: "segments", defaultID: "segments", macOSMajor: 27) == "segments-glass")
        #expect(AppIconBundle.previewName(for: "segments", defaultID: "segments", macOSMajor: 15) == "segments")
        #expect(AppIconBundle.previewName(for: "segments", defaultID: "segments", macOSMajor: 14) == "segments")
        #expect(AppIconBundle.previewName(for: "original", defaultID: "segments", macOSMajor: 26) == "original")
    }
}
