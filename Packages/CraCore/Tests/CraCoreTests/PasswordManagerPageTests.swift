import CraCore
import Testing

/// The command bar's Open Passwords (#905): Chromium's password manager, on the current site's logins.
struct PasswordManagerPageTests {
    /// On a site, the list opens searched for it (the page's `q`), so its logins are the ones shown.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/905"))
    func opensOnTheSitesLogins() {
        #expect(PasswordManagerPage.address(forPage: "https://www.linkedin.com/jobs/view/1", incognito: false)
                == "chrome://password-manager/passwords?q=linkedin.com")
        #expect(PasswordManagerPage.address(forPage: "http://portal.client.example:8080/login", incognito: false)
                == "chrome://password-manager/passwords?q=portal.client.example")
    }

    /// No site (a new tab, a chrome:// page, nothing open), or an incognito window's page, whose site must not show
    /// up in the normal window the list opens in: the whole list.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/905"))
    func otherwiseTheWholeList() {
        let all = "chrome://password-manager/passwords"
        #expect(PasswordManagerPage.address(forPage: nil, incognito: false) == all)
        #expect(PasswordManagerPage.address(forPage: "chrome://extensions/", incognito: false) == all)
        #expect(PasswordManagerPage.address(forPage: "about:blank", incognito: false) == all)
        #expect(PasswordManagerPage.address(forPage: "https://private.example/", incognito: true) == all)
    }
}
