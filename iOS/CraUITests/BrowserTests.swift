import XCTest
import UIKit

/// The app driven by real taps in the simulator. Pages are `data:` addresses, so nothing here
/// needs the network. `scripts/ios.sh test` runs these and saves the screenshots they attach.
class BrowserTestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Launches on an empty data folder.
    func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-CraDataDir", "fresh"] + arguments
        app.launch()
    }

    /// A page with `title` as its heading. No spaces in the address (typed text with a space is
    /// a search, not an address), so attributes are separated with slashes.
    static func page(_ title: String, color: String = "white") -> String {
        "data:text/html,<meta/name=viewport/content=width=device-width><title>\(title)</title>"
            + "<body/bgcolor=\(color)><h1/style=font-family:-apple-system;padding:24px>\(title)</h1>"
    }

    func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func waitForPage(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.webViews.staticTexts[title].waitForExistence(timeout: 20), "page \(title) never showed", file: file, line: line)
    }

    func closeShareSheet(openedFrom button: XCUIElement) {
        let activity = app.otherElements["ActivityListView"]
        let navigation = app.navigationBars["UIActivityContentView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5) || navigation.waitForExistence(timeout: 2),
                      "the share sheet opens")
        if UIDevice.current.userInterfaceIdiom == .pad {
            let popover = activity.exists ? activity : navigation
            XCTAssertTrue(popover.frame.insetBy(dx: -40, dy: -40).intersects(button.frame),
                          "the share popover is attached to its source button")
            let outside = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: app.frame.midX, dy: app.frame.maxY - 20))
            XCTAssertFalse(popover.frame.contains(CGPoint(x: app.frame.midX, y: app.frame.maxY - 20)))
            outside.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 5))
    }

    /// The bottom bar is back on screen once the keyboard is gone (GitHub #505: a keyboard that
    /// faded out was still counted, so the bar stayed below the screen).
    func waitForBarOnScreen(file: StaticString = #filePath, line: UInt = #line) {
        let pill = app.buttons["bar-search"]
        let onScreen = NSPredicate { _, _ in pill.exists && pill.frame.maxY <= self.app.frame.maxY && pill.isHittable }
        let found = expectation(for: onScreen, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: 5), .completed, "the bar stayed off screen", file: file, line: line)
    }
}

final class SearchTests: BrowserTestCase {
    /// Arc Search comes up ready to type: the search field has the keyboard on a first launch.
    func testLaunchesReadyToType() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(field.placeholderValue, "Search...")
        keep("launch")
    }

    // promise: #505
    /// Typing shows the typed text as the first row, and Go opens it in a new tab.
    func testTypingAnAddressAndGoOpensThePage() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("example")
        XCTAssertTrue(app.staticTexts["example"].waitForExistence(timeout: 5))
        keep("typed")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        field.typeText(Self.page("First") + "\n")
        waitForPage("First")
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        waitForBarOnScreen()
        keep("page")
    }

    // promise: #505
    /// The pill opens search over a page, and a tap above the sheet puts it away again.
    func testThePillOpensSearchAndATapAboveClosesIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        keep("search-over-page")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        waitForBarOnScreen()
    }
}

final class TabSwitcherTests: BrowserTestCase {
    private func openTwoTabs() {
        launch(["-CraOpenURL", Self.page("First", color: "%23ffe9d6"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.page("Second", color: "%23d6ecff") + "\n")
        waitForPage("Second")
    }

    /// The tab stack opens the row of cards, newest in focus; a tap on the older card opens it.
    func testTheRowShowsEveryTabAndATapOpensOne() {
        openTwoTabs()
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bar-spaces"].exists)
        XCTAssertTrue(app.buttons["bar-settings"].exists)
        sleep(1)
        keep("tab-row")
        // The older card is tucked behind the newest: only its left edge can be tapped.
        app.buttons["tab-card-0"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        waitForPage("First")
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
    }

    /// Throwing a card upwards closes its tab; the last one gone leaves the search sheet.
    func testThrowingACardUpClosesItsTab() {
        openTwoTabs()
        app.buttons["bar-tabs"].tap()
        let newest = app.buttons["tab-card-1"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        sleep(1)
        newest.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-card-1"].waitForExistence(timeout: 2))
        keep("tab-row-after-close")
        app.buttons["tab-card-0"].swipeUp(velocity: .fast)
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }
}

/// The bottom bar's buttons tick under the finger as Arc Search's do (#675). The simulator plays no haptics, so with
/// `-CraCountHaptics YES` each button counts the ticks it played.
final class BarHapticsTests: BrowserTestCase {
    // promise: #675
    func testBarButtonsTickOnPressAndOnRelease() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraCountHaptics", "YES"])
        waitForPage("First")
        // The New Tab pill, which gave nothing before: one tick down, one up (read once the sheet has gone and
        // the pill is back on screen).
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        waitForBarOnScreen()
        XCTAssertEqual(app.buttons["bar-search"].value as? String, "ticks 2")
        // The menu button.
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-share"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["bar-menu"].value as? String, "ticks 2")
        // The tab stack, then Settings in the tab switcher.
        app.buttons["bar-tabs"].tap()
        let settings = app.buttons["bar-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertEqual(settings.value as? String, "ticks 2")
        // Back on the page by its card, where the tab stack shows again.
        app.buttons["tab-card-0"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["bar-tabs"].value as? String, "ticks 2")
    }
}

final class PageMenuTests: BrowserTestCase {
    // promise: #670
    func testShareFromThePageMenu() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        let menu = app.buttons["bar-menu"]
        menu.tap()
        app.buttons["menu-tile-share"].tap()
        closeShareSheet(openedFrom: menu)
        menu.tap()
        XCTAssertTrue(app.buttons["menu-tile-share"].waitForExistence(timeout: 5))
    }

    // promise: #670
    func testHoldingTheMenuSharesThePage() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        let menu = app.buttons["bar-menu"]
        menu.press(forDuration: 1.5)
        closeShareSheet(openedFrom: menu)
        menu.tap()
        XCTAssertTrue(app.buttons["menu-tile-share"].waitForExistence(timeout: 5))
    }

    /// The up arrow opens the menu on the page's site, with Arc Search's tiles and rows.
    func testTheMenuShowsThePageAndItsControls() {
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 10))
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.staticTexts["menu-host"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["menu-host"].label, "example.com")
        // Arc Search 1.49's menu (Victor's recording): four tiles, Display Options, Site Settings.
        for tile in ["findOnPage", "pin", "share"] { XCTAssertTrue(app.buttons["menu-tile-\(tile)"].exists, tile) }
        for row in ["displayOptions", "siteSettings"] { XCTAssertTrue(app.buttons["menu-row-\(row)"].exists, row) }
        XCTAssertTrue(app.buttons["menu-copy-link"].exists)
        XCTAssertFalse(app.buttons["menu-back"].isEnabled)
        sleep(1)
        keep("page-menu")
        // Display Options opens in place to its four rows.
        XCTAssertFalse(app.buttons["menu-row-translate"].isHittable)
        app.buttons["menu-row-displayOptions"].tap()
        for row in ["translate", "readerMode", "requestDesktopSite"] {
            XCTAssertTrue(app.buttons["menu-row-\(row)"].waitForExistence(timeout: 3), row)
        }
        sleep(1)
        keep("page-menu-options")
        // Zooming shows the percentage, and a tap on it goes back to the page's own size.
        app.buttons["menu-zoom-in"].tap()
        XCTAssertEqual(app.buttons["menu-zoom-value"].label, "110%")
        app.buttons["menu-zoom-value"].tap()
        XCTAssertFalse(app.buttons["menu-zoom-value"].exists)
        // A tap on the dimmed page puts the menu away.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertFalse(app.staticTexts["menu-host"].waitForExistence(timeout: 2))
    }

    /// Copy Link acts and puts the menu away. (That trackers are left out is CleanURL's test.)
    func testCopyLinkPutsTheMenuAway() {
        launch(["-CraOpenURL", Self.page("First") + "?utm_source=test", "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-copy-link"].waitForExistence(timeout: 5))
        app.buttons["menu-copy-link"].tap()
        XCTAssertFalse(app.staticTexts["menu-host"].waitForExistence(timeout: 2))
    }
}

final class SettingsTests: BrowserTestCase {
    // promise: #670
    func testShareCraFromSettings() {
        openSettingsShare("setting-share-cra")
    }

    // promise: #670
    func testExportDataFromSettings() {
        openSettingsShare("setting-export-data")
    }

    private func openSettingsShare(_ identifier: String) {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        let button = app.buttons[identifier]
        for _ in 0..<8 {
            if button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
        closeShareSheet(openedFrom: button)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["bar-settings"].waitForExistence(timeout: 5))
    }

