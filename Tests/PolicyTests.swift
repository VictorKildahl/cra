import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var openedURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        openedURLs.append(contentsOf: urls)
    }
}

/// App policies tested without browser windows or Chromium.
@main
enum PolicyTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        extensionLaunch()
        devToolsToggle()
        featureFlags()
        liveScheduler()
        try webHandoff()
        try defaultBrowserPicker()
        try iPhoneDefaultBrowser()
        try iPhoneWebContentLoadsHTTP()
        print("Policies: \(checks) checks passed")
    }

    @MainActor
    private static func webHandoff() throws {
        let plist = try Data(contentsOf: URL(fileURLWithPath: "resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        expect((info?["NSUserActivityTypes"] as? [String])?.contains(NSUserActivityTypeBrowsingWeb) == true,
               "macOS can offer Cra for web Handoff")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let receiver = AppDelegate()
        let delegate: NSApplicationDelegate = receiver
        let web = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        let other = NSUserActivity(activityType: "com.example.other")
        expect(delegate.application?(app, willContinueUserActivityWithType: web.activityType) == true, "accept a web Handoff")
        expect(delegate.application?(app, willContinueUserActivityWithType: other.activityType) == false, "decline unrelated activities")

        func resume(_ activity: NSUserActivity) -> Bool? {
            delegate.application?(app, continue: activity, restorationHandler: { _ in })
        }
        expect(resume(web) == false, "a missing webpage cannot be continued")
        web.webpageURL = URL(string: "https:/missing-host")
        expect(resume(web) == false, "a web address without a host is ignored")
        let urls = ["http://example.test/", "https://example.test/a%20b?q=1#part"].map { URL(string: $0)! }
        other.webpageURL = urls[0]
        expect(resume(other) == false, "a webpage on an unrelated activity is ignored")
        for url in urls {
            web.webpageURL = url
            expect(resume(web) == true, "continue a handed-off web page")
        }
        expect(receiver.openedURLs == urls, "only the accepted pages reach normal URL opening, once each and intact")
    }

    // promise: #452
    /// #452: System Settings ▸ Desktop & Dock ▸ Default web browser lists only the apps that open
    /// http and https links and both public.html and public.xhtml files (DesktopSettings.appex asks
    /// LSOpenWithMenuConstructor for that set). With public.html alone, Cra was missing from it.
    private static func defaultBrowserPicker() throws {
        let plist = try Data(contentsOf: URL(fileURLWithPath: "resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let schemes = (info?["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        expect(schemes.contains("http") && schemes.contains("https"), "Cra opens http and https links")
        let types = (info?["CFBundleDocumentTypes"] as? [[String: Any]] ?? [])
            .filter { ($0["CFBundleTypeRole"] as? String) == "Viewer" }
            .flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        expect(types.contains("public.html"), "Cra views HTML files")
        expect(types.contains("public.xhtml"), "Cra views XHTML files, so the system's default browser picker lists it")
    }

    // promise: #504 #536
    /// #504: iOS lists an app under Settings ▸ Apps ▸ Default Apps ▸ Browser App, and gives the
    /// app's own Settings page its "Default Browser App" row, only when the app is signed with
    /// Apple's managed `com.apple.developer.web-browser` entitlement (granted to the team 18 Nov
    /// 2026, request 2557T8YX24). Without it "Set Cra as Default Browser" led to a page with nothing
    /// to pick. Apple also asks for http and https in the Info.plist, and the entitlement rules out
    /// Universal Links (associated domains). #536: the same entitlement is what lets WebKit pass a
    /// site's passkey request to iOS; without it every passkey sign-in failed (PasskeyTests).
    private static func iPhoneDefaultBrowser() throws {
        let entitlementsData = try Data(contentsOf: URL(fileURLWithPath: "iOS/Support/Cra.entitlements"))
        let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        expect(entitlements?["com.apple.developer.web-browser"] as? Bool == true,
               "the iPhone app is signed as a web browser, so iOS lets people make it the default")
        expect(entitlements?["com.apple.developer.associated-domains"] == nil,
               "a default-browser app claims no Universal Links")
        let plist = try Data(contentsOf: URL(fileURLWithPath: "iOS/Support/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let schemes = (info?["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        expect(schemes.contains("http") && schemes.contains("https"), "the iPhone app opens http and https links")
    }

    // promise: #568
    /// #568: every http:// address opened as a blank white page on the iPhone. With no
    /// NSAppTransportSecurity entry iOS refuses plain-http loads in the web view too (error -1022).
    /// NSAllowsArbitraryLoadsInWebContent is Apple's key for browsers: it lets web views load http
    /// as Arc Search, Safari and Cra for Mac do, while the app's own requests stay under ATS. The
    /// broader NSAllowsArbitraryLoads would let those through as well, and iOS ignores the
    /// web-content key when it is set.
    private static func iPhoneWebContentLoadsHTTP() throws {
        let plist = try Data(contentsOf: URL(fileURLWithPath: "iOS/Support/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let ats = info?["NSAppTransportSecurity"] as? [String: Any]
        expect(ats?["NSAllowsArbitraryLoadsInWebContent"] as? Bool == true, "the iPhone app's web views load http:// pages")
        expect(ats?["NSAllowsArbitraryLoads"] == nil, "the app's own requests stay https-only")
    }

    /// #41: a click never reaches an extension turned off in chrome://extensions (Chromium crashed
    /// on it). #22: nor one the page's profile doesn't have; that click does nothing.
    // promise: #22 #41
    private static func extensionLaunch() {
        typealias E = ExtensionLaunch.Extension
        let popup = E(id: "pop", popupPath: "popup.html", optionsPath: "options.html")
        let options = E(id: "opt", popupPath: nil, optionsPath: "settings.html")
        let bare = E(id: "bare")
        let off = E(id: "off", popupPath: "popup.html", enabled: false)
        let all = [popup, options, bare, off]
        expect(ExtensionLaunch.decide("pop", available: all, hasPage: true) == .runAction, "with a page, Chrome runs the action")
        expect(ExtensionLaunch.decide("off", available: all, hasPage: true) == .nothing,
               "a click never reaches an extension turned off in chrome://extensions")
        expect(ExtensionLaunch.decide("off", available: all, hasPage: false) == .nothing, "not even without a page")
        expect(ExtensionLaunch.fallback(off) == .nothing, "nor when Chrome's action failed")
        expect(ExtensionLaunch.decide("gone", available: all, hasPage: true) == .nothing, "an extension of another profile does nothing")
        expect(ExtensionLaunch.decide("pop", available: all, hasPage: false) == .popupWindow(url: "chrome-extension://pop/popup.html"),
               "no page: the popup page in its own window")
        expect(ExtensionLaunch.decide("opt", available: all, hasPage: false) == .openTab(url: "chrome-extension://opt/settings.html"),
               "no popup: the options page in a tab")
        expect(ExtensionLaunch.decide("bare", available: all, hasPage: false) == .openTab(url: "chrome://extensions/?id=bare"),
               "neither: Chrome's details page for it")
    }

    // promise: #88 #138
    /// DevTools' toggle, and the developer bar's Console, Network and Inspect as Chrome runs them (#88).
    /// #138: the developer bar's Console and Network switch open DevTools to their panel and close
    /// them only when that panel already shows; a press while they open picks the panel.
    private static func devToolsToggle() {
        var t = DevToolsToggle()
        expect(t.toggle() == .show && t.state == .opening, "closed: a press opens")
        t.didOpen()
        expect(t.toggle() == .close && t.state == .closing(reopen: false), "open: a press closes")
        expect(t.toggle() == .none && t.state == .closing(reopen: true), "closing: a press is remembered, not sent")
        expect(t.toggle() == .none && t.state == .closing(reopen: false), "a third press takes it back")
        expect(t.didClose() == .none && t.state == .closed, "closed with nothing pending stays closed")
        _ = t.toggle()
        t.didOpen()
        _ = t.toggle()
        expect(t.show() == .none && t.state == .closing(reopen: true), "Inspect Element while closing waits for the close")
        expect(t.didClose() == .show && t.state == .opening, "and opens them once closed")
        t.didOpen()
        expect(t.show() == .show && t.state == .open, "Inspect Element on open DevTools moves them to the element")
        var external = DevToolsToggle()
        external.didOpen()
        expect(external.state == .open && external.toggle() == .close, "DevTools opened from Chromium's menu close on the next press")
        var userClosed = DevToolsToggle()
        _ = userClosed.toggle()
        userClosed.didOpen()
        expect(userClosed.didClose() == .none && userClosed.toggle() == .show, "closed from DevTools' own button: the next press opens")

        // The developer bar and ⌥⌘J/⌥⌘C (#88): Console and Network switch panels, close only their own (#138).
        var bar = DevToolsToggle()
        expect(bar.run(.console) == (.show, "console"), "Console on closed DevTools opens them on the Console")
        expect(bar.run(.network) == (.none, "network") && bar.state == .opening, "pressed while they open: they open on Network instead")
        bar.didOpen()
        bar.didShowPanel("console")
        expect(bar.run(.network) == (.frontend, "network") && bar.state == .open, "Network on the Console switches panel, DevTools stay open")
        expect(bar.run(.network) == (.close, nil) && bar.state == .closing(reopen: false),
               "pressed again before the frontend reports the switch: Network shows, so it closes")
        expect(bar.run(.network) == (.none, "network") && bar.state == .closing(reopen: true), "pressed while closing: reopened on Network")
        expect(bar.run(.console) == (.none, nil) && bar.state == .closing(reopen: false), "a second press takes the reopen back")
        expect(bar.run(.console) == (.none, "console"), "a third asks again, on the Console")
        expect(bar.didClose() == .show && bar.panel == nil, "once closed they reopen, the old panel forgotten")
        bar.didOpen()
        bar.didShowPanel("elements")
        expect(bar.run(.console) == (.frontend, "console"), "Console on Elements switches")
        bar.didShowPanel("console")
        expect(bar.run(.console) == (.close, nil), "Console on the Console closes")
        expect(bar.didClose() == .none && bar.state == .closed && bar.panel == nil, "and stays closed")
        bar.didShowPanel("network")
        expect(bar.panel == nil, "a report from a closed frontend is dropped")
        var unknown = DevToolsToggle()
        unknown.didOpen()
        expect(unknown.run(.console) == (.frontend, "console"), "a frontend that never said its panel: switch, never close")
        bar = DevToolsToggle()
        _ = bar.run(.console)
        bar.didOpen()
        expect(bar.run(.inspect) == (.show, "inspect") && bar.state == .open, "Inspect never closes: the picker on open DevTools")
        expect(bar.run(.toggle) == (.close, nil), "⌥⌘I closes")
        var plain = DevToolsToggle()
        expect(plain.run(.toggle) == (.show, nil), "⌥⌘I opens DevTools as they were")
    }

    /// The app's clock: work runs whether or not the caller keeps the handle, and only cancel()
    /// stops it. SharingService's first usage report, 30 s after launch, was dropped because its
    /// handle wasn't kept, so 0.1.38 sent no stats until six hours in.
    @MainActor
    private static func liveScheduler() {
        let clock = LiveScheduler()
        var dropped = false, kept = false, cancelled = false
        _ = clock.after(0.05) { dropped = true }
        let handle = clock.after(0.05) { kept = true }
        clock.after(0.05) { cancelled = true }.cancel()
        let until = Date().addingTimeInterval(2)
        while !(dropped && kept), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expect(kept, "kept work runs")
        expect(dropped, "work whose handle was let go still runs")
        expect(!cancelled, "cancelled work doesn't run")
        _ = handle
    }

    private static func featureFlags() {
        expect(FeatureFlags(parsing: "").backdrop == .layer, "the calibrated backdrop layer is the default")
        expect(FeatureFlags(parsing: "backdrop=material").backdrop == .material, "CRA_FLAGS picks the material path")
        expect(FeatureFlags(parsing: "x=1&backdrop=material&y").backdrop == .material, "other keys around it are ignored")
        expect(FeatureFlags(parsing: "backdrop=glass").backdrop == .layer && FeatureFlags(parsing: "backdrop").backdrop == .layer,
               "an unknown value or a bare key keeps the default")
        expect(FeatureFlags(parsing: "backdrop=material").summary == "backdrop=material sidebarSlide=live", "the log line names the paths")
        // #613: ⌘S resizes the page as the sidebar slides, as Arc does; frozen keeps #317's page sized up front.
        expect(FeatureFlags(parsing: "").sidebarSlide == .live, "the sidebar's slide resizes the page live by default (Arc's)")
        expect(FeatureFlags(parsing: "sidebarSlide=frozen&backdrop=material").sidebarSlide == .frozen, "CRA_FLAGS picks the frozen slide")
        expect(FeatureFlags(parsing: "sidebarSlide=fast").sidebarSlide == .live, "an unknown slide keeps the default")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
