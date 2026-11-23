import Foundation

/// Cra.app itself never carries the picked app icon (GitHub #724). 0.1.54 and 0.1.55 put it there as Finder's
/// custom icon (an `Icon\r` file and a flag in com.apple.FinderInfo), as Arc's AppIconApplier does, so Finder and
/// /Applications showed it. That attribute on the bundle breaks the app's signature: `codesign --strict` refuses
/// it, and lsd kept registering the app launch-disabled while trustd checked it over and over. The pick shows in
/// the Dock (applicationIconImage, and the CraDockTile plug-in after Cra quits), which needs no change to the app.
public enum AppIconBundle {
    public enum Change: Equatable, Sendable {
        /// Take Finder's custom icon off: the app's signature holds again.
        case takeOff
        /// Leave the bundle alone.
        case none
    }

    /// What the app does to its bundle, at launch or at a pick: it writes to it only to take off a Finder icon an
    /// earlier Cra put there (an `Icon\r` file, or a com.apple.FinderInfo attribute, which `codesign --strict`
    /// refuses whatever it holds), whatever icon is picked.
    public static func change(bundleHasFinderIcon: Bool) -> Change {
        bundleHasFinderIcon ? .takeOff : .none
    }

    /// Whether the bundle has anything of a Finder custom icon on it: the com.apple.FinderInfo attribute (nil when
    /// it's absent) or the `Icon\r` file.
    public static func hasFinderIcon(finderInfo: [UInt8]?, iconFile: Bool) -> Bool {
        finderInfo != nil || iconFile
    }

    /// Finder's custom icon flag (kHasCustomIcon, 0x0400) in a com.apple.FinderInfo value: the finder
    /// flags are bytes 8-9, big-endian.
    public static func hasCustomIcon(finderInfo: [UInt8]) -> Bool {
        finderInfo.count >= 10 && (UInt16(finderInfo[8]) << 8 | UInt16(finderInfo[9])) & 0x0400 != 0
    }

    /// The picture the Dock tile is given for `picked` (the running app's applicationIconImage and the Dock tile
    /// plug-in's view): always the picked one, Segments too (app-icons/segments.png, the bundle's icon on Apple's
    /// grid). Left to the Dock, the bundle's own icon came from the Dock's cache, which after 0.1.54 put a pick on
    /// Cra.app can be the icon picked before: Segments picked after Original kept Original (Victor, 23 Nov 2026).
    public static func dockImage(picked: String, defaultID: String) -> String? {
        picked
    }
}
