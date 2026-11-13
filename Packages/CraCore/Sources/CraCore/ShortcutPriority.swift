import Foundation

/// Who gets a shortcut's keys while a page has the keyboard and wants them too: Arc 1.172's choice
/// per shortcut in Settings ▸ Shortcuts (GitHub #374). The raw values are Arc's own
/// (`overrideWebView`, `promptAfterConsumedByWebView`, `low`), as keybindings.json stores them.
///
/// Cra hears a key twice around the page (Sources/CraCEF/CraCEF.mm): before the page sees it
/// (CEF's OnPreKeyEvent), and again if the page left it alone (OnKeyEvent). Prefer Cra takes it
/// at the first point; Prefer Websites only at the second; Use Both gives the page the first press
/// and takes the next one when the page kept the first (UseBothPresses).
public enum ShortcutPriority: String, CaseIterable, Codable, Hashable, Sendable {
    case preferCra = "overrideWebView"
    case useBoth = "promptAfterConsumedByWebView"
    case preferWebsites = "low"

    /// The pop-up's item: Arc's names, with Cra for Arc.
    public var title: String {
        switch self {
        case .preferCra: "Prefer Cra"
        case .useBoth: "Use Both"
        case .preferWebsites: "Prefer Websites"
        }
    }

    /// The line under the pop-up: Arc's wording, with Cra for Arc.
    public var subtitle: String {
        switch self {
        case .preferCra: "When shortcuts conflict, Cra wins."
        case .useBoth: "Press this shortcut once to use the website’s shortcut. Press it twice to use Cra’s shortcut."
        case .preferWebsites: "When shortcuts conflict, the website wins."
        }
    }

    /// Does Cra take the press before the page sees it? `repeatOffered`: the press is the second
    /// one of a Use Both shortcut whose first press the page kept (UseBothPresses.beforePage).
    /// A press Cra doesn't take here goes to the page, and comes back to Cra if the page leaves it.
    public func takesBeforePage(repeatOffered: Bool = false) -> Bool {
        switch self {
        case .preferCra: true
        case .useBoth: repeatOffered
        case .preferWebsites: false
        }
    }

    /// Each action's priority until the user picks one: what Cra did before the choice existed.
    /// The actions Cra took before the page (Chrome calls them reserved) prefer Cra, the rest prefer
    /// websites, as in Chrome.
    public static func defaultPriority(for action: String) -> ShortcutPriority {
        preferCraByDefault.contains(action) ? .preferCra : .preferWebsites
    }

    /// The shortcuts Cra took before the page saw them before #374 (AppDelegate.reservedActions).
    /// Copy URL is among them like Arc's: Google Docs takes ⇧⌘C for its word count (GitHub #194).
    public static let preferCraByDefault: Set<String> = Set([
        "newTab", "newWindow", "newBlankWindow", "newIncognitoWindow", "closeTab", "closeWindow", "reopenClosedTab", "editURL",
        "toggleSidebar", "toggleToolbar", "nextTab", "previousTab", "recentTab", "recentTabBackward", "nextSpace", "previousSpace",
        "devTools", "jsConsole", "inspectElement", "viewArchive", "openLibrary", "settings", "clearToday", "newLittleWindow",
        "promoteLittleWindow", "addSplitView", "closeSplitPane", "copyURL", "copyURLMarkdown",
    ] + (1...9).flatMap { ["item\($0)", "space\($0)", "moveTabToSpace\($0)"] })
}

/// Use Both's memory between key presses (Arc's `promptAfterConsumedByWebView`, #374). The first press
/// of a shortcut goes to the page. If the page leaves it, it comes back and Cra runs it as with Prefer
/// Websites. If the page keeps it (nothing came back `answerTime` after the press), Cra says so with
/// a toast ("Press ⌘W again to Close Tab"), and the next press of that shortcut while the offer stands
/// is Cra's, taken before the page sees it.
///
/// Chromium has no signal for a key the page used; a key it didn't use comes back through CEF's
/// OnKeyEvent right after the renderer answers, so a press that hasn't come back by `answerTime`
/// counts as kept. If a slow page's answer comes later after all, Cra still runs the shortcut then
/// and drops the offer (`pageLeft`).
public struct UseBothPresses: Equatable, Sendable {
    /// How long a page has to hand a press back before Cra counts it as the page's.
    public static let answerTime: TimeInterval = 0.5

    struct Press: Equatable, Sendable {
        var action: String
        var time: TimeInterval
    }

