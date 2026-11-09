import CraCore
import Testing

/// Arc's "Block Cookie Banners": the consent managers' containers are hidden, nothing else.
struct CookieBannersTests {
    @Test(arguments: ["#onetrust-banner-sdk", "#CybotCookiebotDialog", "#didomi-host", ".qc-cmp2-container", "#usercentrics-root"])
    func hidesTheBigConsentManagers(selector: String) {
        #expect(CookieBanners.css.contains(selector))
    }

    @Test func hidesOnlyIdsClassesAndAttributes() {
        // No bare element selectors: they would hide parts of every page.
        for s in CookieBanners.selectors {
            #expect(s.hasPrefix("#") || s.hasPrefix(".") || s.hasPrefix("["), "\(s)")
        }
    }
}
