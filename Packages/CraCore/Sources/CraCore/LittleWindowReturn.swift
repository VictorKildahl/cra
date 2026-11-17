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
    public mutating func otherWindowBecameKey() {
        if hadKeyboard { app = nil }
    }

    /// Cra came forward again (⌘Tab, a click on the Little Window) from `previous`: that's where
    /// the window goes back to now.
    public mutating func craCameForward(from previous: Int32?) {
        if app != nil { app = previous }
    }

    /// The app to bring forward as the window closes: only when it had the keyboard and Cra was
    /// in front (not an idle archive, a quit or a close in the background), and not when its page
    /// moved into a tab of the browser window, which is then what's in use.
    public func target(closingKeyWindow: Bool, craActive: Bool, movedToTab: Bool) -> Int32? {
        guard closingKeyWindow, craActive, !movedToTab else { return nil }
        return app
    }
}
