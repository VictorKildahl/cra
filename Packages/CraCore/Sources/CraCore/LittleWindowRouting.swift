import Foundation

/// What a key Little Window does with a menu or key action (#333). Before, every action it didn't
/// handle fell through to the browser window behind it, so Window ▸ Stay On Top floated that window
/// and Share…, Save Page As… and the rest took its selected tab.
public enum LittleWindowRouting {
    public enum Route: Equatable, Sendable {
        /// The Little Window does it, to its own page or window.
        case window
        /// It has no such thing (a find bar, a sidebar, tabs, split view): nothing happens.
        case ignored
        /// Not about a page or a window of its own: the app answers it.
        case app
    }

    /// Handled by a Little Window and by a Peek: close, reload, back and forward, zoom, Copy URL,
    /// developer tools, print, ⌘O, ⇧⌘O and Move Tab to Space N.
    static let sharedWindow: Set<String> = [
        "closeTab", "closeWindow", "newTab", "editURL", "goBack", "goForward", "reload", "hardReload", "clearCache",
        "clearCookies", "stop", "zoomIn", "zoomOut", "resetZoom", "copyURL", "copyURLMarkdown", "viewSource", "devTools",
        "jsConsole", "inspectElement", "print", "capturePage", "promoteLittleWindow", "littleWindowOpenInMenu",
    ]

    /// Commands on the page and window of a Little Window, which used to reach the browser window's. A Peek
    /// is a card over the browser window, whose page is the one under it, so it leaves them to the app.
    public static let ownPage: Set<String> = [
        "stayOnTop", "share", "savePageAs", "captureFullPage", "capturePortrait", "copyURLQuote", "jumpToSelection",
        "pictureInPicture", "cast", "taskManager", "toggleDeveloperMode", "networkPanel",
    ]

    /// Ignored since the Little Window began: no find bar, sidebar, tab list or pinned section, in a Peek either.
    static let ignoredFromTheStart: Set<String> = [
        "find", "findNext", "findPrevious", "toggleSidebar", "pinTab", "favoriteTab", "renameTab", "duplicateTab",
        "resetTab", "muteTab", "clearToday", "nextTab", "previousTab", "recentTab", "recentTabBackward",
    ]

    /// What they did to the browser window's selected tab, sidebar or split view, a Little Window has none of.
    /// Their menu rows are off while one is in front; the commands ignored from the start keep theirs.
    public static let ignoredInLittleWindow: Set<String> = [
        "useSelectionForFind", "revealTab", "resetSpaceTabs", "collapsePinned", "collapseAllFolders", "expandAllFolders",
        "newFolder", "newBoost", "openExtensions", "addSplitView", "closeSplitPane", "separateFromSplit",
        "flipSplitOrientation", "nextSplitPane", "previousSplitPane",
    ]

    /// Windows, settings, the Library, spaces, appearance and updates.
    static let app: Set<String> = [
        "newWindow", "newBlankWindow", "newIncognitoWindow", "newLittleWindow", "reopenClosedTab", "newSpace", "newProfile",
        "newEasel", "toggleToolbar", "appearanceAutomatic", "appearanceLight", "appearanceDark", "allowAppleEventsJavaScript",
        "closeLittleWindows", "settings", "setDefaultBrowser", "importData", "rebuildArcProfiles", "clearBrowsingData",
        "languageSettings", "checkForUpdates", "essentialShortcuts", "revealData", "copyAppInfo", "viewArchive", "showArchive",
        "clearArchive", "openLibrary", "viewDownloads", "viewBoosts", "viewEasels", "viewMedia", "joinNextMeeting",
        "nextSpace", "previousSpace", "editSpace", "changeProfile", "deleteSpace", "manageSpaces", "manageExtensions",
    ]

    /// `item1`…`item9` (Go to Tab), `splitPane1`…`4`, `space1`…`9` and `moveTabToSpace1`…`9`.
    private static func numbered(_ id: String, _ prefix: String) -> Bool {
        id.hasPrefix(prefix) && Int(id.dropFirst(prefix.count)) != nil
    }

    /// Whether `id` has been decided on: every action the app lists must be (Tests/KeyBindingsTests).
    public static func isClassified(_ id: String) -> Bool {
        sharedWindow.contains(id) || ownPage.contains(id) || ignoredFromTheStart.contains(id)
            || ignoredInLittleWindow.contains(id) || app.contains(id)
            || numbered(id, "moveTabToSpace") || numbered(id, "item") || numbered(id, "splitPane") || numbered(id, "space")
    }

    public static func route(_ id: String, inPeek: Bool = false) -> Route {
        if sharedWindow.contains(id) || numbered(id, "moveTabToSpace") { return .window }
        if ignoredFromTheStart.contains(id) { return .ignored }
        if inPeek { return .app }
        if ownPage.contains(id) { return .window }
        if ignoredInLittleWindow.contains(id) || numbered(id, "item") || numbered(id, "splitPane") { return .ignored }
        return .app
    }
}
