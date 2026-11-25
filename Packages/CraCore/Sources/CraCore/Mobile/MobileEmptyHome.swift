import Foundation

/// What the empty home screen (no tab open) shows: Cra's logo, which spins when flicked, over a field of dots that
/// ripple under a finger (`MobileRipples`, PR #708) on a near-black backdrop (near-white in light mode), "Tap to
/// search" over the pill and the bar's buttons floating without their slab. Until 25 Nov 2026 the dots were
/// App Settings ▸ Rippling Dots and Arc Search's lavender gradient was the default; Victor made the dots the
/// only look.
public struct MobileEmptyHome: Equatable, Sendable {
    public var showsDots: Bool
    public var showsLogo: Bool
    public var showsSearchHint: Bool
    /// The bar's buttons float on the backdrop without the bar's slab.
    public var barFloats: Bool
    /// The bar is the tab row's: Spaces, the plus and Settings, not the tab stack and the page menu, which have
    /// nothing to show with no tabs open.
    public var barShowsTabRow: Bool

    /// Whether the empty home is on screen: no tab is open, so the tab row would have no cards. The home is that
    /// empty row: the logo and the dots with the row's buttons, and the tab button opens no blank row over it.
    public static func isHome(tabOnScreen: Bool, rowTabs: Int) -> Bool {
        !tabOnScreen && rowTabs == 0
    }

    /// `home`: no tab is open (`isHome`). `searching`: the search sheet is up, `incognitoSearch` with its incognito
    /// grey; `pulling`: the sheet is being pulled out of the pill.
    public init(home: Bool, searching: Bool, incognitoSearch: Bool, pulling: Bool) {
        showsLogo = home && !searching
        // The dots stay behind the sheet, as the backdrop does, but not behind incognito's grey.
        showsDots = home && !(searching && incognitoSearch)
        showsSearchHint = home && !searching && !pulling
        barFloats = home
        barShowsTabRow = home
    }
}