    /// Site Settings opens from the page menu on the page's site, and a switch flipped there is
    /// still flipped when the sheet is opened again.
    func testSiteSettingsKeepsASitesChoice() {
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 10))
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-siteSettings"].tap()
        XCTAssertTrue(app.staticTexts["EXAMPLE.COM SETTINGS"].waitForExistence(timeout: 5))
        let ads = app.switches["setting-block-ads"]
        XCTAssertEqual(ads.value as? String, "1")
        sleep(1)
        keep("site-settings")
        ads.switches.firstMatch.tap()
        XCTAssertEqual(ads.value as? String, "0")
        app.buttons["Done"].tap()
        app.buttons["menu-row-siteSettings"].tap()
        XCTAssertTrue(app.switches["setting-block-ads"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["setting-block-ads"].value as? String, "0")
        // App Settings is one step further, with the global options behind their own row.
        XCTAssertTrue(app.buttons["setting-app-settings"].waitForExistence(timeout: 5))
        app.buttons["setting-app-settings"].tap()
        XCTAssertTrue(app.buttons["setting-global-site-settings"].waitForExistence(timeout: 5))
        sleep(1)
        keep("app-settings")
        app.buttons["setting-global-site-settings"].tap()
        XCTAssertTrue(app.switches["setting-block-ads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Default Site Settings"].exists)
        XCTAssertTrue(app.staticTexts["default-site-settings-caption"].exists)
        sleep(1)
        keep("default-site-settings")
        XCTAssertEqual(app.switches["setting-block-ads"].value as? String, "1", "the site's choice leaves the global one alone")
    }

    // promise: #674
    func testAppSettingsOpensTallOnIPadAndHalfOnIPhone() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        XCTAssertTrue(app.buttons["setting-global-site-settings"].waitForExistence(timeout: 5))
        sleep(1)
        keep("app-settings-open")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertLessThan(app.buttons["Done"].frame.minY, app.frame.height / 3,
                              "App Settings opened as a short card on iPad")
        } else {
            XCTAssertGreaterThan(app.buttons["Done"].frame.minY, app.frame.height * 0.4,
                                 "App Settings did not open at medium height on iPhone")
        }
    }

    /// The bottom of App Settings as in Arc Search 1.49: Sync, the share capsule, Contact the
    /// Team, Show Onboarding, Privacy Policy, Open Source Licenses (the block list's notices) and
    /// the version.
    func testOpenSourceLicensesShowTheBlockListsNotices() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        let licenses = app.buttons["setting-licenses"]
        XCTAssertTrue(app.buttons["setting-global-site-settings"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !licenses.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["setting-sync"].exists)
        XCTAssertTrue(app.buttons["setting-share-cra"].exists)
        XCTAssertTrue(app.buttons["setting-contact"].exists)
        sleep(1)
        keep("app-settings-bottom")
        licenses.tap()
        let notice = app.staticTexts["licenses-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("AdAway"), "the CC BY list is credited")
        XCTAssertTrue(notice.label.contains("Anudeep"), "the MIT list is credited")
    }

    /// A tab thrown out of the row is in the Archive, and a tap there brings it back.
    func testAnArchivedTabComesBackFromTheArchive() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["tab-card-1"].swipeUp(velocity: .fast)
        XCTAssertFalse(app.buttons["tab-card-1"].waitForExistence(timeout: 2))
        app.buttons["bar-settings"].tap()
        XCTAssertTrue(app.buttons["settings-archive"].waitForExistence(timeout: 5))
        app.buttons["settings-archive"].tap()
        let row = app.buttons["archive-row-Second"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TODAY"].exists)
        sleep(1)
        keep("archive")
        row.tap()
        waitForPage("Second")
    }
}

final class BlockingTests: BrowserTestCase {
    /// A page that loads Google Analytics' script and puts what became of it in its title. With
    /// the blockers on the script is stopped at once and the menu counts it; with Block Trackers
    /// off for the page the request is let through and nothing is counted. The tab's card is
    /// asked for the title: web content changed by script does not reach the test's view of the
    /// page.
    func testAListedScriptIsStoppedAndCountedUntilItsBlockerIsSwitchedOff() {
        let page = "data:text/html,<meta name=viewport content='width=device-width'><title>waiting</title><h1>Blocking</h1>"
            + "<script src='https://www.google-analytics.com/analytics.js' onload=\"document.title='script-loaded'\" onerror=\"document.title='script-stopped'\"></script>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Blocking")
        app.buttons["bar-menu"].tap()
        let footer = app.buttons["menu-reload-without-blockers"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.value as? String, "Cra scrubbed 1 tracker")
        keep("blocked-count")
        // The page has no site of its own, so its Site Settings are the global ones.
        app.buttons["menu-row-siteSettings"].tap()
        let trackers = app.switches["setting-block-trackers"]
        XCTAssertTrue(trackers.waitForExistence(timeout: 5))
        trackers.switches.firstMatch.tap()
        XCTAssertEqual(trackers.value as? String, "0")
        app.buttons["Done"].tap()
        app.buttons["menu-reload"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(6)
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.staticTexts["menu-host"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["menu-reload-without-blockers"].value as? String ?? "", "")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Let through, the request is the network's business: it loads, or is still on its way on
        // a slow or filtered network. Stopped by a rule it would have failed at once.
        XCTAssertNotEqual(card.label, "script-stopped")
    }

    // promise: #570
    /// Manga sites' pop-up ads (#570) load from Monetag's loader and zone scripts, on domains that
    /// change every few days. This page asks for both from domains no list has; Cra's filters stop
    /// them by their path, before any network, and the menu counts both. Without the filters the
    /// two requests go out, fail on hosts that don't exist, and nothing is counted.
    func testAnAdLoaderFromAnUnlistedDomainIsStoppedByItsPath() {
        let page = "data:text/html,<meta name=viewport content='width=device-width'><title>Manga</title><h1>Manga</h1>"
            + "<script src='https://cra-test-570-loader.com/btag.min.js'></script>"
            + "<script src='https://qwertyuiopcra.net/5/9357427/'></script>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Manga")
        app.buttons["bar-menu"].tap()
        let footer = app.buttons["menu-reload-without-blockers"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.value as? String, "Cra scrubbed 2 trackers")
        keep("ad-loader-blocked")
    }

    // promise: #570
    /// A list added under Block Lists applies its path rules, not only its domains (#570). The list,
    /// served by the local fixture server, has a path rule for a script on `cra.localhost`, which no
    /// list has, a hiding rule and a scriptlet Cra can't run. Its row says so; then a reload of the
    /// page stops the script (the tab's title says which of onload/onerror ran) and the menu counts it.
    /// Before #570 the list had no domains, so its fetch failed and the script loaded.
    func testAnAddedListsPathRuleStopsAScriptFromAnUnlistedDomain() throws {
        let base = ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765"
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("Cra-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        // Added as Add List would, but over http: the fixture server is plain http on the loopback,
        // which the app's fetch may reach and Add List refuses to type in.
        try #"{"hasSeenOnboarding": true, "hasSeenBlockTip": true, "customBlocklists": ["\#(base)/cra-570/list.txt"]}"#
            .write(to: data.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        // The page comes from the fixture server too: XCUITest drops the quotes its onerror needs.
        app.launchArguments = ["-CraDataDir", data.path, "-CraOpenURL", base + "/cra-570/page", "-CraSearch", "NO"]
        app.launch()
        waitForPage("Path rule")

        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        XCTAssertTrue(app.buttons["setting-global-site-settings"].waitForExistence(timeout: 5))
        app.buttons["setting-global-site-settings"].tap()
        XCTAssertTrue(app.buttons["setting-block-lists"].waitForExistence(timeout: 5))
        app.buttons["setting-block-lists"].tap()
        XCTAssertTrue(app.staticTexts["Cra test list 570"].waitForExistence(timeout: 30), "the list was fetched")
        let summary = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "2 rules · 1 rule Cra can’t use · ")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "the row says what the list applies")
        keep("added-list-full-rules")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        app.buttons["tab-card-0"].tap()
        waitForPage("Path rule")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-reload"].waitForExistence(timeout: 5))
        app.buttons["menu-reload"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(3)
        app.buttons["bar-menu"].tap()
        let footer = app.buttons["menu-reload-without-blockers"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.value as? String, "Cra scrubbed 1 tracker", "the added list's path rule is counted")
        keep("added-list-path-blocked")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "loader-stopped", "WebKit stopped the script")
    }

    // promise: #507
    /// An added list blocks from the first page after launch (#507): its kept copy in the data
    /// folder is compiled before that page loads, even when the list can't be fetched again
    /// (`.invalid` never resolves), and what it stops is counted in the menu like Cra's own list.
    /// The copy is named for its address (CraCore's keptCopiesInTestsMatchTheirAddresses). The image
    /// is from www.google.com, which Cra's own list leaves alone: let through, it loads and nothing is
    /// counted. (Its title isn't asked: script changes don't reach the tab card.) The copy holds
    /// 100,000 more domains, new each run, so it compiles afresh and well after Cra's own lists are
    /// looked up: a first page that didn't wait for it (MobileBlockerReadiness) would load the image.
    func testAKeptBlockListStopsItsDomainsFromTheFirstPage() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("Cra-\(UUID().uuidString)", isDirectory: true)
        let lists = data.appendingPathComponent("Blocklists", isDirectory: true)
        try FileManager.default.createDirectory(at: lists, withIntermediateDirectories: true)
        try #"{"hasSeenOnboarding": true, "hasSeenBlockTip": true, "customBlocklists": ["https://lists.invalid/kept.txt"]}"#
            .write(to: data.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let kept = """
        # Cra block list (added in Settings). One domain per line; a domain also blocks its subdomains.
        # url: https://lists.invalid/kept.txt
        # title: Kept list
        # fetched: 2026-01-01T00:00:00Z
        # skipped: 0
        www.google.com

        """
        let run = UUID().uuidString.prefix(8).lowercased()
        let filler = (0..<100_000).map { "ad\($0).run-\(run).example" }.joined(separator: "\n")
        try (kept + filler + "\n").write(to: lists.appendingPathComponent("dac256c30d0d3b6d.txt"), atomically: true, encoding: .utf8)

        let page = "data:text/html,<meta name=viewport content='width=device-width'><title>Kept list</title><h1>Kept list</h1>"
            + "<img src='https://www.google.com/favicon.ico?cra-test'>"
        app.launchArguments = ["-CraDataDir", data.path, "-CraOpenURL", page, "-CraSearch", "NO"]
        app.launch()
        waitForPage("Kept list")
        app.buttons["bar-menu"].tap()
        let footer = app.buttons["menu-reload-without-blockers"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.value as? String, "Cra scrubbed 1 tracker", "the added list's block is counted")
        keep("kept-list-blocked")
    }

    // promise: #507
    /// Default Site Settings ▸ Block Lists (#507): an http:// address is refused (the app can't
    /// load one), an https:// one becomes a row that says what became of its fetch, and a swipe
    /// removes it. `.invalid` never resolves, so the fetch fails without the network.
    func testAnAddedBlockListShowsItsFetchAndCanBeRemoved() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        XCTAssertTrue(app.buttons["setting-global-site-settings"].waitForExistence(timeout: 5))
        app.buttons["setting-global-site-settings"].tap()
        let lists = app.buttons["setting-block-lists"]
        XCTAssertTrue(lists.waitForExistence(timeout: 5))
        lists.tap()
        let add = app.buttons["block-lists-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))

        add.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("http://lists.invalid/hosts")
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.alerts["That isn’t a list address"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()

        add.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lists.invalid/abpindo.txt")
        app.alerts.buttons["Add"].tap()
        let row = app.descendants(matching: .any)["block-list-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lists.invalid"].exists)
        XCTAssertTrue(app.staticTexts["Couldn’t reach the list. Cra tries again later."].waitForExistence(timeout: 30))
        sleep(1)
        keep("block-lists")

        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["lists.invalid"].waitForExistence(timeout: 2))
    }

    /// Arc Search 1.49's tip (Victor's recording, 1:59): the first page that had something
    /// stopped says so over the bar, once; the × puts it away and it doesn't come back.
    func testTheFirstBlockedPageShowsTheTipOnce() {
        let page = "data:text/html,<meta name=viewport content='width=device-width'><title>Tracked</title><h1>Tracked</h1>"
            + "<script src='https://www.google-analytics.com/analytics.js'></script>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        // The tip itself says the page loaded (the page's own text reaches the test unreliably).
        let title = app.staticTexts["block-tip-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "Cra just blocked 1 tracker")
        sleep(1)
        keep("block-tip")
        app.buttons["block-tip-close"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
        app.buttons["bar-menu"].tap()
        app.buttons["menu-reload"].tap()
        sleep(4)
        XCTAssertFalse(app.staticTexts["block-tip-title"].exists, "the tip shows once")
    }

    /// Restoring the original page asks whether that fixed it (3:20); a thumbs-up turns the
    /// site's blockers off, kept in its Site Settings.
    func testRestoringThePageAsksWhetherItFixedIt() {
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 10))
        sleep(2)
        app.buttons["bar-menu"].tap()
        app.buttons["menu-reload-without-blockers"].tap()
        let yes = app.buttons["fix-yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["fix-question-label"].label, "Did it fix the issue?")
        sleep(1)
        keep("fix-question")
        yes.tap()
        XCTAssertEqual(app.staticTexts["fix-question-label"].label, "Blockers disabled for example.com")
        keep("blockers-disabled")
        sleep(3)
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-siteSettings"].tap()
        let trackers = app.switches["setting-block-trackers"]
        XCTAssertTrue(trackers.waitForExistence(timeout: 5))
        XCTAssertEqual(trackers.value as? String, "0")
        XCTAssertEqual(app.switches["setting-block-ads"].value as? String, "0")
    }
}

