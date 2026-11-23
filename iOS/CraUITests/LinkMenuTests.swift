import XCTest
import UIKit

/// A long press on a link, and editing a page's address (GitHub #572).
final class LinkMenuTests: BrowserTestCase {
    /// A data: address for a page titled `title`, written to sit inside another data: page as a
    /// link. The app escapes the outer address's `%` once more as it loads it (from a launch
    /// argument or the search field), so `%3C` here is `%3C` in the link and `<` in its page.
    private static func linkedPage(_ title: String) -> String {
        "data:text/html,%3Ctitle%3E\(title)%3C/title%3E%3Ch1%3E\(title)%3C/h1%3E"
    }

    /// A page titled First with a big link to a page titled `title`.
    private static func pageLinking(to title: String) -> String {
        "data:text/html,<meta name=viewport content=width=device-width><title>First</title>"
            + "<h1 style=font-family:-apple-system;padding:24px>First</h1>"
            + "<a href=\(linkedPage(title)) style=font-size:48px;padding:24px>Read later</a>"
    }

    // promise: #670
    func testShareFromALinksMenu() {
        launch(["-CraOpenURL", Self.pageLinking(to: "Later"), "-CraSearch", "NO"])
        waitForPage("First")
        let link = app.webViews.links["Read later"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let share = app.buttons["Share..."]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            let activity = app.otherElements["ActivityListView"]
            XCTAssertTrue(activity.waitForExistence(timeout: 5))
            let source = link.frame
            let popover = activity.frame
            // Accessibility rounds the link frame outwards; the popover frame includes its arrow.
            XCTAssertFalse(popover.intersects(source.insetBy(dx: 2, dy: 2)), "the share popover \(popover) must not cover the pressed link \(source)")
        }
        closeShareSheet(openedFrom: link)
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-share"].waitForExistence(timeout: 5))
    }

    // promise: #713
    /// Save to Photos in a long-pressed image's menu (WebKit's own) asks for the photo library instead of ending
    /// the app: iOS ends an app that reaches the library without NSPhotoLibraryAddUsageDescription.
    func testSaveToPhotosFromAnImageKeepsTheAppRunning() {
        // A 300 px picture from the local fixture server (WebKit offers no image menu for a 1 px one blown up).
        let base = ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765"
        let page = base + "/picture"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Picture")
        let image = app.webViews.images["Square"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        // The photo library's question comes from SpringBoard; allowing it lets the save finish.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        image.press(forDuration: 1.5)
        let save = app.buttons["Save to Photos"]
        let offered = save.waitForExistence(timeout: 5)
        keep("image-menu")
        XCTAssertTrue(offered, "the image menu offers Save to Photos: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        save.tap()
        for title in ["Allow Access to All Photos", "Allow", "OK"] {
            let allow = springboard.buttons[title]
            if allow.waitForExistence(timeout: 3) { allow.tap(); break }
        }
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "Save to Photos must not end the app")
        XCTAssertTrue(app.webViews.staticTexts["Picture"].exists, "the page is still on screen")
    }

    /// The search sheet's eyes on, then a private page typed in with a link to `title`.
    private func openPrivatePage(linkingTo title: String) {
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["search-incognito"].tap()
        XCTAssertTrue(app.staticTexts["incognito-note"].waitForExistence(timeout: 3))
        field.typeText("data:text/html,<title>Secret</title><h1><a/href=\(Self.linkedPage(title))>Secret</a></h1>\n")
    }

    // promise: #572
    /// Arc Search's link menu: "Open in Background Tab" puts the link's page in the tab row and
    /// leaves the page on screen.
    func testALinkOpensInABackgroundTab() {
        launch(["-CraOpenURL", Self.pageLinking(to: "Later"), "-CraSearch", "NO"])
        waitForPage("First")
        let link = app.webViews.links["Read later"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let background = app.buttons["Open in Background Tab"]
        XCTAssertTrue(background.waitForExistence(timeout: 5), "the link menu offers Open in Background Tab")
        XCTAssertTrue(app.buttons["Open in New Tab"].exists)
        XCTAssertTrue(app.buttons["Open in Incognito"].exists)
        keep("link-menu")
        background.tap()
        XCTAssertFalse(background.waitForExistence(timeout: 2))
        XCTAssertTrue(app.webViews.staticTexts["First"].exists, "the page stays on screen")
        sleep(2)
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the background tab is in the row")
        XCTAssertEqual(card.label, "Later")
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        sleep(1)
        keep("tab-row-with-background-tab")
    }

    // promise: #572
    /// "Open in Incognito" opens the link in a new private tab and shows it; it stays out of the row.
    func testALinkOpensInIncognito() {
        launch(["-CraOpenURL", Self.pageLinking(to: "Private"), "-CraSearch", "NO"])
        waitForPage("First")
        let link = app.webViews.links["Read later"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let incognito = app.buttons["Open in Incognito"]
        XCTAssertTrue(incognito.waitForExistence(timeout: 5), "the link menu offers Open in Incognito")
        incognito.tap()
        waitForPage("Private")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "the link's tab is incognito")
    }

    // promise: #572
    /// A private tab is the eyes in the search field away (Arc Search's incognito toggle), and a
    /// link on it opens privately too: no "Open in Incognito" (it is already), and its new tab
    /// stays out of the row.
    func testAPrivateTabsLinksStayPrivate() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openPrivatePage(linkingTo: "Hidden")
        let link = app.webViews.links["Secret"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let newTab = app.buttons["Open in New Tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open in Background Tab"].exists)
        XCTAssertFalse(app.buttons["Open in Incognito"].exists, "the page is incognito already")
        keep("incognito-link-menu")
        newTab.tap()
        waitForPage("Hidden")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "the link's tab is incognito too")
    }

    // promise: #572
    /// From a private page, "Open in Background Tab" makes a private tab that waits, unseen, as a
    /// card in the tab row while the private page is on screen; a tap opens it.
    func testAPrivateBackgroundTabWaitsInTheRow() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openPrivatePage(linkingTo: "Waiting")
        let link = app.webViews.links["Secret"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let background = app.buttons["Open in Background Tab"]
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        background.tap()
        XCTAssertFalse(background.waitForExistence(timeout: 2))
        XCTAssertTrue(app.webViews.links["Secret"].exists, "the private page stays on screen")
        sleep(2)
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the private background tab waits in the row")
        XCTAssertEqual(card.label, "Waiting")
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        sleep(1)
        keep("tab-row-with-private-background-tab")
        card.tap()
        waitForPage("Waiting")
    }

    // promise: #572
    /// The address in the page menu opens the search sheet with the page's address, selected:
    /// what is typed over it loads in the same tab. (+ still opens a new tab: SearchTests.)
    func testTheMenusAddressIsEditedInThisTab() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-menu"].tap()
        let host = app.staticTexts["menu-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("data:text/html,") && value.contains("First"), "the page's address is in the field: \(value)")
        sleep(1)
        keep("address-editing")
        // Selected, so what is typed replaces it.
        field.typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "Second")
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "it loaded in the same tab")
    }
}
