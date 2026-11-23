import Foundation

/// What the empty home screen (no tab open, no tab row) shows. Arc Search's own is the default: its gradient with
/// Cra's logo in the middle, which spins when flicked. App Settings ▸ Rippling Dots (Cra's own, not Arc Search's,
/// PR #708) lays a field of dots that ripple under a finger (`MobileRipples`) on a near-black backdrop, near-white in
/// light mode, keeps the logo over it, shows "Tap to search" over the pill and floats the bar's buttons without
/// their slab.
public struct MobileEmptyHome: Equatable, Sendable {
    public enum Backdrop: Equatable, Sendable {
        /// Arc Search's lavender gradient with its pink bloom.
        case arcSearch
        /// Near-black with soft warm patches (light mode: near-white), under the dots.
        case dots
    }

    public var backdrop: Backdrop
    public var showsDots: Bool
    public var showsLogo: Bool
    public var showsSearchHint: Bool
    /// The bar's buttons float on the backdrop without the bar's slab.
    public var barFloats: Bool

    /// `home`: no tab is open and the tab row isn't up. `searching`: the search sheet is up, `incognitoSearch` with
    /// its incognito grey; `pulling`: the sheet is being pulled out of the pill.
    public init(dots: Bool, home: Bool, searching: Bool, incognitoSearch: Bool, pulling: Bool) {
        backdrop = dots ? .dots : .arcSearch
        showsLogo = home && !searching
        // The dots stay behind the sheet, as the backdrop does, but not behind incognito's grey.
        showsDots = dots && home && !(searching && incognitoSearch)
        showsSearchHint = dots && home && !searching && !pulling
        barFloats = dots && home
    }
}
