/// Where the keys go when the ⌘T / ⌘L bar closes.
public enum CommandBarClosing: Equatable, Sendable {
    /// A pick, Escape or a shortcut closed it: the keys were still the bar's.
    case byBar
    /// The bar's panel lost the keys and that closed it; `to` is the window that holds them now.
    case lostKeys(to: KeyHolder)

    /// The window holding the keys a moment after the bar lost them.
    public enum KeyHolder: Equatable, Sendable {
        /// None: Cra is no longer the active app, or nothing took them yet.
        case none
        /// The bar's own window, a window over it (its Peek) or one inside it (its page).
        case barsWindow
        /// Another Cra window (a second browser window, a Little Window, Settings).
        case otherWindow
    }

    /// Whether the bar closes when its panel loses the keys to `holder`. A click on its window or on
    /// another Cra window closes it. Leaving Cra for another app doesn't (GitHub #551): Arc keeps the
    /// bar open with what was typed and gives it the keys again when Cra comes back.
    public static func closesBar(lostKeysTo holder: KeyHolder) -> Bool {
        holder != .none
    }

    /// How long after opening the bar takes the keys back when they go: a page made behind it (⌘Return's
    /// background tab, the page coming up as ⌘T opens) takes them on its own.
    public static let keysGraceAfterOpening: Double = 0.6

    /// Whether the bar's panel, having lost the keys `secondsOpen` after it opened, takes them back
    /// instead of closing. Only while it is opening, and never from a click (GitHub #807): a click
    /// outside the bar closes it whenever it comes, as in Arc.
    public static func takesKeysBack(secondsOpen: Double, byClick: Bool) -> Bool {
        !byClick && secondsOpen < keysGraceAfterOpening
    }

    /// True when the bar's window takes the keys back and focuses its page. Never from another
    /// window that took them (GitHub #429): Arc leaves them where the click put them.
    public var barsWindowTakesKeys: Bool {
        self != .lostKeys(to: .otherWindow)
    }
}
