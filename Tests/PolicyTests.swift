import Foundation

/// The decisions pulled out of the window controllers: what an extension click does, the
/// DevTools toggle and the feature flags (the toolbar's buttons moved to CraCore). Table tests,
/// no AppKit views.
@main
enum PolicyTests {
    private static var checks = 0

    @MainActor
    static func main() {
        extensionLaunch()
        devToolsToggle()
        featureFlags()
        print("Policies: \(checks) checks passed")
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

    private static func featureFlags() {
        expect(FeatureFlags(parsing: "").backdrop == .layer, "the calibrated backdrop layer is the default")
        expect(FeatureFlags(parsing: "backdrop=material").backdrop == .material, "CRA_FLAGS picks the material path")
        expect(FeatureFlags(parsing: "x=1&backdrop=material&y").backdrop == .material, "other keys around it are ignored")
        expect(FeatureFlags(parsing: "backdrop=glass").backdrop == .layer && FeatureFlags(parsing: "backdrop").backdrop == .layer,
               "an unknown value or a bare key keeps the default")
        expect(FeatureFlags(parsing: "backdrop=material").summary == "backdrop=material", "the log line names the path")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
