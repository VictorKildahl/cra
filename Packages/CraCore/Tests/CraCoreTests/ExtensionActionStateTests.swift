import CraCore
import Foundation
import Testing

struct ExtensionActionStateTests {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    static let other = Data([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 1])

    static func params(_ p: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: p) }

    static func update(_ id: String = "ext", profile: String = "Default", target: String? = nil,
                       icon: Data? = nil, title: String = "") -> ExtensionActionUpdate {
        ExtensionActionUpdate(extensionID: id, profile: profile, targetID: target,
                              state: ExtensionActionState(icon: icon, title: title))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func decodesTheEvent() throws {
        let u = try #require(ExtensionActionUpdate(params: Self.params([
            "id": "abc", "profile": "Profile 1", "targetId": "T1",
            "icon": "data:image/png;base64," + Self.png.base64EncodedString(),
            "title": "Omega: auto", "badgeText": "3", "badgeColor": "#FF0000FF", "badgeTextColor": "#FFFFFFFF",
        ])))
        #expect(u.extensionID == "abc")
        #expect(u.profile == "Profile 1")
        #expect(u.targetID == "T1")
        #expect(u.state == ExtensionActionState(icon: Self.png, title: "Omega: auto", badgeText: "3", badgeColor: "#FF0000FF",
                                                badgeTextColor: "#FFFFFFFF"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func everyTabEventHasNoTarget() throws {
        let u = try #require(ExtensionActionUpdate(params: Self.params(["id": "abc", "profile": "Default", "icon": ""])))
        #expect(u.targetID == nil)
        #expect(u.state.isEmpty)
    }

    @Test(arguments: [
        // Not PNG, or not a data URL: Chromium only sends PNG data URLs.
        "data:image/svg+xml;base64,PHN2Zy8+",
        "https://example.com/icon.png",
        "data:image/png;base64,not base64!",
    ])
    func ignoresIconsThatAreNotPNGs(icon: String) throws {
        let u = try #require(ExtensionActionUpdate(params: Self.params(["id": "abc", "profile": "Default", "icon": icon])))
        #expect(u.state.icon == nil)
    }

    @Test func ignoresIconsFarLargerThanAToolbarIcon() throws {
        let icon = "data:image/png;base64," + Data(count: 300 * 1024).base64EncodedString()
        let u = try #require(ExtensionActionUpdate(params: Self.params(["id": "abc", "profile": "Default", "icon": icon])))
        #expect(u.state.icon == nil)
    }

    @Test(arguments: [
        ["profile": "Default"],
        ["id": "", "profile": "Default"],
        ["id": "abc"],
    ] as [[String: String]])
    func rejectsOtherParams(p: [String: String]) {
        #expect(ExtensionActionUpdate(params: Self.params(p)) == nil)
    }

    @Test func nothingReportedIsEmpty() {
        #expect(ExtensionActionStates().state(extensionID: "ext", profile: "Default", tab: UUID()).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func everyTabValueAppliesToEachTabInItsProfile() {
        var s = ExtensionActionStates()
        s.apply(Self.update(icon: Self.png), tab: nil)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: UUID()).icon == Self.png)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: nil).icon == Self.png)
        // The same extension in another profile has its own action.
        #expect(s.state(extensionID: "ext", profile: "Profile 1", tab: nil).icon == nil)
        #expect(s.state(extensionID: "other", profile: "Default", tab: nil).icon == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func aTabsOwnValueWinsValueByValue() {
        var s = ExtensionActionStates()
        let tab = UUID(), elsewhere = UUID()
        s.apply(Self.update(icon: Self.png, title: "On"), tab: nil)
        // AdGuard: setIcon({path: off}, tabId) on an allowlisted site, title untouched.
        s.apply(Self.update(target: "T", icon: Self.other), tab: tab)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: tab) == ExtensionActionState(icon: Self.other, title: "On"))
        #expect(s.state(extensionID: "ext", profile: "Default", tab: elsewhere).icon == Self.png)
        // A later change for every tab shows through where the tab set nothing of its own.
        s.apply(Self.update(icon: Self.png, title: "Paused"), tab: nil)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: tab) == ExtensionActionState(icon: Self.other, title: "Paused"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func aNavigationThatClearsTheTabFallsBack() {
        var s = ExtensionActionStates()
        let tab = UUID()
        s.apply(Self.update(icon: Self.png), tab: nil)
        s.apply(Self.update(target: "T", icon: Self.other), tab: tab)
        s.apply(Self.update(target: "T"), tab: tab)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: tab).icon == Self.png)
        #expect(s == {
            var only = ExtensionActionStates()
            only.apply(Self.update(icon: Self.png), tab: nil)
            return only
        }())
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func anEmptyEveryTabStateGoesBackToTheManifest() {
        var s = ExtensionActionStates()
        s.apply(Self.update(icon: Self.png), tab: nil)
        s.apply(Self.update(), tab: nil)
        #expect(s == ExtensionActionStates())
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func closedTabsAreForgotten() {
        var s = ExtensionActionStates()
        let open = UUID(), closed = UUID()
        s.apply(Self.update(target: "A", icon: Self.png), tab: open)
        s.apply(Self.update(target: "B", icon: Self.png), tab: closed)
        s.removeTab(closed)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: open).icon == Self.png)
        #expect(s.state(extensionID: "ext", profile: "Default", tab: closed).icon == nil)
    }
}
