import Foundation

/// Which app was in use before Cra came forward, kept the way Arc keeps it
/// (WorkspaceClient.frontmostApplicationHistory), so a Little Window opened from that app can give
/// it the keyboard back when it closes (#430). Apps are process ids.
public struct FrontmostAppHistory: Equatable {
    /// How long after Cra comes forward a link still counts as coming from the app before it: the
    /// app that opens a link hands Cra the front (LaunchServices) at about the moment the link
    /// arrives, before or after it.
    public static let linkGrace: TimeInterval = 1

    /// The last app other than Cra to come forward.
    public private(set) var lastOther: Int32?
    /// The app in use when Cra last came forward.
    public private(set) var beforeCra: Int32?
    /// When Cra came forward; nil while another app is in front.
    public private(set) var craFrontSince: Date?

    public init(frontmost: Int32? = nil) { lastOther = frontmost }

    /// An app came forward (NSWorkspace.didActivateApplicationNotification); `isCra`: Cra itself.
    public mutating func activated(_ pid: Int32, isCra: Bool, at now: Date) {
        if isCra {
            beforeCra = lastOther
            craFrontSince = now
        } else {
            lastOther = pid
            craFrontSince = nil
        }
    }

    /// The app a Little Window opening at `now` goes back to when it closes: the app in use, when
    /// that isn't Cra (a link from it, the shortcut pressed in it). Nil when Cra itself was in use
    /// (⌥⌘N in the browser, a page's popup): its browser window takes the keyboard back as before.
    public func returnApp(at now: Date) -> Int32? {
        guard let since = craFrontSince else { return lastOther }
        return now.timeIntervalSince(since) <= Self.linkGrace ? beforeCra : nil
    }
}

/// One Little Window's way back to the app it was opened over (#430). Arc's Little Arc closes
/// back to where you were; AppKit alone gives the keyboard to Cra's next window, which brings the
/// browser window (and its Space) forward over the app the link came from.
public struct LittleWindowReturn: Equatable {
    /// The app to go back to; nil once Cra's own windows are in use.
    public private(set) var app: Int32?
    /// The Little Window has had the keyboard: windows that took it before (the browser window
    /// AppKit makes key while Cra comes forward for the link) don't count.
    public private(set) var hadKeyboard = false

    public init(app: Int32?) { self.app = app }

    public mutating func littleWindowBecameKey() { hadKeyboard = true }

    /// Another Cra window that isn't a panel (the browser window, Settings) took the keyboard: the
    /// browser is in use, so closing the Little Window goes back to it as before.
    /// `whileComingForward`: AppKit made it key as Cra came forward (between applicationWillBecomeActive and
    /// applicationDidBecomeActive), before the window it gives the keyboard back to. That isn't the browser in
    /// use, and it took the way back from a Little Window opened earlier: a second link from Slack, then ⌘W on
    /// the first window, brought the browser window forward instead of Slack (#659).
    public mutating func otherWindowBecameKey(whileComingForward: Bool = false) {
        if hadKeyboard, !whileComingForward { app = nil }
    }

    /// Cra came forward again (⌘Tab, a click on the Little Window) from `previous`: that's where
    /// the window goes back to now.
    public mutating func craCameForward(from previous: Int32?) {
        if app != nil { app = previous }
    }

    /// The app to bring forward as the window closes: only when it had the keyboard and Cra was
    /// in front (not an idle archive, a quit or a close in the background), and not when its page
    /// moved into a tab of the browser window, which is then what's in use.
    /// `littleWindowsLeft`: other Little Windows are still open. As in Arc, the front one of them takes
    /// the keyboard, so ⌘W can close it next, and the app comes back only after the last (#646). Bringing
    /// the app forward put it over all of them.
    public func target(closingKeyWindow: Bool, craActive: Bool, movedToTab: Bool, littleWindowsLeft: Bool = false) -> Int32? {
        guard closingKeyWindow, craActive, !movedToTab, !littleWindowsLeft else { return nil }
        return app
    }

    /// Whether another open Little Window can take the keyboard as one closes (#646): not a Peek, shown, not
    /// minimized, and on a Space in front (`onActiveSpace`, NSWindow.isOnActiveSpace: this desktop, or the one
    /// showing on another display). One on another desktop doesn't count: making it key switched macOS to that
    /// desktop, away from the app in use on this one (#738). With none left here, the closing window goes back to
    /// the app it was opened over, as the last one does.
    public static func canTakeKeyboard(isPeek: Bool, visible: Bool, miniaturized: Bool, onActiveSpace: Bool) -> Bool {
        !isPeek && visible && !miniaturized && onActiveSpace
    }

    /// Whether the Little Window in front takes the keyboard as `closing` goes (#646): it had the
    /// keyboard while Cra was in front, and its page didn't move into a tab (the browser window has it then).
    public static func nextTakesKeyboard(closingKeyWindow: Bool, craActive: Bool, movedToTab: Bool, littleWindowsLeft: Bool) -> Bool {
        closingKeyWindow && craActive && !movedToTab && littleWindowsLeft
    }
}

/// How a Little Window's close counts toward its way back (#430, #659): whether it closed as the key window with
/// Cra in front, which `LittleWindowReturn.target` asks.
public struct LittleWindowClose: Equatable, Sendable {
    public let closingKeyWindow: Bool
    public let craActive: Bool

    /// `keyIsThisWindow`: Cra's key window is the closing window (or its command bar or popup); `craActive`:
    /// NSApp.isActive; `craFrontmost`: the window server already has Cra in front (NSWorkspace's frontmost app);
    /// `clickedInWindow`: a click in the closing window closes it (its close button).
    /// A click on the close button of a Little Window while another app is in front brings Cra forward, but the
    /// button acts on the mouse-up, before AppKit makes Cra active: the window closed as an inactive one, nothing
    /// went back, and AppKit then gave the keyboard to the browser window, which came forward on its own display
    /// over the app the user was in (#659). That click is the Little Window in use, with Cra coming to the front.
    public init(keyIsThisWindow: Bool, craActive: Bool, craFrontmost: Bool, clickedInWindow: Bool) {
        let clickBringsCraForward = !craActive && craFrontmost && clickedInWindow
        closingKeyWindow = keyIsThisWindow || clickBringsCraForward
        self.craActive = craActive || clickBringsCraForward
    }
}

/// Where Cra's keyboard stays while a closing Little Window hands the front back to the app it was opened over
/// (#659). Cra is still the active app for a moment after asking that app forward (70 ms in the report), or about
/// to become it (a click on the close button while that app was in front). With the Little Window gone, AppKit gave
/// the keyboard (and main) to the browser window then, and activation raised it: on its own display, over the app
/// in use there, where it stayed, since the app coming back raises only its own windows. A window that shows nothing
/// is Cra's key and main window instead, and goes once Cra has let go of the front.
public struct KeyboardHold: Equatable, Sendable {
    /// The app that was asked forward may never take the front (it quit, or the user clicked Cra again): the hold
    /// goes then too, and Cra's next window takes the keyboard as AppKit gives it.
    public static let limit: TimeInterval = 2

    public let since: Date

    public init(at now: Date) { since = now }

    /// Whether the hold goes: Cra has let go of the front (applicationDidResignActive), or `limit` has passed.
    public func releases(craResigned: Bool, at now: Date) -> Bool {
        craResigned || now.timeIntervalSince(since) >= Self.limit
    }
}
