import CraCore
import Testing

struct AppIconBundleTests {
    /// X, 20 Nov 2026: a picked icon (an .icns of the user's own) changed the Dock but not Finder or
    /// /Applications. Arc puts the picked icon on its app too, and again at every launch, since an update
    /// replaces the bundle; picking Arc's own icon takes it off.
    @Test func aPickedIconGoesOnTheAppAndTheDefaultComesOff() {
        #expect(AppIconBundle.change(picked: "midnight", defaultID: "segments", bundleHasCustomIcon: false) == .put)
        // Already on it, perhaps another icon picked before: put it again (Arc's applier does the same).
        #expect(AppIconBundle.change(picked: "custom", defaultID: "segments", bundleHasCustomIcon: true) == .put)
        #expect(AppIconBundle.change(picked: "segments", defaultID: "segments", bundleHasCustomIcon: true) == .takeOff)
        // The bundle's own icon and nothing on it: the app never writes to its bundle.
        #expect(AppIconBundle.change(picked: "segments", defaultID: "segments", bundleHasCustomIcon: false) == .none)
    }

    /// At launch the picked icon goes back on only when an update brought a bundle without it, so a launch
    /// doesn't rewrite the app each time; Segments still takes a leftover one off.
    @Test func atLaunchOnlyWhatIsMissing() {
        #expect(AppIconBundle.change(picked: "midnight", defaultID: "segments", bundleHasCustomIcon: false, atLaunch: true) == .put)
        #expect(AppIconBundle.change(picked: "midnight", defaultID: "segments", bundleHasCustomIcon: true, atLaunch: true) == .none)
        #expect(AppIconBundle.change(picked: "segments", defaultID: "segments", bundleHasCustomIcon: true, atLaunch: true) == .takeOff)
        #expect(AppIconBundle.change(picked: "segments", defaultID: "segments", bundleHasCustomIcon: false, atLaunch: true) == .none)
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
    /// from its cache: since a pick goes on Cra.app (056ae73b) that was the icon picked before, so picking Segments
    /// after Original kept Original in the Dock (Victor, 23 Nov 2026).
    @Test func theDockIsGivenSegmentsToo() {
        #expect(AppIconBundle.dockImage(picked: "segments", defaultID: "segments") == "segments")
        #expect(AppIconBundle.dockImage(picked: "original", defaultID: "segments") == "original")
        #expect(AppIconBundle.dockImage(picked: "custom", defaultID: "segments") == "custom")
    }
}

