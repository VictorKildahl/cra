import CraCore
import Foundation
import Testing

/// Arc 1.172.1's search-suggestions notice in ⌘T (#314), measured live 10 Nov 2026: the (i) opens a banner
/// in the bottom row's place, Dismiss ends it for good. Until then Cra's badge was a picture.
struct SearchSuggestionsNoticeTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/314")) func theBadgeShowsUntilPressedAndNeverAfterDismiss() {
        #expect(SearchSuggestionsNotice.showsBadge(suggestionsOn: true, dismissed: false, bannerShown: false, scoped: false, offersSite: false))
        // Pressed: the banner takes its place.
        #expect(!SearchSuggestionsNotice.showsBadge(suggestionsOn: true, dismissed: false, bannerShown: true, scoped: false, offersSite: false))
        #expect(SearchSuggestionsNotice.showsBanner(suggestionsOn: true, dismissed: false, bannerShown: true))
        // Dismissed: neither, in this ⌘T or any later one.
        #expect(!SearchSuggestionsNotice.showsBadge(suggestionsOn: true, dismissed: true, bannerShown: false, scoped: false, offersSite: false))
        #expect(!SearchSuggestionsNotice.showsBanner(suggestionsOn: true, dismissed: true, bannerShown: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/314")) func nothingToTellWithSuggestionsOff() {
        #expect(!SearchSuggestionsNotice.showsBadge(suggestionsOn: false, dismissed: false, bannerShown: false, scoped: false, offersSite: false))
        #expect(!SearchSuggestionsNotice.showsBanner(suggestionsOn: false, dismissed: false, bannerShown: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/314")) func aScopeOrASiteSearchTakesTheBadgesPlace() {
        #expect(!SearchSuggestionsNotice.showsBadge(suggestionsOn: true, dismissed: false, bannerShown: false, scoped: true, offersSite: false))
        #expect(!SearchSuggestionsNotice.showsBadge(suggestionsOn: true, dismissed: false, bannerShown: false, scoped: false, offersSite: true))
    }

    /// Arc listed four rows above the banner where it had listed five, in a bar of the same height.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/314")) func theBannerTakesTheLastRowsPlace() {
        #expect(SearchSuggestionsNotice.rowsListed(5, maxRows: 5, banner: true) == 4)
        #expect(SearchSuggestionsNotice.rowPlaces(rows: 4, banner: true) == 5)
        #expect(SearchSuggestionsNotice.rowsListed(5, maxRows: 5, banner: false) == 5)
        // A short list keeps its rows and the bar grows by the banner.
        #expect(SearchSuggestionsNotice.rowsListed(2, maxRows: 5, banner: true) == 2)
        #expect(SearchSuggestionsNotice.rowPlaces(rows: 2, banner: true) == 3)
        #expect(SearchSuggestionsNotice.rowPlaces(rows: 0, banner: true) == 1)
    }

    /// Default theme, focus (70,77,219): Arc's buttons are (48,47,99) inside (99,98,174).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/314")) func theButtonsTakeTheSpacesFocusColour() {
        let tones = CommandBarTones(selection: ArcThemeData.Color(RGB(70 / 255, 77 / 255, 219 / 255), 0.86), badge: .black)
        func gap(_ a: RGB, _ b: (Int, Int, Int)) -> Int {
            [abs(Int((a.r * 255).rounded()) - b.0), abs(Int((a.g * 255).rounded()) - b.1), abs(Int((a.b * 255).rounded()) - b.2)].max()!
        }
        #expect(gap(tones.noticeButtonFill, (48, 47, 99)) <= 4, "\(tones.noticeButtonFill)")
        #expect(gap(tones.noticeButtonOutline, (99, 98, 174)) <= 5, "\(tones.noticeButtonOutline)")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/314")) func theDismissalIsKeptInWindowsJSON() throws {
        var prefs = WindowPrefs()
        #expect(!prefs.searchSuggestionsNoticeDismissed)
        prefs.searchSuggestionsNoticeDismissed = true
        let back = try JSONDecoder().decode(WindowPrefs.self, from: JSONEncoder().encode(prefs))
        #expect(back.searchSuggestionsNoticeDismissed)
        // Files from before the notice read as not dismissed.
        let old = try JSONDecoder().decode(WindowPrefs.self, from: Data(#"{"sidebarWidth": 300}"#.utf8))
        #expect(!old.searchSuggestionsNoticeDismissed)
    }
}
