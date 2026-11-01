import Foundation

/// What a click on an extension's button does (toolbar, sidebar URL pill, Extensions menu,
/// a shortcut): MainWindowController performs it. Only an extension installed and turned on in
/// the focused page's profile runs; one turned off in chrome://extensions is out of the toolbar
/// and the menus (GitHub #41) and must not be reached from a stale button or a shortcut either.
enum ExtensionLaunch: Equatable {
    case nothing
    /// Chrome's action on the focused page; its popup hangs from the toolbar.
    case runAction
    /// No page for Chrome's popup to attach to: the popup page in a popup-sized window.
    case popupWindow(url: String)
    /// No popup at all: the options page, else Chrome's details page for the extension.
    case openTab(url: String)

    struct Extension: Equatable {
        let id: String
        var popupPath: String?
        var optionsPath: String?
        var enabled = true
    }

    /// `available`: the extensions of the focused page's profile. `hasPage`: a page and a
    /// toolbar to anchor Chrome's popup.
    static func decide(_ id: String, available: [Extension], hasPage: Bool) -> ExtensionLaunch {
        guard let e = available.first(where: { $0.id == id }), e.enabled else { return .nothing }
        return hasPage ? .runAction : fallback(e)
    }

    /// Also what follows when Chrome could not run the action on the page.
    static func fallback(_ e: Extension) -> ExtensionLaunch {
        guard e.enabled else { return .nothing }
        let base = "chrome-extension://\(e.id)/"
        if let popup = e.popupPath { return .popupWindow(url: base + popup) }
        return .openTab(url: e.optionsPath.map { base + $0 } ?? "chrome://extensions/?id=\(e.id)")
    }
}
