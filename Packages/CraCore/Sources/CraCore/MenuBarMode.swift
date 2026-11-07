import Foundation

/// Settings ▸ Advanced ▸ "Keep Cra in the menu bar" (GitHub #231, not in Arc, where ⌘Q quits):
/// ⌘Q closes the pages and windows as a quit would, but Cra keeps running behind a menu bar item,
/// so ⌥⌘N from any app opens a Little Window without waiting for Chromium to start.
public enum MenuBarMode {
    /// Where a quit came from.
    public enum QuitSource: Equatable, Sendable {
        /// Cra ▸ Quit Cra, or ⌘Q.
        case appMenu
        /// Quit Cra in the menu bar item's menu: the way out of the menu bar.
        case menuBarItem
        /// A quit Apple Event: logout, restart, shutdown, the Dock's Quit, a script, a newer copy
        /// of Cra replacing this one.
        case appleEvent
        /// Restarting into an update or another page engine.
        case relaunch
    }

    public enum QuitOutcome: Equatable, Sendable {
        case quit
        case stayInMenuBar
    }

    /// Only Cra's own Quit stays in the menu bar: macOS logging out, a script or the updater
    /// must get a real quit, and the menu bar item's Quit is how the user asks for one.
    public static func outcome(enabled: Bool, source: QuitSource) -> QuitOutcome {
        enabled && source == .appMenu ? .stayInMenuBar : .quit
    }

    /// Cra has a Dock icon unless it was put in the menu bar and nothing of it is on screen. A
    /// Little Window from ⌥⌘N or Settings from the menu bar item bring the icon back while open,
    /// as any app's window would; closing the last one puts Cra back in the menu bar.
    public static func showsInDock(inMenuBar: Bool, windowsOpen: Bool) -> Bool {
        !inMenuBar || windowsOpen
    }

    public enum WindowKind: Equatable, Sendable { case normal, blank, incognito }

    public struct Window: Equatable, Sendable {
        public var id: UUID
        public var kind: WindowKind
        public init(id: UUID, kind: WindowKind) {
            self.id = id
            self.kind = kind
        }
    }

    /// What ⌘Q does to the browser windows when Cra stays: the ones a relaunch would bring back are
    /// put away (`keep`, opened again together), the rest close (`close`). Incognito windows always
    /// close, ending their session as a quit does. With "restore windows from previous session"
    /// off, only the window in use last is kept, or a normal one when that was a Blank Window
    /// (SidebarStore.keepOnlyActiveWindow).
    public static func windowsOnQuit(_ windows: [Window], active: UUID?, restoreWindows: Bool) -> (keep: [UUID], close: [UUID]) {
        let kept: [Window]
        if restoreWindows {
            kept = windows.filter { $0.kind != .incognito }
        } else {
            let one = windows.first { $0.id == active && $0.kind == .normal } ?? windows.first { $0.kind == .normal }
                ?? windows.first { $0.kind != .incognito }
            kept = one.map { [$0] } ?? []
        }
        let keep = kept.map(\.id)
        return (keep, windows.map(\.id).filter { !keep.contains($0) })
    }
}
