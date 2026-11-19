import XCTest

/// Addresses another app handles (mailto:, tel:, sms: and any custom scheme): the page hands them
/// to that app and stays as it is. `scripts/ios.sh test` serves the pages from
/// `iOS/Tests/popup_server.py` on loopback (CRA_POPUP_TEST_BASE_URL); run by hand, start it
/// yourself (port 18765).
///
/// The simulator has no Mail and no Phone app, so `UIApplication.open` reports false for mailto:
/// and tel: there: those tests check the page is left alone, which is the same on an iPhone whose
/// app opens. Messages is on the simulator, so sms: shows the hand-over itself.
final class ExternalLinkTests: BrowserTestCase {
    private var base: String {
        ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765"
    }

    private var errorHeading: XCUIElement { app.webViews.staticTexts["This page couldn’t load"] }

    /// The fixture is still the page: no error page came, and the tab is still the fixture.
    private func assertPageKept(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(errorHeading.waitForExistence(timeout: 4), "an error page replaced the page", file: file, line: line)
        XCTAssertTrue(app.webViews.staticTexts[title].exists, "the page is gone", file: file, line: line)
        app.buttons["bar-menu"].tap()
        let host = app.staticTexts["menu-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(host.label, "127.0.0.1", "the tab left the page", file: file, line: line)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertFalse(host.waitForExistence(timeout: 2), file: file, line: line)
    }

    /// Regression in TestFlight 1086: a tapped mailto: or tel: link went to WebKit, which can't load
    /// it (-1002 "unsupported URL"), and since #568's error page that failure replaced the page
    /// with "This page couldn’t load". Before that, the tap did nothing. Now it goes to
    /// `UIApplication.open`; with no app for it (the simulator has neither Mail nor Phone) the page
    /// stays as it is.
    // promise: crash-1086-external-schemes
    func testATappedEmailOrPhoneLinkLeavesThePageAsItIs() {
        launch(["-CraOpenURL", base + "/schemes", "-CraSearch", "NO"])
        waitForPage("Scheme Links")
        app.webViews.links["Write an email"].tap()
        assertPageKept("Scheme Links")
        keep("mailto-tapped")
        app.webViews.links["Call the fixture"].tap()
        assertPageKept("Scheme Links")
        keep("tel-tapped")
    }

    /// A tapped link to another app's address opens that app at once, with no question first, as
    /// in Safari: sms: brings up Messages, and the page is still there on coming back.
    // promise: crash-1086-external-schemes
    func testATappedMessageLinkOpensMessages() {
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.terminate()
        launch(["-CraOpenURL", base + "/schemes", "-CraSearch", "NO"])
        waitForPage("Scheme Links")
        app.webViews.links["Text the fixture"].tap()
        XCTAssertTrue(messages.wait(for: .runningForeground, timeout: 15), "Messages never opened")
        XCTAssertFalse(app.alerts.firstMatch.exists, "a tap asked first")
        keep("sms-tapped")
        messages.terminate()
        app.activate()
        waitForPage("Scheme Links")
        assertPageKept("Scheme Links")
    }

    /// A page that sends itself to another app's address without a tap asks first, as Safari
    /// does ("Open this page in …?"), and whatever the answer the page stays: no error page.
    // promise: crash-1086-external-schemes
    func testARedirectToAnEmailAddressAsksFirstAndKeepsThePage() {
        launch(["-CraOpenURL", base + "/scheme-redirect", "-CraSearch", "NO"])
        let question = app.alerts["Open this page in another app?"]
        XCTAssertTrue(question.waitForExistence(timeout: 20), "the redirect didn't ask")
        XCTAssertTrue(question.buttons["Cancel"].exists)
        keep("redirect-asks")
        // No Mail on the simulator: Open finds no app, and the page stays.
        question.buttons["Open"].tap()
        XCTAssertFalse(question.waitForExistence(timeout: 2))
        assertPageKept("Scheme Redirect")
        keep("redirect-opened")
    }
}
