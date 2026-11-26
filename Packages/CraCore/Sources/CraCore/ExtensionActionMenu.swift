import Foundation

/// A pinned extension's right-click menu in the toolbar (GitHub #695): Arc's, which is Chromium's
/// extension action menu (the reporter's 1Password menu in Arc 1.17x): the extension's name, its own
/// action items, the site access line, Remove from Arc and Unpin, then Manage Extension and View Web
/// Permissions. The extension's own items and Remove come through the engine (engine -20), the site access
/// line too (engine -7 of 159, `ExtensionSiteAccess`). Options is Chrome's row for an extension with an options page; Cra's icon choices
/// (Original Icon, Monochrome, Symbol, Choose Image…), which this menu used to be, close it.
public enum ExtensionActionMenu {
    public enum Row: Equatable, Sendable {
        /// The extension's name: Chrome opens its Web Store page; one that didn't come from the Web
        /// Store only names it.
        case name(String, opensWebStore: Bool)
        case separator
        /// The extension's own items (chrome.contextMenus for its action), then a separator; nothing when it has none.
        case ownItems
        /// The site access line for the page (`ExtensionSiteAccess`), then a separator; nothing when the
        /// extension asks for no site access.
        case siteAccess
        case options
        /// Remove the extension, after asking.
        case remove
        case unpin
        case manage
        case webPermissions
        case icon

        public var title: String {
            switch self {
            case .name(let name, _): name
            case .separator, .ownItems, .siteAccess: ""
            case .options: "Options"
            case .remove: "Remove from Cra"
            case .unpin: "Unpin"
            case .manage: "Manage Extension"
            case .webPermissions: "View Web Permissions"
            case .icon: "Icon"
            }
        }
    }

    public static func rows(name: String, hasOptions: Bool, fromWebStore: Bool) -> [Row] {
        [.name(name, opensWebStore: fromWebStore), .separator, .ownItems, .siteAccess]
            + (hasOptions ? [.options] : []) + [.remove, .unpin, .separator, .manage, .webPermissions, .separator, .icon]
    }

    public static func webStorePage(id: String) -> String { "https://chromewebstore.google.com/detail/\(id)" }

    /// Chrome's page for the one extension (its Remove button is there).
    public static func managePage(id: String) -> String { "chrome://extensions/?id=\(id)" }

    /// Chrome's site settings for the extension's own origin, as its View web permissions opens.
    public static func webPermissionsPage(id: String) -> String {
        "chrome://settings/content/siteDetails?site=chrome-extension%3A%2F%2F\(id)%2F"
    }

    /// options_ui.page or options_page, relative to the extension's folder.
    public static func optionsPage(id: String, path: String) -> String {
        "chrome-extension://\(id)/" + path.drop { $0 == "/" }
    }
}
