import AppKit
import Observation

/// A keyboard shortcut: CraCore's KeyChord (the keybindings.json format), read from and
/// matched against AppKit key events here.
typealias Shortcut = KeyChord

extension Shortcut {
    init(_ key: String, _ mods: NSEvent.ModifierFlags) {
        self.init(key: key, modifiers: mods.intersection(.deviceIndependentFlagsMask).rawValue)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// The key press an event is, for CraCore's matching (KeyChord.match). Nil for anything but a
    /// key-down: charactersIgnoringModifiers throws on flagsChanged events, which Chromium
    /// forwards as raw key-downs for modifier keys.
    static func press(_ event: NSEvent) -> KeyChord.Press? {
        guard event.type == .keyDown, let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        return KeyChord.Press(characters: chars, keyCode: event.keyCode,
                              modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
    }

    @MainActor func matches(_ event: NSEvent) -> Bool {
        guard let press = Self.press(event) else { return false }
        return match(press, typable: KeyboardLayoutCharacters.types) != nil
    }

    /// Build a shortcut from a recorded key press (nil for bare letters without ⌘/⌃/⌥).
    static func from(event e: NSEvent) -> Shortcut? {
        guard let chars = press(e)?.key else { return nil }
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let special = [tab, left, right, up, down].contains(chars) || (chars.unicodeScalars.first.map { $0.value >= 0xF704 && $0.value <= 0xF71F } ?? false)
        guard special || !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return Shortcut(chars, flags)
    }
}

enum MenuSection: String, Codable {
    case app, file, edit, view, tabs, spaces, archive, window, help, none
}

/// An app command. Arc keeps the same shape: identifier + name + default
/// shortcut + the phrases type-travel matches ("typeTravelTriggers").
struct KeyAction: Identifiable, Hashable {
    let id: String
    let name: String
    let section: MenuSection
    var shortcuts: [Shortcut]
    var triggers: [String] = []
    var inCommandBar: Bool = true
    /// The command bar row's glyph, where Arc gives the command its own (else ⌘).
    var symbol: String? = nil

    var primary: Shortcut? { shortcuts.first }
}

/// The action table plus user overrides (keybindings.json).
@MainActor
@Observable
final class KeyBindingRegistry {
    /// The app's one registry (AppDelegate.bindings), for the context menus' shortcut glyphs.
    static let shared = KeyBindingRegistry()

    private(set) var actions: [KeyAction]
    @ObservationIgnored private let overridesFile = JSONStore<[String: [Shortcut]]>("keybindings.json")
    @ObservationIgnored private var overrides: [String: [Shortcut]]

    init() {
        actions = KeyBindingRegistry.defaults
        overrides = overridesFile.load(or: { [:] })
        apply()
    }

    private func apply() {
        for i in actions.indices {
            if let o = overrides[actions[i].id] { actions[i].shortcuts = o }
        }
    }

    func action(_ id: String) -> KeyAction? { actions.first { $0.id == id } }

    func setShortcuts(_ shortcuts: [Shortcut], for id: String) {
        overrides[id] = shortcuts
        overridesFile.save(overrides)
        apply()
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    func isOverridden(_ id: String) -> Bool { overrides[id] != nil }

    func resetShortcuts(for id: String) {
        overrides[id] = nil
        overridesFile.save(overrides)
        if let d = KeyBindingRegistry.defaults.first(where: { $0.id == id }), let i = actions.firstIndex(where: { $0.id == id }) {
            actions[i].shortcuts = d.shortcuts
        }
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    func resetOverrides() {
        overrides = [:]
        overridesFile.saveNow(overrides)
        actions = KeyBindingRegistry.defaults
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    /// The action a key press runs: the first one whose shortcut it types, else the first one
    /// whose key sits where the press's does (KeyChord.first).
    func action(for event: NSEvent) -> KeyAction? {
        guard let press = Shortcut.press(event) else { return nil }
        return KeyChord.first(in: actions, chords: \.shortcuts, press: press, typable: KeyboardLayoutCharacters.types)
    }

    func actions(in section: MenuSection) -> [KeyAction] { actions.filter { $0.section == section } }

    // Arc's defaults, read from Arc 1.168's menu bar on this Mac (see
    // docs/arc-reverse-engineering.md, "Key bindings"). Items Cra doesn't
    // have (Little Arc, Easels, Split View, Capture) are left out.
    static let defaults: [KeyAction] = {
        let cmd: NSEvent.ModifierFlags = .command
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        let cmdOpt: NSEvent.ModifierFlags = [.command, .option]
        let cmdOptShift: NSEvent.ModifierFlags = [.command, .option, .shift]
        var list: [KeyAction] = [
            // File
            KeyAction(id: "newTab", name: "New Tab…", section: .file, shortcuts: [Shortcut("t", cmd)], triggers: ["new tab"]),
            KeyAction(id: "newWindow", name: "New Window", section: .file, shortcuts: [Shortcut("n", cmd)], inCommandBar: false),
            // Arc: File ▸ Blank Window ⌃⌘N, a window with a sidebar of its own (#220).
            KeyAction(id: "newBlankWindow", name: "Blank Window", section: .file, shortcuts: [Shortcut("n", [.command, .control])],
                      triggers: ["blank window", "this window"]),
            KeyAction(id: "newIncognitoWindow", name: "New Incognito Window", section: .file, shortcuts: [Shortcut("n", cmdShift)],
                      triggers: ["incognito", "private"]),
            // Arc: File ▸ New Little Arc Window ⌥⌘N.
            KeyAction(id: "newLittleWindow", name: "New Little Window", section: .file, shortcuts: [Shortcut("n", cmdOpt)], triggers: ["little window", "little arc"]),
            KeyAction(id: "reopenClosedTab", name: "Restore Last Closed Tab", section: .file, shortcuts: [Shortcut("t", cmdShift)], triggers: ["reopen", "undo close", "restore"]),
            KeyAction(id: "editURL", name: "Open Command Bar", section: .file, shortcuts: [Shortcut("l", cmd)], triggers: ["url", "address", "command bar"]),
            KeyAction(id: "newFolder", name: "New Folder", section: .file, shortcuts: [], triggers: ["folder"]),
            KeyAction(id: "newGitHubLiveFolder", name: "New GitHub Live Folder", section: .file, shortcuts: [],
                      triggers: ["live folder", "pull requests", "github"]),
            KeyAction(id: "newSpace", name: "New Space…", section: .file, shortcuts: [], triggers: ["space"]),
            KeyAction(id: "closeWindow", name: "Close Window", section: .file, shortcuts: [Shortcut("w", cmdShift)], inCommandBar: false),
            KeyAction(id: "closeTab", name: "Close Tab", section: .file, shortcuts: [Shortcut("w", cmd)], triggers: ["close", "archive tab"]),
            KeyAction(id: "capturePage", name: "Capture…", section: .file, shortcuts: [Shortcut("2", cmdShift)], triggers: ["capture", "screenshot"]),
            // Arc: File ▸ Capture Full Page, Save Page As ⇧⌘S.
            KeyAction(id: "captureFullPage", name: "Capture Full Page", section: .file, shortcuts: [], triggers: ["full page", "screenshot"]),
            KeyAction(id: "capturePortrait", name: "Capture in Portrait Mode", section: .file, shortcuts: [], triggers: ["portrait", "mobile screenshot"]),
            KeyAction(id: "savePageAs", name: "Save Page As…", section: .file, shortcuts: [Shortcut("s", cmdShift)], triggers: ["save page", "download page"]),
            KeyAction(id: "print", name: "Print", section: .file, shortcuts: [Shortcut("p", cmd)]),
            // Edit
            KeyAction(id: "copyURL", name: "Copy URL", section: .edit, shortcuts: [Shortcut("c", cmdShift)], triggers: ["copy link"]),
            KeyAction(id: "copyURLMarkdown", name: "Copy URL as Markdown", section: .edit, shortcuts: [Shortcut("c", cmdOptShift)], triggers: ["markdown"]),
            // Arc: Edit ▸ Copy URL as Quote ⌃⇧⌘C, the selection with a link to it.
            KeyAction(id: "copyURLQuote", name: "Copy URL as Quote", section: .edit, shortcuts: [Shortcut("c", [.command, .shift, .control])], triggers: ["quote", "highlight"]),
            KeyAction(id: "find", name: "Find…", section: .edit, shortcuts: [Shortcut("f", cmd)], triggers: ["find", "search page"]),
            KeyAction(id: "findNext", name: "Find Next", section: .edit, shortcuts: [Shortcut("g", cmd)], inCommandBar: false),
            KeyAction(id: "findPrevious", name: "Find Previous", section: .edit, shortcuts: [Shortcut("g", cmdShift)], inCommandBar: false),
            // View
            KeyAction(id: "toggleSidebar", name: "Hide Sidebar", section: .view, shortcuts: [Shortcut("s", cmd)], triggers: ["sidebar", "hide sidebar", "show sidebar"]),
            KeyAction(id: "toggleToolbar", name: "Hide Toolbar", section: .view, shortcuts: [Shortcut("d", cmdShift)], triggers: ["toolbar"]),
            // Arc: View ▸ Appearance, what websites see (Websites, Easels, and Notes will use:).
            KeyAction(id: "appearanceAutomatic", name: "Website Appearance: Automatic", section: .none, shortcuts: [], triggers: ["website appearance", "system appearance"], symbol: "circle.lefthalf.filled"),
            KeyAction(id: "appearanceLight", name: "Website Appearance: Light", section: .none, shortcuts: [], triggers: ["light mode", "light websites"], symbol: "sun.max"),
            KeyAction(id: "appearanceDark", name: "Website Appearance: Dark", section: .none, shortcuts: [], triggers: ["dark mode", "dark websites"], symbol: "moon"),
            // Arc: View ▸ Collapse Pinned Tabs / Expand Pinned Tabs.
            KeyAction(id: "collapsePinned", name: "Collapse Pinned Tabs", section: .view, shortcuts: [], triggers: ["collapse pinned", "expand pinned"]),
            KeyAction(id: "stop", name: "Stop Loading", section: .view, shortcuts: [Shortcut(".", cmd)], inCommandBar: false),
            KeyAction(id: "reload", name: "Refresh the Page", section: .view, shortcuts: [Shortcut("r", cmd)], triggers: ["refresh", "reload"]),
            KeyAction(id: "hardReload", name: "Force Refresh the Page", section: .view, shortcuts: [Shortcut("r", cmdShift)]),
            // Arc's command bar (1.171): "clear" lists both, cache first, with a trash glyph.
            KeyAction(id: "clearCache", name: "Clear Cache and Refresh", section: .view, shortcuts: [], symbol: "trash"),
            KeyAction(id: "clearCookies", name: "Clear Cookies and Refresh", section: .view, shortcuts: [], symbol: "trash"),
            // Arc: View ▸ Developer ▸ "Turn on/off Developer Mode for this site" (⌃D).
            KeyAction(id: "toggleDeveloperMode", name: "Toggle Developer Mode for this Site", section: .view, shortcuts: [Shortcut("d", .control)], triggers: ["developer mode", "dev mode"]),
            KeyAction(id: "resetZoom", name: "Zoom to Actual Size", section: .view, shortcuts: [Shortcut("0", cmd)], triggers: ["reset zoom"]),
            KeyAction(id: "zoomIn", name: "Zoom In", section: .view, shortcuts: [Shortcut("=", cmd), Shortcut("=", cmdShift)]),
            KeyAction(id: "zoomOut", name: "Zoom Out", section: .view, shortcuts: [Shortcut("-", cmd)]),
            KeyAction(id: "viewSource", name: "View Source", section: .view, shortcuts: [Shortcut("u", cmdOpt)]),
            KeyAction(id: "devTools", name: "Developer Tools", section: .view, shortcuts: [Shortcut("i", cmdOpt), Shortcut(Shortcut.f12, [])], triggers: ["devtools", "inspect", "console"]),
            KeyAction(id: "inspectElement", name: "Inspect Elements", section: .view, shortcuts: [Shortcut("c", cmdOpt)], inCommandBar: false),
            KeyAction(id: "jsConsole", name: "JavaScript Console", section: .view, shortcuts: [Shortcut("j", cmdOpt)], inCommandBar: false),
            // Arc: Extensions ▸ Picture in Picture (no shortcut); "Open Picture in Picture" in the command bar.
            // Arc: View ▸ Cast; Help ▸ Troubleshooting ▸ Open Task Manager. Chrome's own.
            KeyAction(id: "cast", name: "Cast…", section: .view, shortcuts: [], triggers: ["cast", "chromecast", "airplay"]),
            KeyAction(id: "taskManager", name: "Open Task Manager", section: .help, shortcuts: [], triggers: ["task manager", "memory", "processes"]),
            KeyAction(id: "pictureInPicture", name: "Picture in Picture", section: .view, shortcuts: [], triggers: ["pip", "picture in picture", "pop out", "popout", "video"]),
            // Arc: View ▸ Add Split View ⌃⇧=, Close this Split Pane ⌃⇧-, Separate Page from Split View, Expand Current Split.
            KeyAction(id: "addSplitView", name: "Add Split View", section: .view, shortcuts: [Shortcut("=", [.control, .shift])], triggers: ["split", "split view", "add split"]),
            KeyAction(id: "closeSplitPane", name: "Close this Split Pane", section: .view, shortcuts: [Shortcut("-", [.control, .shift])], triggers: ["close split", "close pane"]),
            KeyAction(id: "separateFromSplit", name: "Separate Page from Split View", section: .view, shortcuts: [], triggers: ["separate", "unsplit"]),
            KeyAction(id: "flipSplitOrientation", name: "Flip Split View Orientation", section: .view, shortcuts: [], triggers: ["vertical split", "horizontal split", "flip split"]),
            KeyAction(id: "nextSplitPane", name: "Switch to Next Split View", section: .view, shortcuts: [], inCommandBar: false),
            KeyAction(id: "previousSplitPane", name: "Switch to Previous Split View", section: .view, shortcuts: [], inCommandBar: false),
            // Spaces
            KeyAction(id: "nextSpace", name: "Next Space", section: .spaces, shortcuts: [Shortcut(Shortcut.right, cmdOpt)], inCommandBar: false),
            KeyAction(id: "previousSpace", name: "Previous Space", section: .spaces, shortcuts: [Shortcut(Shortcut.left, cmdOpt)], inCommandBar: false),
            KeyAction(id: "editSpace", name: "Edit Space…", section: .spaces, shortcuts: [], triggers: ["theme", "color", "emoji", "edit space"]),
            KeyAction(id: "changeProfile", name: "Change Profile", section: .spaces, shortcuts: [], triggers: ["profile", "change profile", "set profile"]),
            KeyAction(id: "deleteSpace", name: "Delete Space…", section: .spaces, shortcuts: [], triggers: ["delete space", "remove space"]),
            KeyAction(id: "manageSpaces", name: "Manage Spaces…", section: .spaces, shortcuts: [], triggers: ["manage spaces", "reorder spaces"]),
            // Tabs
            KeyAction(id: "pinTab", name: "Pin/Unpin Tab", section: .tabs, shortcuts: [Shortcut("d", cmd)], triggers: ["pin", "unpin"]),
            // Arc: Next Tab ⌥⌘↓ and ⌘}, Previous Tab ⌥⌘↑ and ⌘{ (Settings ▸ Shortcuts).
            KeyAction(id: "nextTab", name: "Next Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.down, cmdOpt), Shortcut("]", cmdShift)], inCommandBar: false),
            KeyAction(id: "previousTab", name: "Previous Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.up, cmdOpt), Shortcut("[", cmdShift)], inCommandBar: false),
            // Arc: Tabs ▸ Reveal Tab in Sidebar; Reveal Current Tab ⌃Space.
            KeyAction(id: "revealTab", name: "Reveal Tab in Sidebar", section: .tabs, shortcuts: [Shortcut(Shortcut.space, .control)], triggers: ["reveal", "find tab"]),
            KeyAction(id: "recentTab", name: "Next Recent Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.tab, .control)], inCommandBar: false),
            KeyAction(id: "recentTabBackward", name: "Previous Recent Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.tab, [.control, .shift])], inCommandBar: false),
            KeyAction(id: "clearToday", name: "Clear Today", section: .tabs, shortcuts: [Shortcut("k", cmdShift)], triggers: ["clear", "tidy"]),
            KeyAction(id: "favoriteTab", name: "Add to Favorites", section: .tabs, shortcuts: [], triggers: ["favorite", "top app"]),
            KeyAction(id: "renameTab", name: "Rename Tab…", section: .tabs, shortcuts: [], triggers: ["rename"]),
            KeyAction(id: "duplicateTab", name: "Duplicate Tab", section: .tabs, shortcuts: [], triggers: ["duplicate"]),
            KeyAction(id: "resetTab", name: "Reset Pinned Tab", section: .tabs, shortcuts: [], triggers: ["reset", "home"]),
            KeyAction(id: "muteTab", name: "Mute / Unmute Tab", section: .tabs, shortcuts: [], triggers: ["mute"]),
            KeyAction(id: "resetSpaceTabs", name: "Reset all tabs in this Space", section: .tabs, shortcuts: [], triggers: ["reset all", "reset pinned"]),
            // Arc lists these in Settings ▸ Shortcuts and the command bar only.
            KeyAction(id: "collapseAllFolders", name: "Collapse All Folders", section: .none, shortcuts: [], triggers: ["collapse folders", "close folders"]),
            KeyAction(id: "expandAllFolders", name: "Expand All Folders", section: .none, shortcuts: [], triggers: ["expand folders", "open folders"]),
            KeyAction(id: "manageExtensions", name: "Manage Extensions…", section: .none, shortcuts: [], triggers: ["manage extensions", "chrome extensions"], symbol: "puzzlepiece.extension"),
            KeyAction(id: "openExtensions", name: "Open Extensions", section: .none, shortcuts: [Shortcut("e", cmd)], triggers: ["extensions", "site controls"]),
            // Archive
            KeyAction(id: "goBack", name: "Go Back", section: .archive, shortcuts: [Shortcut("[", cmd), Shortcut(Shortcut.left, cmd)]),
            KeyAction(id: "goForward", name: "Go Forward", section: .archive, shortcuts: [Shortcut("]", cmd), Shortcut(Shortcut.right, cmd)]),
            KeyAction(id: "viewArchive", name: "View History", section: .archive, shortcuts: [Shortcut("y", cmd)], triggers: ["archive", "history", "closed tabs"]),
            // Arc: Archive ▸ View Archive…, Clear Archive.
            KeyAction(id: "showArchive", name: "View Archive…", section: .archive, shortcuts: [], triggers: ["archive", "archived tabs"]),
            KeyAction(id: "clearArchive", name: "Clear Archive", section: .archive, shortcuts: [], triggers: ["clear archive"], symbol: "trash"),
            // Window
            KeyAction(id: "openLibrary", name: "Open Library…", section: .window, shortcuts: [Shortcut("l", cmdShift)], triggers: ["library"]),
            KeyAction(id: "viewDownloads", name: "View Downloads…", section: .window, shortcuts: [Shortcut("j", cmdShift)], triggers: ["downloads"]),
            // Arc: Window ▸ View Media….
            KeyAction(id: "viewMedia", name: "View Media…", section: .window, shortcuts: [], triggers: ["media", "screenshots", "photos"]),
            // Arc: Window ▸ Stay On Top.
            KeyAction(id: "stayOnTop", name: "Stay On Top", section: .window, shortcuts: [], triggers: ["stay on top", "float", "always on top", "pin window"]),
            // Arc's Little Arc "Open in Space" button (LittleBrowserMoveButton) and "Close Little Arc Windows".
            KeyAction(id: "promoteLittleWindow", name: "Open Little Window in Space", section: .window, shortcuts: [Shortcut("o", cmd)], inCommandBar: false),
            // Arc: Show Little Arc "Open In" Menu ⇧⌘O.
            KeyAction(id: "littleWindowOpenInMenu", name: "Show Little Window “Open In” Menu", section: .window,
                      shortcuts: [Shortcut("o", cmdShift)], inCommandBar: false),
            KeyAction(id: "closeLittleWindows", name: "Close Little Windows", section: .window, shortcuts: [], triggers: ["close little"]),
            // App
            KeyAction(id: "settings", name: "Settings…", section: .app, shortcuts: [Shortcut(",", cmd)], triggers: ["preferences", "settings"]),
            // Arc's app menu shows ⌘♡ beside it, a glyph no key types (see buildMenus).
            KeyAction(id: "setDefaultBrowser", name: "Set as Default Browser", section: .app, shortcuts: [], triggers: ["default browser"]),
            KeyAction(id: "importData", name: "Import from Arc or Dia…", section: .app, shortcuts: [], triggers: ["import", "arc", "dia"]),
            KeyAction(id: "rebuildArcProfiles", name: "Rebuild Profiles from Arc…", section: .app, shortcuts: [], triggers: ["profiles", "arc profiles"]),
            // Chrome's app menu item and key; Arc has neither, only Settings ▸ Profiles ▸ Clear Browsing Data.
            KeyAction(id: "clearBrowsingData", name: "Clear Browsing Data…", section: .app, shortcuts: [Shortcut(Shortcut.delete, cmdShift)],
                      triggers: ["clear history", "delete history", "clear browsing data", "delete browsing data"], symbol: "trash"),
            // Arc's Translate bubble item "Language Settings": Chromium's page, in the space's profile (#209).
            KeyAction(id: "languageSettings", name: "Language Settings", section: .app, shortcuts: [],
                      triggers: ["language", "languages", "preferred language", "accept language"], symbol: "globe"),
            KeyAction(id: "checkForUpdates", name: "Check for Updates…", section: .app, shortcuts: [],
                      triggers: ["update", "upgrade", "new version"], symbol: "arrow.down.circle"),
            // Arc: Help ▸ Essential Keyboard Shortcuts.
            KeyAction(id: "essentialShortcuts", name: "Essential Keyboard Shortcuts", section: .help, shortcuts: [],
                      triggers: ["shortcuts", "keyboard shortcuts", "hotkeys"], symbol: "keyboard"),
            // Arc: Help ▸ Troubleshooting ▸ Reveal Arc Data, Copy Arc Info.
            KeyAction(id: "revealData", name: "Reveal Cra Data", section: .help, shortcuts: [], triggers: ["data folder", "reveal data"]),
            KeyAction(id: "copyAppInfo", name: "Copy Cra Info", section: .help, shortcuts: [], triggers: ["version", "copy info"]),
        ]
        // Arc: Switch to Split View 1–4 (⌃⇧1…4), the panes of the open split.
        for n in 1...4 {
            list.append(KeyAction(id: "splitPane\(n)", name: "Switch to Split View \(n)", section: .none,
                                  shortcuts: [Shortcut("\(n)", [.control, .shift])], inCommandBar: false))
        }
        for n in 1...9 {
            // Arc: ⌘9 is "Go to last Sidebar Item", as in Chrome.
            list.append(KeyAction(id: "item\(n)", name: n == 9 ? "Go to Last Tab" : "Go to Tab \(n)", section: .tabs,
                                  shortcuts: [Shortcut("\(n)", cmd)], triggers: ["\(n). tab", "\(n). item"], inCommandBar: false))
            list.append(KeyAction(id: "space\(n)", name: "Go to Space \(n)", section: .spaces,
                                  shortcuts: [Shortcut("\(n)", .control)], inCommandBar: false))
        }
        // Arc has no default for this (its command bar's "Move to Today in <space>" has no key);
        // ⌃⌘N adds ⌘ to Go to Space N (#86). Neither Arc nor macOS binds ⌃⌘1–9.
        for n in 1...9 {
            list.append(KeyAction(id: "moveTabToSpace\(n)", name: "Move Tab to Space \(n)", section: .spaces,
                                  shortcuts: [Shortcut("\(n)", [.command, .control])], inCommandBar: false))
        }
        return list
    }()
}

extension NSMenuItem {
    /// Shows a command's shortcut on the right of a context-menu row, as the menu bar does,
    /// following the user's overrides. Shortcut.key is already unshifted ("r" for ⇧⌘R), which
    /// is what keyEquivalent wants.
    @MainActor func showShortcut(of id: String) {
        guard let s = KeyBindingRegistry.shared.action(id)?.primary else { return }
        keyEquivalent = s.key
        keyEquivalentModifierMask = s.flags
    }
}

extension Notification.Name {
    /// Posted when the user edits shortcuts; the app rebuilds its menus.
    static let craKeyBindingsChanged = Notification.Name("craKeyBindingsChanged")
}
