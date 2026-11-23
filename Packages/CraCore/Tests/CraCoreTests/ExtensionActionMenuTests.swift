import CraCore
import Testing

/// A pinned extension's right-click menu in the toolbar (GitHub #695), Arc's rows that need no engine.
struct ExtensionActionMenuTests {
    static let id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/695"))
    func arcsRowsInArcsOrder() {
        // Arc 1.17x (the reporter's 1Password menu): the name, then Unpin, then Manage Extension and
        // View Web Permissions; Options with an options page, as Chrome's menu has; Cra's icon choices last.
        #expect(ExtensionActionMenu.rows(name: "1Password", hasOptions: false, fromWebStore: true) == [
            .name("1Password", opensWebStore: true), .separator, .unpin, .separator, .manage, .webPermissions, .separator, .icon,
        ])
        #expect(ExtensionActionMenu.rows(name: "Fixture", hasOptions: true, fromWebStore: false) == [
            .name("Fixture", opensWebStore: false), .separator, .options, .unpin, .separator, .manage, .webPermissions, .separator, .icon,
        ])
        #expect(ExtensionActionMenu.Row.manage.title == "Manage Extension")
        #expect(ExtensionActionMenu.Row.webPermissions.title == "View Web Permissions")
        #expect(ExtensionActionMenu.Row.unpin.title == "Unpin")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/695"))
    func eachRowOpensChromesPage() {
        #expect(ExtensionActionMenu.webStorePage(id: Self.id) == "https://chromewebstore.google.com/detail/\(Self.id)")
        #expect(ExtensionActionMenu.managePage(id: Self.id) == "chrome://extensions/?id=\(Self.id)")
        #expect(ExtensionActionMenu.webPermissionsPage(id: Self.id) == "chrome://settings/content/siteDetails?site=chrome-extension%3A%2F%2F\(Self.id)%2F")
        #expect(ExtensionActionMenu.optionsPage(id: Self.id, path: "options.html") == "chrome-extension://\(Self.id)/options.html")
        #expect(ExtensionActionMenu.optionsPage(id: Self.id, path: "/settings/index.html") == "chrome-extension://\(Self.id)/settings/index.html")
    }
}
