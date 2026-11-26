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

    /// The picture the Dock tile is given for `picked` (the running app's applicationIconImage, Chromium's download
    /// badge view and the Dock tile plug-in), nil to leave the tile to the Dock. A pick is always given: only the app
    /// can show it. Segments, the bundle's own icon, is left to the Dock, which draws it in the icon style picked in
    /// System Settings ▸ Appearance (Dark, Clear, Tinted) as it does every app's; a picture the app hands over is
    /// drawn as it is, so 0.1.55's light Segments sat in a dark Dock (GitHub #739). Only when this launch found a
    /// Finder icon an earlier Cra put on Cra.app (0.1.54, 0.1.55; #724) is Segments given too: the Dock's cache of
    /// the bundle's icon can then still be the icon picked before, so Segments picked after Original kept Original
    /// (Victor, 23 Nov 2026).
    public static func dockImage(picked: String, defaultID: String, bundleIconStale: Bool) -> String? {
        picked != defaultID || bundleIconStale ? picked : nil
    }

    /// Whether the app sets NSApp.applicationIconImage at all: only to give the Dock a picture, or to take back one
    /// it gave. Setting it, even to nil, makes AppKit hand the Dock a picture of the bundle's icon, which the Dock
    /// draws as it is, outside the system's icon style (GitHub #739); a launch with Segments leaves it alone.
    public static func setsApplicationIcon(giving: Bool, gaveBefore: Bool) -> Bool {
        giving || gaveBefore
    }

    /// The picture (resources/app-icons/<name>.png) Settings ▸ Icon shows for an icon: the icon the Dock shows. Segments
    /// is the bundle's own icon, which macOS 26 draws from the Icon Composer icon (the glass Segments, GitHub #739) and
    /// macOS 14 and 15 from AppIcon.icns (the sticker), so its tile follows the system; the others are pictures the app
    /// hands the Dock, the same everywhere (#865).
    public static func previewName(for id: String, defaultID: String, macOSMajor: Int) -> String {
        id == defaultID && macOSMajor >= 26 ? "segments-glass" : id
    }
}
