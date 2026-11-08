import Foundation

/// Settings ▸ Advanced "When opening Cra, start on a new tab" (X DM 7 Nov 2026, not in Arc, which
/// always opens on the tab in use last). On, the window in front opens with no tab selected and
/// the command bar ready for a new one, as ⌘T makes it; the sidebar keeps every tab.
public enum LaunchStart {
    /// Why this process started.
    public enum Launch: Equatable, Sendable {
        /// The user opened Cra: the Dock, Finder, Spotlight, a login item, Restart to Update.
        case opened
        /// To open a link or file from another app: its tab is what the window shows.
        case forLink
        /// Cra restarted itself into an update while the user was away: the session goes on.
        case automaticUpdate
        /// First launch: onboarding comes first.
        case firstRun
    }

    public static func startsOnNewTab(enabled: Bool, launch: Launch) -> Bool {
        enabled && launch == .opened
    }

    /// The order matters: a first run that came with a link still runs onboarding, and an update
    /// restart can't have brought a link with it.
    public static func launch(firstRun: Bool, automaticUpdate: Bool, withLinks: Bool) -> Launch {
        if firstRun { return .firstRun }
        if automaticUpdate { return .automaticUpdate }
        if withLinks { return .forLink }
        return .opened
    }
}
