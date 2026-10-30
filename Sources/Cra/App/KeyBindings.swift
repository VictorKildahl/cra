import AppKit
import Observation

/// A keyboard shortcut. `key` is the lowercase character or a special key
/// (see `Shortcut.tab`, `.left`...), `modifiers` the device-independent flags.
struct Shortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt

    init(_ key: String, _ mods: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = mods.intersection(.deviceIndependentFlagsMask).rawValue
    }

    static let tab = "\t"
    static let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    static let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    static let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    static let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Shift turns "[" into "{" in charactersIgnoringModifiers; undo that.
    /// ⇧Tab arrives as backtab (U+0019).
    private static let unshift: [String: String] = ["\u{19}": Shortcut.tab, "{": "[", "}": "]", "<": ",", ">": ".", "?": "/", "+": "=", "_": "-", "~": "`", ":": ";", "\"": "'", "|": "\\"]

    /// Physical-key fallbacks so ⌘[ / ⌘] work on layouts (Danish, German...)
    /// where those characters live on other keys. Key codes are ANSI positions.
    private static let keyCodeFor: [String: UInt16] = ["[": 33, "]": 30, "=": 24, "-": 27, ",": 43, ".": 47, "/": 44, ";": 41, "'": 39, "`": 50, "\\": 42]

    func matches(_ event: NSEvent) -> Bool {
        // charactersIgnoringModifiers throws on flagsChanged events, which
        // Chromium forwards as raw key-downs for modifier keys.
        guard event.type == .keyDown else { return false }
        let evFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard evFlags == flags.intersection([.command, .shift, .option, .control]) else { return false }
        guard var chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
        chars = chars.lowercased()
        if let u = Self.unshift[chars] { chars = u }
        if chars == key { return true }
        if let code = Self.keyCodeFor[key], event.keyCode == code { return true }
        return false
    }

    /// Build a shortcut from a recorded key press (nil for bare letters without ⌘/⌃/⌥).
    static func from(event e: NSEvent) -> Shortcut? {
        guard e.type == .keyDown, var chars = e.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        chars = chars.lowercased()
        if let u = unshift[chars] { chars = u }
        let special = [tab, left, right, up, down].contains(chars) || (chars.unicodeScalars.first.map { $0.value >= 0xF704 && $0.value <= 0xF71F } ?? false)
        guard special || !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return Shortcut(chars, flags)
    }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        switch key {
        case Shortcut.tab: s += "⇥"
        case Shortcut.left: s += "←"
        case Shortcut.right: s += "→"
        case Shortcut.up: s += "↑"
        case Shortcut.down: s += "↓"
        default: s += key.uppercased()
        }
        return s
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

    /// First action whose shortcut matches the key event.
    func action(for event: NSEvent) -> KeyAction? {
        for a in actions where a.shortcuts.contains(where: { $0.matches(event) }) { return a }
        return nil
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
            KeyAction(id: "print", name: "Print", section: .file, shortcuts: [Shortcut("p", cmd)]),
            // Edit
            KeyAction(id: "copyURL", name: "Copy URL", section: .edit, shortcuts: [Shortcut("c", cmdShift)], triggers: ["copy link"]),
            KeyAction(id: "copyURLMarkdown", name: "Copy URL as Markdown", section: .edit, shortcuts: [Shortcut("c", cmdOptShift)], triggers: ["markdown"]),
            KeyAction(id: "find", name: "Find…", section: .edit, shortcuts: [Shortcut("f", cmd)], triggers: ["find", "search page"]),
            KeyAction(id: "findNext", name: "Find Next", section: .edit, shortcuts: [Shortcut("g", cmd)], inCommandBar: false),
            KeyAction(id: "findPrevious", name: "Find Previous", section: .edit, shortcuts: [Shortcut("g", cmdShift)], inCommandBar: false),
            // View
            KeyAction(id: "toggleSidebar", name: "Hide Sidebar", section: .view, shortcuts: [Shortcut("s", cmd)], triggers: ["sidebar", "hide sidebar", "show sidebar"]),
            KeyAction(id: "toggleToolbar", name: "Hide Toolbar", section: .view, shortcuts: [Shortcut("d", cmdShift)], triggers: ["toolbar"]),
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
            KeyAction(id: "devTools", name: "Developer Tools", section: .view, shortcuts: [Shortcut("i", cmdOpt)], triggers: ["devtools", "inspect", "console"]),
            KeyAction(id: "inspectElement", name: "Inspect Elements", section: .view, shortcuts: [Shortcut("c", cmdOpt)], inCommandBar: false),
            KeyAction(id: "jsConsole", name: "JavaScript Console", section: .view, shortcuts: [Shortcut("j", cmdOpt)], inCommandBar: false),
            // Arc: Extensions ▸ Picture in Picture (no shortcut); "Open Picture in Picture" in the command bar.
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
            KeyAction(id: "deleteSpace", name: "Delete Space…", section: .spaces, shortcuts: [], triggers: ["delete space", "remove space"]),
            // Tabs
            KeyAction(id: "pinTab", name: "Pin/Unpin Tab", section: .tabs, shortcuts: [Shortcut("d", cmd)], triggers: ["pin", "unpin"]),
            KeyAction(id: "nextTab", name: "Next Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.down, cmdOpt)], inCommandBar: false),
            KeyAction(id: "previousTab", name: "Previous Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.up, cmdOpt)], inCommandBar: false),
            KeyAction(id: "recentTab", name: "Next Recent Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.tab, .control)], inCommandBar: false),
            KeyAction(id: "recentTabBackward", name: "Previous Recent Tab", section: .tabs, shortcuts: [Shortcut(Shortcut.tab, [.control, .shift])], inCommandBar: false),
            KeyAction(id: "clearToday", name: "Clear Today", section: .tabs, shortcuts: [Shortcut("k", cmdShift)], triggers: ["clear", "tidy"]),
            KeyAction(id: "favoriteTab", name: "Add to Favorites", section: .tabs, shortcuts: [], triggers: ["favorite", "top app"]),
            KeyAction(id: "renameTab", name: "Rename Tab…", section: .tabs, shortcuts: [], triggers: ["rename"]),
            KeyAction(id: "duplicateTab", name: "Duplicate Tab", section: .tabs, shortcuts: [], triggers: ["duplicate"]),
            KeyAction(id: "resetTab", name: "Reset Pinned Tab", section: .tabs, shortcuts: [], triggers: ["reset", "home"]),
            KeyAction(id: "muteTab", name: "Mute / Unmute Tab", section: .tabs, shortcuts: [], triggers: ["mute"]),
            // Archive
            KeyAction(id: "goBack", name: "Go Back", section: .archive, shortcuts: [Shortcut("[", cmd), Shortcut(Shortcut.left, cmd)]),
            KeyAction(id: "goForward", name: "Go Forward", section: .archive, shortcuts: [Shortcut("]", cmd), Shortcut(Shortcut.right, cmd)]),
            KeyAction(id: "viewArchive", name: "View History", section: .archive, shortcuts: [Shortcut("y", cmd)], triggers: ["archive", "history", "closed tabs"]),
            // Window
            KeyAction(id: "openLibrary", name: "Open Library…", section: .window, shortcuts: [Shortcut("l", cmdShift)], triggers: ["library"]),
            KeyAction(id: "viewDownloads", name: "View Downloads…", section: .window, shortcuts: [Shortcut("j", cmdShift)], triggers: ["downloads"]),
            // Arc's Little Arc "Open in Space" button (LittleBrowserMoveButton) and "Close Little Arc Windows".
            KeyAction(id: "promoteLittleWindow", name: "Open Little Window in Space", section: .window, shortcuts: [Shortcut("o", cmd)], inCommandBar: false),
            KeyAction(id: "closeLittleWindows", name: "Close Little Windows", section: .window, shortcuts: [], triggers: ["close little"]),
            // App
            KeyAction(id: "settings", name: "Settings…", section: .app, shortcuts: [Shortcut(",", cmd)], triggers: ["preferences", "settings"]),
            // Arc's app menu shows ⌘♡ beside it, a glyph no key types (see buildMenus).
            KeyAction(id: "setDefaultBrowser", name: "Set as Default Browser", section: .app, shortcuts: [], triggers: ["default browser"]),
            KeyAction(id: "importData", name: "Import from Arc or Dia…", section: .app, shortcuts: [], triggers: ["import", "arc", "dia"]),
        ]
        for n in 1...9 {
            list.append(KeyAction(id: "item\(n)", name: "Go to Tab \(n)", section: .tabs,
                                  shortcuts: [Shortcut("\(n)", cmd)], triggers: ["\(n). tab", "\(n). item"], inCommandBar: false))
            list.append(KeyAction(id: "space\(n)", name: "Go to Space \(n)", section: .spaces,
                                  shortcuts: [Shortcut("\(n)", .control)], inCommandBar: false))
        }
        return list
    }()
}

extension Notification.Name {
    /// Posted when the user edits shortcuts; the app rebuilds its menus.
    static let craKeyBindingsChanged = Notification.Name("craKeyBindingsChanged")
}
