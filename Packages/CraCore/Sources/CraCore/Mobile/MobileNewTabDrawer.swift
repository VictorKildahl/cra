import CoreGraphics
import Foundation

/// The new tab drawer while it is out: the search sheet grown out of the bar's pill, as opposed to
/// the sheet that takes the page menu's place to edit the address. Everything here goes back to
/// its start once the drawer has sunk back into the bar.
public struct MobileNewTabDrawer: Equatable, Sendable {
    /// What a finger on the drawer holds the address field to, whatever the drawer itself does.
    public enum FieldHold: Equatable, Sendable {
        /// The field morphs with the drawer.
        case none
        /// A pull up out of the pill: the plus stays a plus until the finger lets go.
        case closed
        /// A drag down on the open drawer: the field stays open, full size, until the finger lets go.
        case open
    }

    /// The search sheet is this drawer, grown out of the bar: its background is the bar's material.
    public var growsFromBar = false
    public var fieldHold: FieldHold = .none
    /// The drawer's material and edge are in: from the first touch until a close starts.
    public var showsMaterial = false
    /// Pulled up and let go: its rise into place springs, rather than following the keyboard.
    public var opensFromPull = false

    public init() {}

    /// How far the drawer's top edge rises before the bar's tabs and menu buttons have faded away,
    /// in points.
    public static let controlsFadeDistance: CGFloat = 120
    /// How long the bar's material takes to become the drawer's. It starts when the drawer does,
    /// not with the finger's distance.
    public static let materialFade: TimeInterval = 0.15
    /// Let go on its way down, or pulled up and released: a short spring with a small overshoot as
    /// it settles.
    public static let bounce = MobileMotion.Spring(response: 0.3, dampingRatio: 0.82)

    /// A dark grey haze over the drawer's material in dark mode (`Palette.drawerHaze`), so it reads
    /// frosted rather than as a plain dark panel; less over the tab switcher. None in light mode,
    /// whose material is already milky, nor in incognito, whose black covers it.
    public static func haze(darkMode: Bool, incognito: Bool, overTabRow: Bool = false) -> CGFloat {
        guard darkMode, !incognito else { return 0 }
        return overTabRow ? 0.3 : 0.6
    }

    /// The tabs and menu buttons over the drawer's top edge: 1 at the bar, 0 once the drawer has
    /// risen `controlsFadeDistance`.
    public static func controlsOpacity(reach: CGFloat) -> CGFloat {
        min(1, max(0, 1 - reach / controlsFadeDistance))
    }

    /// The bar's material while the drawer is out: there in full, as the drawer's background. Over
    /// the home or the tab row, where the bar has no slab of its own, a drawer let go takes the
    /// material down with it, gone by the time it is back in the bar (`openness` 0).
    public static func materialOpacity(floats: Bool, letGo: Bool, openness: CGFloat) -> CGFloat {
        floats && letGo ? min(1, max(0, openness)) : 1
    }

    /// The drawer's top corners: square at the bar and the sheet's own radius only once the drawer
    /// is fully open, `openness` being 0 at the bar and 1 at its open top.
    public static func cornerRadius(openness: CGFloat) -> CGFloat {
        MobileSearchSheet.cornerRadius * min(1, max(0, openness))
    }

    /// How open the address field is, 0 the pill's plus and 1 the open field. While searching it is
    /// open; otherwise a hold wins over the sheet's `pulled` openness.
    public func fieldOpenness(isSearching: Bool, pulled: CGFloat?) -> CGFloat {
        if isSearching { return 1 }
        switch fieldHold {
        case .closed: return 0
        case .open: return 1
        case .none: return pulled ?? 0
        }
    }

    /// The pinned tabs and suggestions: the drawer fades them with its own open position, so they
    /// are all there once it is fully open; a sheet in place of the page menu keeps them with its
    /// field.
    public func listOpenness(fieldOpenness: CGFloat, drawerProgress: CGFloat) -> CGFloat {
        growsFromBar ? drawerProgress : fieldOpenness
    }

    /// The open address field's fill: the drawer's follows the page under the bar.
    public func fieldStyle(pageIsLight: Bool) -> MobileSearchSheet.FieldStyle {
        MobileSearchSheet.FieldStyle(growsFromBar: growsFromBar, pageIsLight: pageIsLight)
    }
}
