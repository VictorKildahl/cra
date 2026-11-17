import CraCore
import Testing

/// Chrome's pages that work on the normal profile open in a normal window, never in incognito,
/// where Cra quit on Extensions ▸ Manage Extensions… (GitHub #412).
struct IncognitoPagesTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/412"), arguments: [
        "chrome://extensions", "chrome://extensions/", "chrome://extensions/?id=abcdefghijklmnopabcdefghijklmnop",
        "chrome://extensions/shortcuts", "chrome://settings", "chrome://settings/searchEngines",
        "chrome://settings/content/siteDetails?site=https%3A%2F%2Fexample.com", "chrome://history",
        "chrome://password-manager/passwords", "chrome://help", "chrome://apps", "chrome://chrome-signin",
        "CHROME://Extensions", "about:settings", "about:extensions", "view-source:chrome://settings",
        " chrome://settings ",
    ])
    func chromesNormalProfilePagesStayOut(url: String) {
        #expect(!IncognitoPages.allows(url))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/412"), arguments: [
        "https://example.com", "https://chromewebstore.google.com/category/extensions", "http://settings/",
        "chrome://version", "chrome://downloads", "chrome://flags", "chrome://newtab", "chrome://settings-frame",
        "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html", "about:blank", "view-source:https://example.com",
        "", "settings",
    ])
    func everythingElseOpensInIncognito(url: String) {
        #expect(IncognitoPages.allows(url))
    }
}