final class GestureTests: BrowserTestCase {
    private func drag(fromX: CGFloat, toX: CGFloat, y: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: y))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func openSecondTab() {
        openTab("Second")
    }

    private func openTab(_ title: String) {
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.page(title) + "\n")
        waitForPage(title)
    }

    /// A flick up that starts on the tab stack button.
    private func flickUpFromTheTabButton() {
        let start = app.buttons["bar-tabs"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
    }

    /// The title of the tab on screen: opens the tab row, reads the focused card (the selected
    /// tab) and goes back into it.
    private func shownTabTitle() -> String {
        app.buttons["bar-tabs"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-card-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        // The focused card is the one whose left edge is 83 pt in.
        let focused = cards.allElementsBoundByIndex.first { abs($0.frame.minX - 83) < 3 }
        let title = focused?.label ?? ""
        focused?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(1)
        return title
    }

    /// A swipe along the bottom bar goes to the neighbouring tab: right for the older one, left
    /// for the newer.
    func testSwipingTheBarMovesBetweenTabs() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openSecondTab()
        // Read from the page on screen: picking a card in the row would move it to the row's end (#647).
        drag(fromX: 0.3, toX: 0.9, y: 0.95)
        waitForPage("First")
        XCTAssertFalse(app.webViews.staticTexts["Second"].exists)
        drag(fromX: 0.8, toX: 0.2, y: 0.95)
        waitForPage("Second")
        XCTAssertFalse(app.webViews.staticTexts["First"].exists)
    }

    /// A swipe right across a tab's first page archives the tab and shows the one before it; the
    /// swipe back left reopens it.
    func testSwipingBackOnAFirstPageArchivesTheTabAndTheOppositeSwipeReopensIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openSecondTab()
        drag(fromX: 0.3, toX: 0.95, y: 0.5)
        sleep(1)
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "the swiped tab left the row")
        app.buttons["tab-card-0"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(1)
        drag(fromX: 0.8, toX: 0.1, y: 0.5)
        sleep(1)
        XCTAssertEqual(shownTabTitle(), "Second")
    }

    /// A drag up from the bottom bar opens the tab row, as the tab stack button does.
    func testDraggingUpFromTheBarOpensTheTabRow() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)), withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bar-spaces"].exists)
    }

    // promise: #537
    /// A flick up from the tab button goes to the tab looked at last, not the row's neighbour,
    /// and the next flick comes back (Arc Search's toggle).
    func testFlickingUpFromTheTabButtonTogglesTheTwoLatestTabs() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        openTab("Third")
        // A swipe along the bar to Second: the row's older neighbour is now First, but Third
        // was on screen last.
        drag(fromX: 0.3, toX: 0.9, y: 0.95)
        sleep(1)
        XCTAssertEqual(shownTabTitle(), "Second")
        flickUpFromTheTabButton()
        XCTAssertFalse(app.buttons["tab-card-0"].exists, "the flick switches tabs; it does not open the row")
        XCTAssertEqual(shownTabTitle(), "Third")
        flickUpFromTheTabButton()
        XCTAssertEqual(shownTabTitle(), "Second")
        keep("flicked back")
    }

    // promise: #537
    /// The flick works from beside the tab button too, towards the pill, leaning the way a
    /// thumb does: the reporter's follow-up found the row opening when it missed the button.
    func testFlickingUpBesideTheTabButtonStillSwitches() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        let button = app.buttons["bar-tabs"]
        // 40 pt right of the button's centre and a little lower: outside its 47 pt circle.
        let start = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 40, dy: 6))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.65)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        XCTAssertFalse(app.buttons["tab-card-0"].exists, "the flick switches tabs; it does not open the row")
        XCTAssertEqual(shownTabTitle(), "First")
        keep("flicked from beside the button")
    }

    // promise: #509
    /// With the bar scrolled away, a tap on the bottom edge brings it back: a swipe up there can
    /// open the app switcher instead.
    func testATapOnTheBottomEdgeBringsTheBarBack() {
        launch(["-CraOpenURL", Self.page("Tall") + "<div/style=height:5000px></div>", "-CraSearch", "NO"])
        waitForPage("Tall")
        let pill = app.buttons["bar-search"]
        XCTAssertTrue(pill.isHittable)
        app.webViews.firstMatch.swipeUp()
        let gone = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: pill)
        wait(for: [gone], timeout: 5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995)).tap()
        let back = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: pill)
        wait(for: [back], timeout: 5)
        keep("bar back")
    }

    /// Dragging the search sheet down puts it away when there is a page behind it.
    func testDraggingTheSearchSheetDownClosesIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }
}

final class CollapseBottomBarTests: BrowserTestCase {
    // promise: #505
    /// With Collapse Bottom Bar switched off (GitHub #505) scrolling down leaves the bar where it
    /// is. First a swipe puts it away with the switch on, so the swipe is known to scroll.
    func testWithCollapseBottomBarOffScrollingKeepsTheBar() {
        launch(["-CraOpenURL", Self.page("Tall") + "<div/style=height:20000px></div>", "-CraSearch", "NO"])
        waitForPage("Tall")
        let pill = app.buttons["bar-search"]
        XCTAssertTrue(pill.isHittable)
        app.webViews.firstMatch.swipeUp()
        let gone = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: pill)
        wait(for: [gone], timeout: 5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995)).tap()
        waitForBarOnScreen()

        // A data: page has no site, so its Site Settings are the global ones.
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-siteSettings"].tap()
        let collapse = app.switches["setting-collapse-bottom-bar"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        XCTAssertEqual(collapse.value as? String, "1")
        collapse.switches.firstMatch.tap()
        XCTAssertEqual(collapse.value as? String, "0")
        app.buttons["Done"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertFalse(app.staticTexts["menu-host"].waitForExistence(timeout: 2))

        for _ in 0..<3 {
            app.webViews.firstMatch.swipeUp()
            sleep(1)
            XCTAssertTrue(pill.isHittable, "the bar collapsed with Collapse Bottom Bar off")
        }
        waitForBarOnScreen()
        keep("collapse-off")
    }
}

