import Foundation

/// Arc's search-suggestions notice in the command bar (`CommandBar.SearchSuggestionsPrivacyView`, #314),
/// measured live in Arc 1.172.1 on 10 Nov 2026 (offline Arc, 2x captures). The (i) at the end of the empty
/// field opens it; the badge goes and a black banner takes the bottom row's place: "We talk to your search
/// engine to help us suggest results." with Search Settings… and Dismiss. Dismiss closes it for good (Arc's
/// `commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed`): no badge on any later ⌘T.
public enum SearchSuggestionsNotice {
    /// The badge, while suggestions go to the engine and the notice was never dismissed. The banner takes its
    /// place, and so do a scope's pill and a site's "Search …  Tab" (Arc keeps it while typing otherwise).
    public static func showsBadge(suggestionsOn: Bool, dismissed: Bool, bannerShown: Bool, scoped: Bool, offersSite: Bool) -> Bool {
        suggestionsOn && !dismissed && !bannerShown && !scoped && !offersSite
    }

    /// The banner, once the badge was pressed in this ⌘T, until it is dismissed or suggestions go off.
    public static func showsBanner(suggestionsOn: Bool, dismissed: Bool, bannerShown: Bool) -> Bool {
        suggestionsOn && !dismissed && bannerShown
    }

    /// The rows listed: the banner takes the last of the bar's `maxRows` places (Arc keeps the bar's
    /// height and lists four rows instead of five).
    public static func rowsListed(_ items: Int, maxRows: Int, banner: Bool) -> Int {
        banner ? min(items, max(0, maxRows - 1)) : items
    }

    /// The row places the bar is sized for: the rows, and one more for the banner.
    public static func rowPlaces(rows: Int, banner: Bool) -> Int { rows + (banner ? 1 : 0) }

    /// Points the banner takes at the bottom of the bar: the last row's 46, the 4 between rows, and the
    /// bar's bottom padding. Arc: 60, from the 4th row's bottom to the bar's edge.
    public static let bannerHeight: Double = 60
}

public extension CommandBarTones {
    /// The banner's buttons on the space's `focus` colour over the black banner: Arc's default theme
    /// (focus (70,77,219)) fills them (48,47,99) inside a (99,98,174) outline.
    var noticeButtonFill: RGB { RGB.black.mixed(with: selection.rgb, 0.377).mixed(with: .white, 0.094) }
    var noticeButtonOutline: RGB { RGB.black.mixed(with: selection.rgb, 0.67).mixed(with: .white, 0.25) }
}
