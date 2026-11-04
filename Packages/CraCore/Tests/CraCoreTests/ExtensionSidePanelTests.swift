import CraCore
import Foundation
import Testing

struct ExtensionSidePanelTests {
    static let metaMask = "nkbihfbeogaeaoehlefnkodbefgpgknn"
    static let panelURL = "chrome-extension://\(metaMask)/sidepanel.html"

    static func params(_ p: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: p) }

    static func request(_ kind: ExtensionSidePanelRequest.Kind, id: String = metaMask, profile: String = "Default",
                        url: String? = nil) -> ExtensionSidePanelRequest {
        ExtensionSidePanelRequest(extensionID: id, profile: profile, kind: kind,
                                  url: url ?? (kind == .close ? "" : "chrome-extension://\(id)/sidepanel.html"), targetID: "T")
    }

    static func shown(_ id: String = metaMask, profile: String = "Default", url: String? = nil) -> ExtensionSidePanelState {
        ExtensionSidePanelState(extensionID: id, profile: profile, url: url ?? "chrome-extension://\(id)/sidepanel.html")
    }

    @Test func decodesTheEvent() throws {
        let r = try #require(ExtensionSidePanelRequest(params: Self.params([
            "id": Self.metaMask, "profile": "Profile 1", "request": "toggle", "url": Self.panelURL, "targetId": "T1",
        ])))
        #expect(r == ExtensionSidePanelRequest(extensionID: Self.metaMask, profile: "Profile 1", kind: .toggle,
                                               url: Self.panelURL, targetID: "T1"))
    }

    @Test func closeNeedsNoPage() throws {
        let r = try #require(ExtensionSidePanelRequest(params: Self.params([
            "id": Self.metaMask, "profile": "Default", "request": "close", "url": "", "targetId": "T1",
        ])))
        #expect(r.kind == .close)
    }

    /// A panel only ever shows the asking extension's own pages.
    @Test(arguments: [
        "https://evil.example/sidepanel.html",
        "chrome-extension://otherextensionid/sidepanel.html",
        "chrome://settings",
        "",
    ])
    func refusesPagesThatAreNotTheExtensions(_ url: String) {
        #expect(ExtensionSidePanelRequest(params: Self.params([
            "id": Self.metaMask, "profile": "Default", "request": "open", "url": url, "targetId": "T1",
        ])) == nil)
    }

    @Test func refusesUnknownRequestsAndMissingFields() {
        #expect(ExtensionSidePanelRequest(params: Self.params([
            "id": Self.metaMask, "profile": "Default", "request": "pin", "url": Self.panelURL, "targetId": "T1",
        ])) == nil)
        #expect(ExtensionSidePanelRequest(params: Self.params([
            "id": Self.metaMask, "profile": "Default", "request": "open", "url": Self.panelURL,
        ])) == nil)
        #expect(ExtensionSidePanelRequest(params: Data("nope".utf8)) == nil)
    }

    // MetaMask's toolbar button (openPanelOnActionClick): a click opens the panel, the next closes it.
    @Test func toggleOpensThenCloses() {
        let toggle = Self.request(.toggle)
        #expect(toggle.change(from: nil) == .show(Self.shown()))
        #expect(toggle.change(from: Self.shown()) == .hide)
    }

    @Test func toggleReplacesAnotherExtensionsPanel() {
        #expect(Self.request(.toggle).change(from: Self.shown("other")) == .show(Self.shown()))
    }

    /// Same extension, another profile's copy: a different panel (its own storage and accounts).
    @Test func anotherProfileIsAnotherPanel() {
        #expect(Self.request(.toggle).change(from: Self.shown(profile: "Profile 1")) == .show(Self.shown()))
        #expect(Self.request(.close).change(from: Self.shown(profile: "Profile 1")) == .none)
    }

    @Test func openShowsOrKeepsOrNavigates() {
        let open = Self.request(.open)
        #expect(open.change(from: nil) == .show(Self.shown()))
        #expect(open.change(from: Self.shown()) == .none)
        let other = "chrome-extension://\(Self.metaMask)/other.html"
        #expect(Self.request(.open, url: other).change(from: Self.shown()) == .show(Self.shown(url: other)))
    }

    @Test func closeOnlyHidesItsOwnPanel() {
        let close = Self.request(.close)
        #expect(close.change(from: Self.shown()) == .hide)
        #expect(close.change(from: Self.shown("other")) == .none)
        #expect(close.change(from: nil) == .none)
    }

    @Test func widthStaysWithinLimitsAndLeavesThePageRoom() {
        typealias W = ExtensionSidePanelWidth
        #expect(W.clamp(360, container: 1400, gap: 10) == 360)
        #expect(W.clamp(100, container: 1400, gap: 10) == W.minimum)
        #expect(W.clamp(2000, container: 1400, gap: 10) == W.maximum)
        // 900 pt of content: the page keeps 400 beside a 10 pt gap.
        #expect(W.clamp(600, container: 900, gap: 10) == 490)
        #expect(W.fits(container: 730, gap: 10))
        #expect(!W.fits(container: 729, gap: 10))
    }

    /// A split keeps every pane at its minimum: three side-by-side panes of 200 pt and two 10 pt
    /// gaps need 620 pt, so the panel only shows from 950 pt of content.
    @Test func splitPanesKeepTheirMinimum() {
        typealias W = ExtensionSidePanelWidth
        #expect(W.pageMinimum(panes: 1, paneMinimum: 200, gap: 10) == 400)
        #expect(W.pageMinimum(panes: 2, paneMinimum: 200, gap: 10) == 410)
        let three = W.pageMinimum(panes: 3, paneMinimum: 200, gap: 10)
        #expect(three == 620)
        #expect(!W.fits(container: 762, gap: 10, pages: three))
        #expect(W.fits(container: 950, gap: 10, pages: three))
        #expect(W.clamp(360, container: 1000, gap: 10, pages: three) == 360)
        #expect(W.clamp(500, container: 1000, gap: 10, pages: three) == 370)
        // Stacked panes share the width, so they need only a page's minimum.
        #expect(W.pageMinimum(panes: 3, paneMinimum: 200, gap: 10, sideBySide: false) == 400)
    }
}