final class ReadingTests: BrowserTestCase {
    static let article: String = {
        let paragraphs = [
            "Pizza is a dish of Italian origin made of a flattened base of leavened dough topped with tomato and cheese.",
            "The dough rests for a day so that it stretches without tearing and bakes with large bubbles at its edge.",
            "A wood fired oven reaches four hundred degrees and bakes a pizza in about ninety seconds.",
            "Naples protects the recipe of its pizza with rules about flour, tomatoes and the size of the base.",
        ]
        let body = paragraphs.map { "<p>\($0)</p>" }.joined()
        return "data:text/html,<meta name=viewport content='width=device-width'><title>About Pizza</title>"
            + "<nav>Menu Home Shop</nav><article><h1>About Pizza</h1>\(body)</article><footer>Copyright</footer>"
    }()

    // promise: #670
    /// The Summarize tile shrinks the page into its card and shows the summary with its credit;
    /// the close button brings the page back.
    func testSummarizeShowsTheSummaryAndClosesBackToThePage() {
        launch(["-CraOpenURL", Self.article, "-CraSearch", "NO", "-CraFakeModel", "YES"])
        waitForPage("About Pizza")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-summarize"].waitForExistence(timeout: 5))
        app.buttons["menu-tile-summarize"].tap()
        let overview = app.staticTexts["summary-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        // The canned model answers with the article's own opening lines: its heading, then its sentences.
        XCTAssertEqual(overview.label, "About Pizza.")
        XCTAssertTrue(app.staticTexts["Summarized for you by Cra"].exists)
        XCTAssertTrue(app.staticTexts["Point 1"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Pizza is a dish of Italian origin'")).firstMatch.exists)
        // Copy and Share once it is written.
        XCTAssertTrue(app.buttons["summary-copy"].exists)
        app.buttons["summary-share"].tap()
        closeShareSheet(openedFrom: app.buttons["summary-share"])
        keep("summary")
        app.buttons["summary-close"].tap()
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["summary-overview"].waitForExistence(timeout: 1))
    }

    /// Reader shows the article without the page's navigation and footer, and the tile closes it again.
    func testReaderShowsTheArticleAlone() {
        launch(["-CraOpenURL", Self.article, "-CraSearch", "NO"])
        waitForPage("About Pizza")
        XCTAssertTrue(app.webViews.staticTexts["Copyright"].exists)
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-displayOptions"].tap()
        XCTAssertTrue(app.buttons["menu-row-readerMode"].waitForExistence(timeout: 3))
        app.buttons["menu-row-readerMode"].tap()
        let reader = app.webViews["reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(reader.staticTexts["About Pizza"].waitForExistence(timeout: 5))
        XCTAssertFalse(reader.staticTexts["Copyright"].exists)
        XCTAssertFalse(reader.staticTexts["Menu Home Shop"].exists)
        sleep(1)
        keep("reader")
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-displayOptions"].tap()
        XCTAssertTrue(app.buttons["menu-row-readerMode"].waitForExistence(timeout: 3))
        app.buttons["menu-row-readerMode"].tap()
        XCTAssertFalse(app.webViews["reader"].waitForExistence(timeout: 2))
    }
}

final class BrowseForMeTests: BrowserTestCase {
    /// "Browse for Me" on a suggestion shows the sites being read, then the page made from them,
    /// in a tab of its own.
    func testBrowseForMeReadsSitesAndMakesAPage() {
        launch(["-CraFakeModel", "YES"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("pizza ovens")
        let chip = app.buttons["browse-for-me"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.staticTexts["browse-reading"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["browse-reading"].label, "Reading 3 web pages")
        XCTAssertEqual(app.staticTexts["browse-query"].label, "pizza ovens")
        XCTAssertTrue(app.staticTexts["alpha.example"].exists)
        keep("browse-loading")
        XCTAssertTrue(app.webViews.staticTexts["About pizza ovens"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.staticTexts["Read 3 web pages"].exists)
        sleep(1)
        keep("browse-page")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "About pizza ovens")
    }
}

final class BrowseFollowUpTests: BrowserTestCase {
    /// A follow-up chip at the end of a Browse for Me page asks it in a new Browse for Me.
    func testAFollowUpChipBrowsesForItsQuestion() {
        launch(["-CraFakeModel", "YES"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("pizza ovens")
        let chip = app.buttons["browse-for-me"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.webViews.staticTexts["About pizza ovens"].waitForExistence(timeout: 15))
        let followUp = app.webViews.links["best pizza ovens"]
        for _ in 0..<4 where !followUp.isHittable { app.webViews.firstMatch.swipeUp() }
        XCTAssertTrue(followUp.waitForExistence(timeout: 5), "the follow-up is offered")
        XCTAssertTrue(app.webViews.staticTexts["Sources"].exists)
        keep("browse-follow-ups")
        followUp.tap()
        XCTAssertTrue(app.staticTexts["browse-query"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["browse-query"].label, "best pizza ovens")
    }
}

final class BrowseQueryEditTests: BrowserTestCase {
    /// The question at the top of a Browse for Me page opens the search sheet with it, to change.
    func testTheQuestionCapsuleOpensItForEditing() {
        launch(["-CraFakeModel", "YES", "-CraFakeSuggestions", "YES"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("pizza ovens")
        app.buttons["browse-for-me"].firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["About pizza ovens"].waitForExistence(timeout: 15))
        sleep(1) // the page slides up into place as the loading screen fades
        app.webViews.links["pizza ovens"].firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "pizza ovens", "the question is ready to change")
        XCTAssertTrue(app.descendants(matching: .any)["suggestion-1"].waitForExistence(timeout: 5), "with its suggestions")
    }
}

final class StarterQuestionsTests: BrowserTestCase {
    /// Someone new sees Arc Search's sample questions under the empty field until a first search.
    func testStarterQuestionsShowUntilTheFirstSearch() {
        launch(["-CraFakeModel", "YES"])
        let starter = app.staticTexts["how do i make my boss like me"]
        XCTAssertTrue(starter.waitForExistence(timeout: 10), "the starter questions are there")
        // Arc Search 1.49's coach mark points at the first question's Browse for Me.
        XCTAssertTrue(app.staticTexts["coach-mark"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["coach-mark"].label, "Tap Browse for Me for a faster answer")
        sleep(1)
        keep("starter-questions")
        app.buttons["browse-for-me"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["browse-query"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["browse-query"].label, "how do i make my boss like me")
        XCTAssertFalse(app.staticTexts["coach-mark"].exists, "the coach mark goes with the sheet")
        XCTAssertTrue(app.webViews.staticTexts["About how do i make my boss like me"].waitForExistence(timeout: 15))
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        // The page behind shows the question too: look at the sheet's first row.
        XCTAssertFalse(app.descendants(matching: .any)["suggestion-0"].waitForExistence(timeout: 2), "gone after the first search")
    }
}

final class IncognitoTests: BrowserTestCase {
    /// The mask in the search field turns the sheet incognito; a page opened then stays out of
    /// the tab row and out of the Archive, and is gone once it is left.
    func testAnIncognitoTabStaysOutOfTheRowAndTheArchive() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["incognito-note"].exists)
        app.buttons["search-incognito"].tap()
        XCTAssertTrue(app.staticTexts["incognito-note"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["incognito-note"].label, "You're browsing Incognito")
        XCTAssertEqual(app.buttons["search-incognito"].value as? String, "On")
        sleep(1)
        keep("incognito")
        field.typeText(Self.page("Secret") + "\n")
        waitForPage("Secret")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        XCTAssertFalse(app.buttons["tab-card-1"].exists)
        app.buttons["bar-settings"].tap()
        app.buttons["settings-archive"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["archive-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["archive-row-Secret"].exists)
        keep("archive-empty")
    }
}

final class SpacesTests: BrowserTestCase {
    /// The tab row's left button shows the Mac's Spaces: the pinned tabs and folders of each,
    /// folders shut until a tap opens them (Arc Search), and a tap on a tab that opens it here.
    func testTheMacsSpacesOpenFromTheTabRow() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", "demo"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-spaces"].waitForExistence(timeout: 5))
        app.buttons["bar-spaces"].tap()
        // The first time the Spaces arrive, Arc Search asks about its share extension.
        let noThanks = app.buttons["share-prompt-no-thanks"]
        XCTAssertTrue(noThanks.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["spaces-close"].exists, "the prompt has no close button")
        noThanks.tap()
        XCTAssertTrue(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["space-title"].firstMatch.label, "Personal")
        XCTAssertFalse(app.buttons["space-tab-Docs"].exists, "a folder starts shut")
        XCTAssertTrue(app.buttons["space-tab-A Story"].exists)
        app.buttons["space-folder-Work"].tap()
        XCTAssertTrue(app.buttons["space-tab-Docs"].waitForExistence(timeout: 2))
        sleep(1)
        keep("spaces")
        app.buttons["space-folder-Work"].tap()
        XCTAssertFalse(app.buttons["space-tab-Docs"].waitForExistence(timeout: 1))
        app.buttons["space-icon-Play"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Play'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["space-icon-Personal"].tap()
        app.buttons["space-tab-Inbox"].tap()
        waitForPage("Inbox")
    }

    // promise: #670
    /// "Set up" on the share prompt opens the how-to sheet; closed, the Spaces are there and the
    /// prompt doesn't come back.
    func testTheSharePromptLeadsToTheHowTo() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", "demo"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-spaces"].waitForExistence(timeout: 5))
        app.buttons["bar-spaces"].tap()
        let setUp = app.buttons["share-prompt-set-up"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 5))
        setUp.tap()
        XCTAssertTrue(app.staticTexts["share-guide-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["share-guide-title"].label, "Save to Cra from any app")
        let share = app.buttons["share-guide-show"]
        XCTAssertTrue(share.exists)
        share.tap()
        closeShareSheet(openedFrom: share)
        app.buttons["share-guide-close"].tap()
        XCTAssertTrue(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 5))
        app.buttons["spaces-close"].tap()
        XCTAssertFalse(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 2))
        app.buttons["bar-spaces"].tap()
        XCTAssertTrue(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["share-prompt-set-up"].exists, "the prompt asks once")
    }

    // promise: #556
    /// The sheet reads the Mac's sidebar every time it opens, here taking 3 s. The first opening
    /// shows "Connecting" for it; a reopened sheet shows the Spaces it read at once (it showed the
    /// bright "Connecting" again on every reopen).
    func testAReopenedSpacesSheetShowsItsSpacesAtOnce() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", "demo", "-CraSyncDelay", "3"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-spaces"].waitForExistence(timeout: 5))
        app.buttons["bar-spaces"].tap()
        XCTAssertTrue(app.staticTexts["spaces-connecting"].waitForExistence(timeout: 2), "the first read is still on its way")
        let noThanks = app.buttons["share-prompt-no-thanks"]
        XCTAssertTrue(noThanks.waitForExistence(timeout: 10))
        noThanks.tap()
        XCTAssertTrue(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 5))
        app.buttons["spaces-close"].tap()
        XCTAssertFalse(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 2))
        app.buttons["bar-spaces"].tap()
        XCTAssertTrue(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 1.5), "reopened, the Spaces show while they are read again")
        XCTAssertFalse(app.staticTexts["spaces-connecting"].exists)
        keep("spaces-reopened")
    }

