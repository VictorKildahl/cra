import CraCore
import Testing

/// What a key Little Window does with a menu or key action, so that nothing about a browser window's
/// own page, tab or window reaches the browser window behind it (#333).
struct LittleWindowRoutingTests {
    /// Window ▸ Stay On Top floated the browser window and left the Little Window as it was; Share…,
    /// Save Page As… and the rest took the browser window's selected tab. The Little Window does each
    /// to its own page or window.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/333"))
    func commandsOnAPageAreTheLittleWindowsOwn() {
        for id in ["stayOnTop", "share", "savePageAs", "captureFullPage", "capturePortrait", "copyURLQuote",
                   "jumpToSelection", "pictureInPicture", "cast", "taskManager", "toggleDeveloperMode", "networkPanel"] {
            #expect(LittleWindowRouting.route(id) == .window, "\(id)")
            #expect(LittleWindowRouting.ownPage.contains(id), "\(id)")
        }
    }

    /// The tab list, split view, sidebar and find bar: a Little Window has none, so what they do to the
    /// browser window's selected tab or sidebar it doesn't pass on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/333"))
    func commandsOnTabsSplitsAndTheSidebarAreIgnored() {
        for id in ["useSelectionForFind", "revealTab", "resetSpaceTabs", "collapsePinned", "collapseAllFolders",
                   "expandAllFolders", "newFolder", "newBoost", "openExtensions", "addSplitView", "closeSplitPane",
                   "separateFromSplit", "flipSplitOrientation", "nextSplitPane", "previousSplitPane",
                   "item1", "item9", "splitPane1", "splitPane4"] {
            #expect(LittleWindowRouting.route(id) == .ignored, "\(id)")
            #expect(LittleWindowRouting.ignoredInLittleWindow.contains(id) || id.hasPrefix("item") || id.hasPrefix("splitPane"), "\(id)")
        }
    }

    /// Ignored since the Little Window began, and the same in a Peek: there is no find bar, sidebar or
    /// tab list. Their menu rows stay as they were.
    @Test func findAndSidebarCommandsStayIgnoredInBoth() {
        for id in ["find", "findNext", "findPrevious", "toggleSidebar", "pinTab", "favoriteTab", "renameTab", "duplicateTab",
                   "resetTab", "muteTab", "clearToday", "nextTab", "previousTab", "recentTab", "recentTabBackward"] {
            #expect(LittleWindowRouting.route(id) == .ignored, "\(id)")
            #expect(LittleWindowRouting.route(id, inPeek: true) == .ignored, "\(id)")
            #expect(!LittleWindowRouting.ignoredInLittleWindow.contains(id), "\(id)")
        }
    }

    /// A Peek is a card over the browser window, whose page is the one under it: what it never handled
    /// still goes to the app, as before.
    @Test func aPeekStillPassesThePageCommandsOn() {
        for id in ["stayOnTop", "share", "savePageAs", "pictureInPicture", "useSelectionForFind", "addSplitView", "item3"] {
            #expect(LittleWindowRouting.route(id, inPeek: true) == .app, "\(id)")
        }
    }

    /// What the window did itself from the start, in a Little Window and in a Peek.
    @Test func whatTheWindowAlreadyDoesStaysItsOwn() {
        for id in ["closeTab", "closeWindow", "newTab", "editURL", "goBack", "goForward", "reload", "hardReload",
                   "clearCache", "clearCookies", "stop", "zoomIn", "zoomOut", "resetZoom", "copyURL", "copyURLMarkdown",
                   "viewSource", "devTools", "jsConsole", "inspectElement", "print", "capturePage", "promoteLittleWindow",
                   "littleWindowOpenInMenu", "moveTabToSpace1", "moveTabToSpace9"] {
            #expect(LittleWindowRouting.route(id) == .window, "\(id)")
            #expect(LittleWindowRouting.route(id, inPeek: true) == .window, "\(id)")
        }
    }

    /// Windows, settings, the Library, spaces and the rest belong to the app, in front or not.
    @Test func appCommandsStayWithTheApp() {
        for id in ["newWindow", "newLittleWindow", "newSpace", "settings", "checkForUpdates", "openLibrary", "nextSpace", "space2"] {
            #expect(LittleWindowRouting.route(id) == .app, "\(id)")
            #expect(LittleWindowRouting.isClassified(id), "\(id)")
        }
        #expect(!LittleWindowRouting.isClassified("aCommandNobodyDecidedOn"))
    }
}