    /// The press the page has and hasn't handed back yet.
    private(set) var waiting: Press?
    /// The shortcut the page kept, and until when its next press is Cra's.
    private(set) var offered: Press?

    public init() {}

    /// A press of a Use Both `action` before the page sees it, at `time` (the event's timestamp):
    /// true when Cra takes it, the next press of a shortcut the page kept while the offer stands.
    /// A key held down repeats: its repeats aren't presses of their own and go where the first went.
    public mutating func beforePage(_ action: String, at time: TimeInterval, isRepeat: Bool = false) -> Bool {
        if isRepeat { return false }
        if let o = offered, o.action == action, time <= o.time {
            offered = nil
            waiting = nil
            return ShortcutPriority.useBoth.takesBeforePage(repeatOffered: true)
        }
        waiting = Press(action: action, time: time)
        return ShortcutPriority.useBoth.takesBeforePage(repeatOffered: false)
    }

    /// The page left the press of `action` alone (OnKeyEvent): Cra runs the shortcut, and there is
    /// nothing to offer.
    public mutating func pageLeft(_ action: String) {
        if waiting?.action == action { waiting = nil }
        if offered?.action == action { offered = nil }
    }

    /// `answerTime` after the press of `action` at `pressedAt`: true when the page kept it. Cra then
    /// offers the shortcut until `now + offerTime` (the toast's time on screen).
    public mutating func pageKept(_ action: String, pressedAt: TimeInterval, now: TimeInterval, offerTime: TimeInterval) -> Bool {
        guard let w = waiting, w == Press(action: action, time: pressedAt) else { return false }
        waiting = nil
        offered = Press(action: action, time: now + offerTime)
        return true
    }
}

/// keybindings.json: the shortcuts the user changed, by action id, and the priority they picked
/// (#374). The file is `{ "<action>": [ { "key", "modifiers", "priority"? }, … ] }`: the priority
/// rides on each of the action's chords, so Cra from before #374, which reads the file as
/// `[String: [KeyChord]]`, loads the same shortcuts and leaves the field alone. An action whose
/// priority the user changed keeps its shortcuts in the file even when they are the defaults.
public struct KeyBindingOverrides: Codable, Equatable, Sendable {
    public var shortcuts: [String: [KeyChord]]
    public var priorities: [String: ShortcutPriority]

    public init(shortcuts: [String: [KeyChord]] = [:], priorities: [String: ShortcutPriority] = [:]) {
        self.shortcuts = shortcuts
        self.priorities = priorities
    }

    /// The action's priority: the user's, else Cra's default for it.
    public func priority(for action: String) -> ShortcutPriority {
        priorities[action] ?? ShortcutPriority.defaultPriority(for: action)
    }

    /// Picks `priority` for an action whose shortcuts are now `current`, `defaults` being Cra's.
    /// Picking the default again over default shortcuts drops the action from the file, so
    /// "Reset Shortcut to Default" turns off again. An action without a shortcut has no keys to
    /// give anyone (Arc shows no pop-up for it), and the file has no chord to carry its priority.
    public mutating func setPriority(_ priority: ShortcutPriority, for action: String, current: [KeyChord], defaults: [KeyChord]) {
        if priority == ShortcutPriority.defaultPriority(for: action) || current.isEmpty {
            priorities[action] = nil
            if shortcuts[action] == defaults { shortcuts[action] = nil }
        } else {
            priorities[action] = priority
            shortcuts[action] = current
        }
    }

    /// One chord as the file holds it.
    struct StoredChord: Codable {
        var key: String
        var modifiers: UInt
        var priority: String?
    }

    public init(from decoder: Decoder) throws {
        let file = try [String: [StoredChord]](from: decoder)
        var shortcuts: [String: [KeyChord]] = [:]
        var priorities: [String: ShortcutPriority] = [:]
        for (action, chords) in file {
            shortcuts[action] = chords.map { KeyChord(key: $0.key, modifiers: $0.modifiers) }
            // A value a later Cra wrote that this one doesn't know: the default.
            if let p = chords.lazy.compactMap({ $0.priority.flatMap(ShortcutPriority.init(rawValue:)) }).first { priorities[action] = p }
        }
        self.init(shortcuts: shortcuts, priorities: priorities)
    }

    public func encode(to encoder: Encoder) throws {
        var file: [String: [StoredChord]] = [:]
        for (action, chords) in shortcuts {
            let p = priorities[action]?.rawValue
            file[action] = chords.map { StoredChord(key: $0.key, modifiers: $0.modifiers, priority: p) }
        }
        try file.encode(to: encoder)
    }
}