    // promise: #556
    /// The tab row reads the Mac's Spaces as it comes up, so even the first opening shows them at
    /// once when that read is back.
    func testTheFirstSpacesOpeningAfterTheTabRowIsInstant() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", "demo", "-CraSyncDelay", "3"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-spaces"].waitForExistence(timeout: 5))
        sleep(5)
        app.buttons["bar-spaces"].tap()
        XCTAssertTrue(app.buttons["share-prompt-no-thanks"].waitForExistence(timeout: 1.5), "the read ahead's Spaces show at once")
        XCTAssertFalse(app.staticTexts["spaces-connecting"].exists)
    }

    // promise: #465
    /// A sidebar.json as the Mac writes it into the sync folder shows its Spaces: dates as ISO 8601
    /// text (build 616 read them as numbers and showed "Sync with Cra for Mac"), and an item kind
    /// this build doesn't know (here an easel, from a newer Mac) leaves out only that item.
    /// `-CraSyncDir demo` builds its Spaces in memory, so it never reads a file.
    func testTheMacsSyncedFileShowsItsSpaces() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(Self.macSidebar.utf8).write(to: folder.appendingPathComponent("sidebar.json"))
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", folder.path])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-spaces"].waitForExistence(timeout: 5))
        app.buttons["bar-spaces"].tap()
        let noThanks = app.buttons["share-prompt-no-thanks"]
        XCTAssertTrue(noThanks.waitForExistence(timeout: 5), "the Mac's file read as nothing synced")
        noThanks.tap()
        XCTAssertTrue(app.buttons["space-tab-Inbox"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["space-title"].firstMatch.label, "Work")
        XCTAssertTrue(app.buttons["space-folder-Projects"].exists)
        XCTAssertTrue(app.buttons["space-tab-Story"].exists)
        XCTAssertFalse(app.buttons["space-tab-Sketch"].exists, "the unknown easel and its tab are left out")
        keep("synced-file")
        app.buttons["space-tab-Inbox"].tap()
        waitForPage("Inbox")
    }

    /// The Mac's sidebar.json, cut down: one Space with a pinned tab, a folder, an easel (an item
    /// kind newer than this build) and a Today tab, dates written the Mac's way.
    static let macSidebar = #"""
    {
      "version": 3,
      "spaceOrder": ["00000000-0000-0000-0000-00000000000A"],
      "spaces": [
        {"id": "00000000-0000-0000-0000-00000000000A", "title": "Work", "emoji": "", "symbol": "briefcase",
         "createdAt": "2026-11-17T09:00:00Z",
         "theme": {"colors": ["#A687C8", "#3A3660"], "intensity": 0.8, "noise": 0.1, "appearance": "auto"},
         "favoritesContainerID": "00000000-0000-0000-0000-0000000000F1",
         "pinnedContainerID": "00000000-0000-0000-0000-0000000000F2",
         "todayContainerID": "00000000-0000-0000-0000-0000000000F3"}
      ],
      "items": [
        {"id": "00000000-0000-0000-0000-0000000000F1", "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"container": {"_0": {"favorites": {"spaceID": "00000000-0000-0000-0000-00000000000A"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000F2", "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "children": ["00000000-0000-0000-0000-0000000000B1", "00000000-0000-0000-0000-0000000000B2", "00000000-0000-0000-0000-0000000000E1"],
         "data": {"container": {"_0": {"pinned": {"spaceID": "00000000-0000-0000-0000-00000000000A"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000F3", "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "children": ["00000000-0000-0000-0000-0000000000D1"],
         "data": {"container": {"_0": {"today": {"spaceID": "00000000-0000-0000-0000-00000000000A"}}}}},
        {"id": "00000000-0000-0000-0000-0000000000B1", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Inbox",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z", "pinnedAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "data:text/html,<title>Inbox</title><h1>Inbox</h1>",
                  "savedURL": "data:text/html,<title>Inbox</title><h1>Inbox</h1>", "savedTitle": "Inbox", "muted": false,
                  "timeLastActiveAt": "2026-11-17T10:00:00Z"}}}},
        {"id": "00000000-0000-0000-0000-0000000000B2", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Projects",
         "children": ["00000000-0000-0000-0000-0000000000B3"], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"folder": {}}},
        {"id": "00000000-0000-0000-0000-0000000000B3", "parentID": "00000000-0000-0000-0000-0000000000B2",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://docs.example", "savedURL": "https://docs.example", "savedTitle": "Docs", "muted": false}}}},
        {"id": "00000000-0000-0000-0000-0000000000E1", "parentID": "00000000-0000-0000-0000-0000000000F2", "title": "Sketches",
         "children": ["00000000-0000-0000-0000-0000000000E3"], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"easel": {"_0": {"canvasID": "00000000-0000-0000-0000-0000000000E9"}}}},
        {"id": "00000000-0000-0000-0000-0000000000E3", "parentID": "00000000-0000-0000-0000-0000000000E1",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://sketch.example", "savedURL": "https://sketch.example", "savedTitle": "Sketch", "muted": false}}}},
        {"id": "00000000-0000-0000-0000-0000000000D1", "parentID": "00000000-0000-0000-0000-0000000000F3",
         "children": [], "isUnread": false, "createdAt": "2026-11-17T09:00:00Z",
         "data": {"tab": {"_0": {"url": "https://news.example/story", "savedURL": "https://news.example/story", "savedTitle": "Story", "muted": false}}}}
      ]
    }
    """#

    /// Without iCloud the Spaces view says where Spaces come from.
    func testWithoutSyncTheSpacesViewExplains() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        // Arc Search's "Every tab, anywhere." card points at the Spaces button and opens the sheet.
        let card = app.buttons["sync-card-open"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        sleep(1)
        keep("sync-card")
        card.tap()
        XCTAssertTrue(app.staticTexts["sync-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["sync-title"].label, "Sync with Cra for Mac")
        sleep(1)
        keep("sync-intro")
        app.buttons["sync-have-mac"].tap()
        XCTAssertTrue(app.staticTexts["sync-detail-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["sync-detail-title"].label, "Turn on Sync on your Mac")
        app.buttons["sync-go-back"].tap()
        app.buttons["sync-no-mac"].tap()
        XCTAssertTrue(app.staticTexts["Get Cra on your computer first"].waitForExistence(timeout: 3))
        keep("sync-no-mac")
        app.buttons["spaces-close"].tap()
        // Closed, the card stays away.
        let close = app.buttons["sync-card-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertFalse(card.waitForExistence(timeout: 1))
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-spaces"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertFalse(card.exists, "a closed card doesn't come back")
    }
}

final class FavoritesTests: BrowserTestCase {
    /// The page menu's Pin tile ("Favorite in App" on the phone) puts the page under the empty search field,
    /// where a tap opens it.
    func testAFavoriteShowsUnderTheEmptySearchField() {
        // A title that is nowhere in the page, so finding it means finding the favorite's row.
        launch(["-CraOpenURL", "data:text/html,<meta name=viewport content='width=device-width'><title>Starred</title><h1>Heading</h1>", "-CraSearch", "NO"])
        waitForPage("Heading")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-pin"].waitForExistence(timeout: 5))
        app.buttons["menu-tile-pin"].tap()
        XCTAssertEqual(app.buttons["menu-tile-pin"].label, "Pinned")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Starred"].waitForExistence(timeout: 3), "the favorite is listed under the empty field")
        sleep(1)
        keep("favorites")
        app.textFields["search-field"].typeText("x")
        XCTAssertFalse(app.staticTexts["Starred"].waitForExistence(timeout: 1), "typing replaces the favorites with suggestions")
    }
}

final class VoiceSearchTests: BrowserTestCase {
    /// Holding the pill listens (here to a canned phrase), shows the words, and searches for
    /// them when the pill is let go.
    func testHoldingThePillSearchesForWhatWasSaid() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraFakeVoice", Self.page("Spoken")])
        waitForPage("First")
        app.buttons["bar-search"].press(forDuration: 3)
        waitForPage("Spoken")
        XCTAssertFalse(app.otherElements["voice-overlay"].exists)
    }
}

final class VoiceFromFieldTests: BrowserTestCase {
    /// The mic in the empty search field starts voice search; a tap ends it and searches.
    func testTheMicInTheFieldSearchesForWhatWasSaid() {
        launch(["-CraFakeVoice", Self.page("Spoken")])
        let mic = app.buttons["search-voice"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        mic.tap()
        let overlay = app.otherElements["voice-overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        sleep(2)
        overlay.tap()
        waitForPage("Spoken")
    }
}

final class OnboardingTests: BrowserTestCase {
    /// First launch walks through Arc Search's steps; the blocking switch decides the global
    /// blockers, and afterwards the app is ready to type.
    func testOnboardingWalksThroughAndLeavesTheAppReadyToType() {
        launch(["-CraOnboarding", "YES", "-CraFakeModel", "YES"])
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Get what you want twice as fast."].exists)
        keep("onboarding-welcome")
        next.tap()
        XCTAssertTrue(app.staticTexts["Meet your new favorite browser"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No more virtual dust bunnies"].exists)
        sleep(1)
        keep("onboarding-meet")
        next.tap()
        // The device can answer (the canned model), so Browse for Me gets its step: tried on a
        // phone first ("Try it!"), and Next comes once it has run.
        XCTAssertTrue(app.staticTexts["Let Cra search and summarize for you"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["things to do in paris"].exists)
        XCTAssertFalse(next.isHittable, "Next waits for the try")
        sleep(1)
        keep("onboarding-browse")
        app.buttons["onboarding-try"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-check"].waitForExistence(timeout: 5))
        sleep(1)
        keep("onboarding-browse-done")
        next.tap()
        XCTAssertTrue(app.staticTexts["onboarding-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["onboarding-title"].label, "Pinch to summarize any web page")
        sleep(1)
        keep("onboarding-pinch")
        app.descendants(matching: .any)["onboarding-pinch-page"].pinch(withScale: 0.5, velocity: -1)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-check"].waitForExistence(timeout: 5), "a pinch summarizes the page")
        sleep(1)
        keep("onboarding-pinch-done")
        next.tap()
        XCTAssertTrue(app.staticTexts["Pick an icon for your home screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["icon-violet"].exists)
        sleep(1)
        keep("onboarding-icon")
        next.tap()
        XCTAssertTrue(app.staticTexts["Get what you need, without the noise"].waitForExistence(timeout: 3))
        XCTAssertEqual(next.label, "Let\u{2019}s go")
        app.switches["onboarding-blocking"].switches.firstMatch.tap()
        sleep(1)
        keep("onboarding-blocking")
        next.tap()
        // "Never see another ad.", then the inset sheet with the way to the default browser.
        XCTAssertTrue(app.buttons["onboarding-skip"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["onboarding-title"].label, "Never see another ad.")
        sleep(1)
        keep("onboarding-default")
        next.tap()
        XCTAssertTrue(app.staticTexts["onboarding-howto"].waitForExistence(timeout: 3))
        sleep(1)
        keep("onboarding-howto")
        app.buttons["onboarding-later"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        keep("onboarding-after")
    }
}

final class PageBasicsTests: BrowserTestCase {
    // XCUITest drops quotes from launch arguments, so these pages are written without any.

    /// In dark mode a page that sets no colours of its own is white with black text, as in Safari
    /// and Arc Search. The web view used to be see-through over the black app background, which
    /// left such a page's black text on black.
    func testAPageWithoutColoursStaysWhiteInDarkMode() {
        launch(["-CraOpenURL", "data:text/html,<meta/name=viewport/content=width=device-width><title>Plain</title><h1>Plain</h1>",
                "-CraSearch", "NO", "-CraAppearance", "dark"])
        waitForPage("Plain")
        sleep(1)
        keep("plain-page-dark")
        let shot = XCUIScreen.main.screenshot().image
        guard let image = shot.cgImage, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return XCTFail("no screenshot")
        }
        // The middle of the screen, well clear of the heading and the bar.
        let x = image.width / 2, y = image.height / 2
        let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        let brightness = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
        XCTAssertGreaterThan(brightness, 200, "the page is white, not the app's black")
    }

    /// A download link saves the file, says so above the bar, and lists it under Settings ▸ Downloads;
    /// downloading it again keeps both, the second one numbered.
    func testADownloadIsSavedAnnouncedAndListed() {
        let page = "data:text/html,<meta name=viewport content=width=device-width><title>Files</title><h1>Files</h1>"
            + "<a href=data:text/plain,hello download=hello.txt style=font-size:40px>Get file</a>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Files")
        app.webViews.links["Get file"].tap()
        let toast = app.buttons["download-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertTrue(toast.label.contains("hello"))
        keep("download-toast")
        sleep(5)
        app.webViews.links["Get file"].tap()
        XCTAssertTrue(app.buttons["download-toast"].waitForExistence(timeout: 10))
        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        app.buttons["settings-downloads"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'download-row-hello'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(app.buttons["download-row-hello 2.txt"].exists, "the second copy is numbered, not written over the first")
        keep("downloads")
    }

    /// A page's alert shows with its message and goes away on OK; the tap that raised it went
    /// through the browser's own swipe and pinch recognizers to the page.
    func testAPagesAlertShows() {
        let page = "data:text/html,<meta name=viewport content=width=device-width><title>Dialogs</title><h1>Dialogs</h1>"
            + "<button onclick=alert(1234) style=font-size:40px>Say hi</button>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Dialogs")
        app.webViews.buttons["Say hi"].tap()
        XCTAssertTrue(app.alerts.staticTexts["1234"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1))
    }
}

final class EmptyHomeTests: BrowserTestCase {
    /// With no tabs the search sheet can still be put away: what is left is the empty home
    /// screen, whose logo spins when it is flicked, and the pill brings the sheet back.
    func testTheEmptyHomeScreenHasALogoThatSpins() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 200)), withVelocity: .fast, thenHoldForDuration: 0)
        let logo = app.images["logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bar-search"].exists)
        XCTAssertFalse(app.staticTexts["Tap to search"].exists, "the dots are off until App Settings turns them on")
        XCTAssertEqual(logo.value as? String, "0.0 turns")
        // A flick across its right-hand side, downwards: clockwise.
        let from = logo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2))
        from.press(forDuration: 0.05, thenDragTo: logo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        keep("empty-home")
        XCTAssertNotEqual(logo.value as? String, "0.0 turns")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    /// App Settings ▸ Rippling Dots (PR #708, Victor 23 Nov 2026: a setting, with the logo kept) lays a field of dots
    /// under the logo that sends a ring out wherever it is tapped, with "Tap to search" over the pill; the pill still
    /// brings the sheet back.
    func testRipplingDotsAreASettingUnderTheLogo() {
        rippleDots(appearance: "light")
    }

    /// The same in dark mode: the near-black backdrop under the dots.
    func testRipplingDotsInDarkMode() {
        rippleDots(appearance: "dark")
    }

    private func rippleDots(appearance: String) {
        // One page, so App Settings opens from its tab row; closing that last tab leaves the empty home screen.
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraAppearance", appearance])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        app.buttons["bar-settings"].tap()
        let toggle = app.switches["setting-home-dots"]
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()
        let card = app.buttons["tab-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        sleep(1)
        card.swipeUp(velocity: .fast)
        // The last tab gone, the sheet comes up ready to type (as without the dots); put away, the home is left.
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 200)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.staticTexts["Tap to search"].waitForExistence(timeout: 5))
        let logo = app.images["logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 5), "the logo stays over the dots")
        let dots = app.otherElements["dot-field"]
        XCTAssertTrue(dots.exists)
        XCTAssertTrue(app.buttons["bar-search"].exists)
        XCTAssertEqual(dots.value as? String, "0 rings")
        dots.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2)).tap()
        dots.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75)).press(forDuration: 0.5)
        XCTAssertEqual(dots.value as? String, "2 rings")
        keep("empty-home-dots-\(appearance)")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "tapping the dots doesn't open the search")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }
}

final class SiteMatchTests: BrowserTestCase {
    // promise: #650
    func testSyncedSpaceSitesShowTheirPlaceAndOpen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(SpacesTests.macSidebar.utf8).write(to: folder.appendingPathComponent("sidebar.json"))
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", folder.path])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        field.typeText("docs")
        let docs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES 'suggestion-[0-9]+'"))
            .containing(.staticText, identifier: "Docs").firstMatch
        XCTAssertTrue(docs.waitForExistence(timeout: 10))
        XCTAssertTrue(docs.staticTexts["Pinned in Work"].exists)
        app.buttons["search-clear"].tap()
        field.typeText("story")
        let story = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES 'suggestion-[0-9]+'"))
            .containing(.staticText, identifier: "Story").firstMatch
        // The Mac's Today tabs come too, saying so (Victor, 20 Nov).
        XCTAssertTrue(story.waitForExistence(timeout: 10))
        XCTAssertTrue(story.staticTexts["Today in Work"].exists)
        app.buttons["search-clear"].tap()
        field.typeText("docs")
        XCTAssertTrue(docs.waitForExistence(timeout: 5))
        keep("space-site-match")
        docs.tap()
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab-card-2"].exists)
        XCTAssertEqual(app.buttons["tab-card-1"].label, "docs.example")
    }

    // promise: #650
    func testPhoneSiteWinsOverSyncedSpace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(SpacesTests.macSidebar.utf8).write(to: folder.appendingPathComponent("sidebar.json"))
        launch(["-CraOpenURL", "http://docs.example/", "-CraSearch", "NO", "-CraSyncDir", folder.path])
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 10))
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText("docs")
        let list = app.scrollViews["suggestion-list"]
        XCTAssertTrue(list.staticTexts["docs.example"].waitForExistence(timeout: 10))
        XCTAssertEqual(list.staticTexts.matching(identifier: "docs.example").count, 1)
        XCTAssertFalse(list.staticTexts["Docs"].exists)
        XCTAssertFalse(list.staticTexts["Pinned in Work"].exists)
    }

    /// A page the phone has open comes up as a row when its address is typed, above the typed
    /// text, and a tap on it opens it. The address never loads (`.invalid`), so no network.
    func testAnOpenPageIsOfferedWhenItsAddressIsTyped() {
        launch(["-CraOpenURL", "http://sitematch.invalid/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 10))
        sleep(2)
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        app.textFields["search-field"].typeText("sitem")
        let row = app.descendants(matching: .any)["suggestion-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.staticTexts["sitematch.invalid"].waitForExistence(timeout: 3), "the open page leads the list")
        XCTAssertTrue(app.descendants(matching: .any)["suggestion-1"].staticTexts["sitem"].exists, "the typed text follows it")
        keep("site-match")
    }
}

final class BrowseToggleTests: BrowserTestCase {
    /// A Browse for Me page has the switch with its own side on; the engine's side opens the
    /// search engine's results for the same query in the tab, and Browse for Me brings the page
    /// back without reading the sites again. Needs the network for the engine's results.
    func testTheSwitchMovesBetweenBrowseForMeAndTheSearchEngine() {
        launch(["-CraFakeModel", "YES"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("pizza ovens")
        let chip = app.buttons["browse-for-me"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.webViews.staticTexts["About pizza ovens"].waitForExistence(timeout: 15))
        let browse = app.buttons["toggle-browse"]
        let engine = app.buttons["toggle-engine"]
        XCTAssertTrue(browse.waitForExistence(timeout: 5), "the switch shows on a Browse for Me page")
        XCTAssertTrue(browse.isSelected)
        XCTAssertEqual(engine.label, "Google")
        sleep(1)
        keep("browse-toggle")
        engine.tap()
        let engineOn = NSPredicate(format: "isSelected == true")
        expectation(for: engineOn, evaluatedWith: engine)
        waitForExpectations(timeout: 25)
        keep("browse-toggle-engine")
        browse.tap()
        XCTAssertTrue(app.webViews.staticTexts["About pizza ovens"].waitForExistence(timeout: 5), "the page comes back from the cache")
        XCTAssertFalse(app.staticTexts["browse-reading"].exists, "nothing is read again")
        XCTAssertTrue(browse.isSelected)
    }

    /// "Browse for Me" picked as the search engine: Go makes a Browse for Me page instead of
    /// opening the engine's results.
    func testBrowseForMeCanBeTheSearchEngine() {
        launch(["-CraFakeModel", "YES", "-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-settings"].waitForExistence(timeout: 5))
        app.buttons["bar-settings"].tap()
        // The row's identifier lands on its menu's button (and its label and icon).
        let menu = app.buttons["setting-search-engine"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Google")
        menu.tap()
        let choice = app.buttons["Browse for Me"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the menu offers Browse for Me")
        choice.tap()
        expectation(for: NSPredicate(format: "label == 'Browse for Me'"), evaluatedWith: menu)
        waitForExpectations(timeout: 5)
        keep("search-engine-browse")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        app.buttons["tab-card-0"].tap()
        waitForPage("First")
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText("pizza ovens\n")
        XCTAssertTrue(app.staticTexts["browse-reading"].waitForExistence(timeout: 8), "Go made a Browse for Me page")
        XCTAssertTrue(app.webViews.staticTexts["About pizza ovens"].waitForExistence(timeout: 15))
    }

    /// Selected text on a page has "Browse for Me" in its edit menu, which makes a page about it.
    func testSelectedTextCanBeBrowsedFor() {
        launch(["-CraFakeModel", "YES", "-CraOpenURL", Self.page("Ovens"), "-CraSearch", "NO"])
        waitForPage("Ovens")
        app.webViews.staticTexts["Ovens"].press(forDuration: 1.2)
        sleep(1)
        // A tap on the selection brings up its edit menu.
        if !app.menuItems["Copy"].exists { app.webViews.staticTexts["Ovens"].tap() }
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3), "the edit menu is up")
        keep("selection-menu")
        let item = app.menuItems["Browse for Me"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "the edit menu offers Browse for Me")
        item.tap()
        XCTAssertTrue(app.staticTexts["browse-query"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["browse-query"].label, "Ovens")
    }
}

final class ShareExtensionTests: BrowserTestCase {
    /// A link the share extension saved for Tabs joins the tab row behind the page on screen.
    func testALinkSavedForTabsJoinsTheRow() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraFakeShare", "https://saved.invalid/page"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5), "the saved link is a second tab")
        XCTAssertEqual(app.buttons["tab-card-1"].label, "Shared page")
    }

    /// One saved for Favorites shows under the empty search field.
    func testALinkSavedForFavoritesShowsUnderTheSearchField() {
        launch(["-CraFakeShare", "https://saved.invalid/page", "-CraFakeShareTo", "favorites"])
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Shared page"].waitForExistence(timeout: 5))
    }

    /// The extension itself, from the page menu's share sheet: "Saved", the place picker, Done.
    func testTheShareSheetSavesThroughTheExtension() {
        // A page that loads (the network is needed): the share sheet shares the page's address.
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 10))
        sleep(6)
        app.buttons["bar-menu"].press(forDuration: 1.2)
        let cra = app.collectionViews.cells.matching(NSPredicate(format: "label == 'Cra'")).firstMatch
        if !cra.waitForExistence(timeout: 8) {
            keep("share-sheet")
            XCTFail(app.debugDescription)
            return
        }
        cra.tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 8))
        sleep(1)
        keep("share-saved")
        app.buttons["share-done"].tap()
        sleep(1)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 10))
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5), "the shared link came back as a tab")
    }
}

final class TranslateTests: BrowserTestCase {
    /// Translate turns the page into the phone's language (capitals stand in, no model) and the
    /// row becomes "Show Original", which puts the page's words back.
    func testTranslateAndShowOriginal() {
        launch(["-CraOpenURL", Self.page("Bonjour"), "-CraSearch", "NO", "-CraFakeTranslate", "YES"])
        waitForPage("Bonjour")
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-displayOptions"].tap()
        let row = app.buttons["menu-row-translate"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Translate")
        row.tap()
        sleep(1)
        keep("translated")
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-displayOptions"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Show Original")
        row.tap()
        sleep(1)
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-displayOptions"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Translate")
    }
}

final class SuggestionScrollTests: BrowserTestCase {
    /// Scrolling the suggestions up brings each one into the field; back at the top the field
    /// shows what was typed, and Go searches for what the field shows.
    func testScrollingTheSuggestionsPutsEachInTheField() {
        launch(["-CraFakeSuggestions", "YES"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("ovens")
        XCTAssertTrue(app.descendants(matching: .any)["suggestion-9"].waitForExistence(timeout: 5), "ten rows are listed")
        let list = app.scrollViews["suggestion-list"]
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("ovens "), "a suggestion is in the field: \(value)")
        keep("suggestion-scroll")
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)), withVelocity: .fast, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertEqual(field.value as? String, "ovens", "back at the top, what was typed")
    }
}

final class AppLinkTests: BrowserTestCase {
    /// With links going to native apps (the default), a tapped link that no app claims still
    /// loads in Cra. Needs the network for example.com.
    func testALinkNoAppClaimsLoadsHere() {
        launch(["-CraOpenURL", "data:text/html,<meta/name=viewport/content=width=device-width><a/href=https://example.com/>Go/there</a>", "-CraSearch", "NO"])
        let link = app.webViews.links.firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        sleep(6)
        // The page menu names the page's site (the web view's own text isn't always readable here).
        app.buttons["bar-menu"].tap()
        let host = app.staticTexts["menu-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertEqual(host.label, "example.com", "the link loaded in the browser")
    }
}

final class WidgetGuideTests: BrowserTestCase {
    /// App Settings ▸ Add Widget walks through Arc Search's three steps and closes on Done!.
    func testTheWidgetGuideWalksThroughItsSteps() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-settings"].waitForExistence(timeout: 5))
        app.buttons["bar-settings"].tap()
        let row = app.buttons["setting-add-widget"]
        XCTAssertTrue(app.buttons["setting-default-browser"].waitForExistence(timeout: 5))
        // Further down the list.
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let title = app.staticTexts["widget-guide-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Bring Cra to your home screen")
        sleep(1)
        keep("widget-guide-1")
        app.buttons["widget-guide-next"].tap()
        sleep(2)
        XCTAssertTrue(title.label.hasPrefix("Start by holding"))
        keep("widget-guide-2")
        app.buttons["widget-guide-next"].tap()
        sleep(3)
        XCTAssertTrue(title.label.contains("Add Widget"))
        keep("widget-guide-3")
        app.buttons["widget-guide-next"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2), "Done! closes the guide")
    }
}

final class AppIconDockTests: BrowserTestCase {
    // promise: #686
    func testChangeIconQuickActionOpensTallOnIPadAndHalfOnIPhone() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraShortcut", "change-icon"])
        let navigationBar = app.navigationBars["App Icon"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        for icon in ["segments", "midnight", "mono", "violet"] {
            XCTAssertTrue(app.buttons["icon-\(icon)"].exists, icon)
        }
        sleep(1)
        keep("app-icon-picker-open")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertLessThan(navigationBar.frame.minY, app.frame.height / 3,
                              "the App Icon picker opened as a short card on iPad")
        } else {
            XCTAssertGreaterThan(navigationBar.frame.minY, app.frame.height * 0.4,
                                 "the App Icon picker did not open at medium height on iPhone")
        }
    }

    /// On iPad the Change App Icon picker shows all four icons whole, at an iPhone's size: its grid
    /// once stretched to the wide sheet, so the icons grew past 250 pt and the second row was cut off.
    func testIconPickerFitsEveryIconOnIPad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPhone opens the picker as a half sheet")
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraShortcut", "change-icon"])
        XCTAssertTrue(app.navigationBars["App Icon"].waitForExistence(timeout: 5))
        sleep(1)
        let sheet = app.scrollViews.firstMatch.frame
        for icon in ["segments", "midnight", "mono", "violet"] {
            let frame = app.buttons["icon-\(icon)"].frame
            XCTAssertTrue(sheet.contains(frame), "\(icon) at \(frame) is cut off by the picker \(sheet)")
            XCTAssertLessThanOrEqual(frame.width, 200, "\(icon) grew to the iPad sheet's width")
        }
        keep("app-icon-picker-ipad")
    }

    /// App Settings ▸ Change App Icon opens Arc Search's dock sheet with every icon on its shelf,
    /// the current one marked.
    func testChangeAppIconShowsTheDock() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-settings"].waitForExistence(timeout: 5))
        app.buttons["bar-settings"].tap()
        let row = app.buttons["setting-app-icon"]
        XCTAssertTrue(app.buttons["setting-default-browser"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.staticTexts["App Icon"].waitForExistence(timeout: 5))
        for icon in ["segments", "midnight", "mono", "violet"] {
            XCTAssertTrue(app.buttons["icon-\(icon)"].exists, icon)
        }
        XCTAssertTrue(app.buttons["icon-segments"].isSelected, "the current icon is marked")
        sleep(1)
        keep("icon-dock")
    }
}

final class LanguagesTests: BrowserTestCase {
    /// App Settings ▸ Languages follows the iPhone until a language is picked, and keeps it.
    func testLanguagesKeepsTheChosenLanguage() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-settings"].waitForExistence(timeout: 5))
        app.buttons["bar-settings"].tap()
        let menu = app.buttons["setting-languages"]
        XCTAssertTrue(app.buttons["setting-default-browser"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Same as iPhone")
        menu.tap()
        let french = app.buttons["French"].firstMatch
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()
        expectation(for: NSPredicate(format: "label == 'French'"), evaluatedWith: menu)
        waitForExpectations(timeout: 5)
        app.buttons["Done"].tap()
        XCTAssertFalse(menu.waitForExistence(timeout: 1))
        sleep(1)
        app.buttons["bar-settings"].tap()
        XCTAssertTrue(app.buttons["setting-default-browser"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.buttons["setting-languages"].isHittable { app.swipeUp() }
        XCTAssertEqual(app.buttons["setting-languages"].label, "French")
    }
}

final class CustomSearchEngineTests: BrowserTestCase {
    /// Search Engine ▸ Custom asks for an address with %s; Go then searches there.
    func testACustomEngineTakesTheSearch() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["bar-settings"].waitForExistence(timeout: 5))
        app.buttons["bar-settings"].tap()
        let menu = app.buttons["setting-search-engine"]
        XCTAssertTrue(app.buttons["setting-default-browser"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !menu.isHittable { app.swipeUp() }
        menu.tap()
        app.buttons["Custom"].firstMatch.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the address is asked for")
        // The field starts with "https://".
        field.tap()
        field.typeText("custom.invalid/find?q=%s")
        keep("custom-engine")
        app.alerts.buttons["Save"].tap()
        expectation(for: NSPredicate(format: "label == 'custom.invalid'"), evaluatedWith: menu)
        waitForExpectations(timeout: 5)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        app.buttons["tab-card-0"].tap()
        waitForPage("First")
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText("pizza ovens\n")
        sleep(2)
        // The address never loads (.invalid); the new tab is named by its site.
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-1"].label, "custom.invalid", "the search went to the custom engine")
    }
}

final class LandscapeTests: BrowserTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// In landscape the search field stays on screen above the keyboard (fewer rows), and the
    /// page menu's address capsule stays below the top edge (the rest scrolls).
    func testSearchAndTheMenuFitInLandscape() {
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO", "-CraFakeSuggestions", "YES"])
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("ovens")
        sleep(1)
        XCTAssertGreaterThanOrEqual(field.frame.minY, 0, "the field is on screen")
        XCTAssertTrue(field.isHittable)
        app.otherElements["search-dismiss"].firstMatch.tap()
        sleep(1)
        app.buttons["bar-menu"].tap()
        let host = app.staticTexts["menu-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertGreaterThanOrEqual(host.frame.minY, 0, "the address capsule is on screen")
        XCTAssertTrue(host.isHittable)
    }
}

final class FavoriteOrderTests: BrowserTestCase {
    /// A favorite under the empty search field can be held and dragged to another place, and
    /// keeps it.
    func testAFavoriteCanBeDraggedToAnotherPlace() {
        launch(["-CraOpenURL", "data:text/html,<meta/name=viewport/content=width=device-width><title>Starred</title><h1>Heading</h1>",
                "-CraSearch", "NO", "-CraFakeShare", "https://saved.invalid/page", "-CraFakeShareTo", "favorites"])
        waitForPage("Heading")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-pin"].waitForExistence(timeout: 5))
        app.buttons["menu-tile-pin"].tap()
        XCTAssertEqual(app.buttons["menu-tile-pin"].label, "Pinned")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        app.buttons["bar-search"].tap()
        let shared = app.staticTexts["Shared page"], starred = app.staticTexts["Starred"]
        XCTAssertTrue(starred.waitForExistence(timeout: 5) && shared.exists)
        XCTAssertLessThan(shared.frame.minY, starred.frame.minY, "the shared link came first")
        starred.press(forDuration: 0.8, thenDragTo: shared, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertLessThan(starred.frame.minY, shared.frame.minY, "dragged above")
        app.otherElements["search-dismiss"].firstMatch.tap()
        sleep(1)
        app.buttons["bar-search"].tap()
        XCTAssertTrue(starred.waitForExistence(timeout: 5))
        XCTAssertLessThan(starred.frame.minY, shared.frame.minY, "the new order is kept")
    }
}

final class AppleIntelligenceTests: BrowserTestCase {
    /// An iPhone that can run Apple Intelligence shows Browse for Me even with it switched off;
    /// a tap asks to switch it on instead of browsing (Victor, 13 Nov).
    func testWithAppleIntelligenceOffBrowseForMeAsksToTurnItOn() {
        launch(["-CraAIState", "off"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("pizza ovens")
        let chip = app.buttons["browse-for-me"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the button shows")
        chip.tap()
        let alert = app.alerts["Turn on Apple Intelligence"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Open Settings"].exists)
        sleep(1)
        keep("apple-intelligence-off")
        alert.buttons["Not Now"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["browse-query"].exists, "nothing was browsed")
    }

    /// A phone that can't run Apple Intelligence has no Browse for Me at all.
    func testAPhoneWithoutAppleIntelligenceHasNoBrowseForMe() {
        launch(["-CraAIState", "unsupported"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("pizza ovens")
        XCTAssertTrue(app.staticTexts["pizza ovens"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browse-for-me"].exists)
    }
}

final class RecentTabsTests: BrowserTestCase {
    // promise: #591
    func testRecentTabsShowUnderTheEmptyField() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sidebar = SpacesTests.macSidebar.replacingOccurrences(of: "2026-11-17T10:00:00Z", with: "2099-11-17T10:00:00Z")
        try Data(sidebar.utf8).write(to: folder.appendingPathComponent("sidebar.json"))
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraSyncDir", folder.path])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-search"].tap()
        let firstRow = app.descendants(matching: .any)["suggestion-0"]
        let secondRow = app.descendants(matching: .any)["suggestion-1"]
        XCTAssertTrue(firstRow.staticTexts["Inbox"].waitForExistence(timeout: 10))
        XCTAssertTrue(secondRow.staticTexts["First"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["suggestion-list"].staticTexts["Second"].exists)
        keep("recent-tabs")
        secondRow.tap()
        waitForPage("First")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(firstRow.staticTexts["Inbox"].waitForExistence(timeout: 10))
        firstRow.tap()
        waitForPage("Inbox")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-card-3"].exists)
    }
}
