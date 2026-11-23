import Foundation

/// The picked app icon on Cra.app itself, for Finder, /Applications, Launchpad and Spotlight, which draw the
/// bundle's icon and never the Dock tile's (X, 20 Nov 2026: "it changes in the Dock but not elsewhere"). Arc
/// does the same: its AppIconApplier puts the picked icon on Arc.app (Finder's custom icon: an `Icon\r` file
/// and a flag in com.apple.FinderInfo) and puts it back at launch, since an update replaces the bundle.
public enum AppIconBundle {
    public enum Change: Equatable, Sendable {
        /// Put the picked icon on the app.
        case put
        /// Take a custom icon off: the app shows its own again.
        case takeOff
        /// Leave the bundle alone.
        case none
    }

    /// What the app does to its bundle when `picked` is the icon, at the pick or at launch. A pick puts the
    /// icon on even when one is there (it may be another). At launch it goes on only when the bundle has none,
    /// as after an update, which brings a bundle with only its own icon; else every launch would rewrite it.
    /// With the bundle's own icon picked the app writes to its bundle only to take a custom one off.
    public static func change(picked: String, defaultID: String, bundleHasCustomIcon: Bool, atLaunch: Bool = false) -> Change {
        if picked != defaultID { return atLaunch && bundleHasCustomIcon ? .none : .put }
        return bundleHasCustomIcon ? .takeOff : .none
    }

    /// Finder's custom icon flag (kHasCustomIcon, 0x0400) in a com.apple.FinderInfo value: the finder
    /// flags are bytes 8-9, big-endian.
    public static func hasCustomIcon(finderInfo: [UInt8]) -> Bool {
        finderInfo.count >= 10 && (UInt16(finderInfo[8]) << 8 | UInt16(finderInfo[9])) & 0x0400 != 0
    }

    /// The picture the Dock tile is given for `picked` (the running app's applicationIconImage and the Dock tile
    /// plug-in's view): always the picked one, Segments too (app-icons/segments.png, the bundle's icon on Apple's
    /// grid). Left to the Dock, the bundle's own icon came from the Dock's cache, which since a pick goes on Cra.app
    /// can be the icon picked before: Segments picked after Original kept Original (Victor, 23 Nov 2026).
    public static func dockImage(picked: String, defaultID: String) -> String? {
        picked
    }
}

