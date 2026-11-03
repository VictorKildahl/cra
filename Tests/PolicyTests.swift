import Foundation

/// The decisions pulled out of the window controllers: the toolbar's buttons (Arc 1.170), what
/// an extension click does, and the DevTools toggle. Table tests, no AppKit views.
@main
enum PolicyTests {
    private static var checks = 0

    @MainActor
    static func main() {
        toolbar()
        extensionLaunch()
        devToolsToggle()
        featureFlags()
        print("Policies: \(checks) checks passed")
    }

    private static func toolbar() {
        typealias T = ToolbarComposition
        func bar(_ kind: T.Kind, split: Bool = false, sidebar: Bool = false, focused: Bool = true, back: Bool = false,
                 forward: Bool = false, loading: Bool = false, pinned: [String] = [], extensions: Bool = false) -> T {
            T(kind: kind, inSplit: split, sidebarVisible: sidebar, focusedPane: focused, canGoBack: back, canGoForward: forward,
              isLoading: loading, pinnedExtensions: pinned, hasExtensions: extensions)
        }
        let full = bar(.normal, back: true, loading: true, pinned: ["a", "b"], extensions: true)
        expect(full.left == [.toggleSidebar, .back(enabled: true), .forward(enabled: false), .reload(loading: true, enabled: true)],
               "the full bar: toggle, ← → and ↻ (an ✕ while loading)")
        expect(full.right == [.pinnedExtension("a"), .pinnedExtension("b"), .extensions, .addSplit],
               "the right end: pinned extensions, Extensions, Split View")
        expect(bar(.normal).right == [.addSplit], "no Extensions button without extensions")
        expect(bar(.normal, sidebar: true).left == [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: true)]
               && bar(.noTab, sidebar: true).left.first == .back(enabled: false) && bar(.developer, sidebar: true).left.isEmpty,
               "the sidebar shown: its header carries the toggle, the bar has none (Arc 1.171, #50)")
        let pane = bar(.normal, split: true, back: true, pinned: ["a"], extensions: true)
        expect(pane.left == [.back(enabled: true), .forward(enabled: false)] && pane.right == [.splitOptions, .closePane],
               "a focused split pane: only ← →, then its options and close")
        expect(bar(.normal, split: true, focused: false).right == [.closePane], "an unfocused pane has only its close button")
        expect(bar(.emptyPane, split: true).left == [.back(enabled: false), .forward(enabled: false)]
               && bar(.emptyPane, split: true).right == [.closePane], "an empty pane: greyed ← → and close")
        let noTab = bar(.noTab, pinned: ["a"], extensions: true)
        expect(noTab.left == [.toggleSidebar, .back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: false)]
               && noTab.right == [.pinnedExtension("a"), .extensions, .addSplit], "no tab: greyed navigation, the right end as usual")
        let dev = bar(.developer, pinned: ["a"])
        expect(dev.left == [.toggleSidebar] && dev.right == [.copyURL, .divider, .console, .network, .inspect, .pinnedExtension("a"), .addSplit],
               "the developer bar: copy · divider · Console, Network, Inspect before the right end (Arc 1.170, #88)")
    }

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
