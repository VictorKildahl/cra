import XCTest

/// A page whose certificate can't be verified. `scripts/ios.sh test` serves one from
/// `iOS/Tests/popup_server.py` over HTTPS on loopback, with a self-signed certificate made for the
/// run, and passes its address as CRA_UNTRUSTED_TEST_URL; run by hand, start the server yourself
/// with `--tls-cert`/`--tls-key` (it then listens on port 18766).
final class CertificateTests: BrowserTestCase {
    /// The fixture by a domain name: App Transport Security lets IP addresses through, so only a
    /// dotted name is treated as a real site is. `cra.localhost` resolves to the loopback.
    private var untrusted: String {
        (ProcessInfo.processInfo.environment["CRA_UNTRUSTED_TEST_URL"] ?? "https://127.0.0.1:18766/untrusted")
            .replacingOccurrences(of: "127.0.0.1", with: "cra.localhost")
    }

    private var warning: XCUIElement { app.alerts["This connection is not private"] }

    private func openUntrusted() {
        launch(["-CraOpenURL", untrusted, "-CraSearch", "NO"])
        XCTAssertTrue(warning.waitForExistence(timeout: 20), "the warning never showed")
        XCTAssertFalse(app.webViews.staticTexts["Untrusted Fixture"].exists, "the page loaded before the user chose")
        keep("certificate-warning")
    }

    // promise: #569
    /// Continue Anyway opens the page, and the warning stays gone. It used to come straight back:
    /// App Transport Security applied to the web view and refuses a certificate it can't verify,
    /// whatever the navigation delegate answers, so the reload failed the same way. Fails without
    /// `NSAllowsArbitraryLoadsInWebContent` in iOS/Support/Info.plist (#568 added it).
    func testContinueAnywayOpensThePageAndTheWarningStaysGone() {
        openUntrusted()
        warning.buttons["Continue Anyway"].tap()
        waitForPage("Untrusted Fixture")
        XCTAssertFalse(warning.waitForExistence(timeout: 5), "the warning came back after Continue Anyway")
        XCTAssertTrue(app.webViews.staticTexts["Untrusted Fixture"].exists)
        keep("certificate-continued")
    }

    // promise: #569
    /// Go Back closes the warning, it stays closed, and the page is not loaded.
    func testGoBackClosesTheWarningAndLeavesThePageUnloaded() {
        openUntrusted()
        warning.buttons["Go Back"].tap()
        XCTAssertFalse(warning.waitForExistence(timeout: 5), "the warning came back after Go Back")
        XCTAssertFalse(app.webViews.staticTexts["Untrusted Fixture"].exists, "Go Back loaded the page anyway")
    }
}
