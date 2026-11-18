import XCTest

/// Passkeys on websites. `scripts/ios.sh test` starts `iOS/Tests/popup_server.py` on loopback and
/// passes its address as CRA_POPUP_TEST_BASE_URL; run by hand, start it yourself (port 18765).
final class PasskeyTests: BrowserTestCase {
    /// The fixture as `localhost`: WebAuthn takes the page's host as the relying party, and an IP
    /// address can't be one.
    private var page: String {
        let base = ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765"
        return base.replacingOccurrences(of: "127.0.0.1", with: "localhost") + "/passkey"
    }

    /// GitHub #536: no passkey worked on any site. WebKit hands a page's WebAuthn request to iOS
    /// only in an app with Apple's browser entitlement (`com.apple.developer.web-browser`, #504);
    /// without it the request is refused at once with NotAllowedError and no sheet shows. With it,
    /// iOS's passkey sheet comes up, which also offers 1Password and other providers.
    // promise: #536
    func testASitesPasskeyRequestBringsUpTheSystemPasskeySheet() {
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Passkey Fixture")
        app.webViews.buttons["Create passkey"].tap()
        let open = app.webViews.staticTexts["Passkey request still open"]
        let refused = app.webViews.staticTexts["Passkey refused: NotAllowedError"]
        let answered = open.waitForExistence(timeout: 15) || refused.exists
        keep("passkey-sheet")
        XCTAssertTrue(answered, "the page never heard back about its passkey request")
        XCTAssertFalse(refused.exists, "WebKit refused the passkey request without asking iOS")
        XCTAssertTrue(open.exists, "the request waits on iOS's passkey sheet")
    }
}
