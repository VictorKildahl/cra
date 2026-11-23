import Foundation

/// The tick a control gives under a finger (#675). The bottom bar's buttons tick once as the
/// finger comes down; the page menu's controls tick on press, on release, or on both. A
/// control's accessibility identifier says which.
public enum MobilePressHaptics {
    public enum Tick: Equatable, Sendable {
        /// A light impact as the finger comes down.
        case press
        /// A softer one as it lets go.
        case release
        /// A very subtle selection tick, for the bar and the address.
        case selection
    }

    /// When a control ticks.
    public enum Policy: Equatable, Sendable {
        /// One tick as the finger comes down.
        case press
        /// One tick as it lets go.
        case release
        /// One on each.
        case pressAndRelease
        /// One very subtle selection tick as the finger comes down, for the bar and the address.
        case selection
    }

    /// Which end of a press is being reported.
    public enum Edge: Equatable, Sendable {
        case down
        case up
    }

    /// The bottom bar's buttons: the tab stack, the New Tab pill and the menu button on a page;
    /// Spaces and Settings in the tab switcher. They give one very subtle tick as the finger
    /// comes down.
    public static let barButtons: Set<String> = ["bar-tabs", "bar-search", "bar-menu", "bar-spaces", "bar-settings"]

    /// The page menu's controls that tick only as the finger comes down: its tiles that act at
    /// once, its rows, the zoom stepper and the footer.
    public static let pressButtons: Set<String> = [
        "menu-tile-findOnPage", "menu-tile-share",
        "menu-row-displayOptions", "menu-row-translate", "menu-row-readerMode",
        "menu-row-requestDesktopSite", "menu-row-siteSettings",
        "menu-zoom-in", "menu-zoom-out", "menu-zoom-value",
        "menu-reload-without-blockers",
    ]

    /// The controls that give one very subtle selection tick instead of an impact: the bottom
    /// bar's buttons, and the page menu's address as it is tapped.
    public static let selectionButtons: Set<String> = barButtons.union(["menu-host"])

    /// The page menu's tiles that also tick as the finger lets go.
    public static let pressAndReleaseButtons: Set<String> = ["menu-tile-pin", "menu-tile-summarize"]

    /// The page menu's capsule: Back, Forward, Reload and Copy Link, which tick only as the
    /// finger lets go.
    public static let releaseButtons: Set<String> = ["menu-back", "menu-forward", "menu-reload", "menu-copy-link"]

    public static func policy(for identifier: String) -> Policy? {
        if pressAndReleaseButtons.contains(identifier) { return .pressAndRelease }
        if releaseButtons.contains(identifier) { return .release }
        if selectionButtons.contains(identifier) { return .selection }
        if pressButtons.contains(identifier) { return .press }
        return nil
    }

    /// The tick for `identifier` at `edge`, or nil when that edge is silent.
    public static func tick(for identifier: String, edge: Edge) -> Tick? {
        guard let policy = policy(for: identifier) else { return nil }
        switch (policy, edge) {
        case (.release, .down), (.press, .up), (.selection, .up): return nil
        case (.selection, .down): return .selection
        case (.release, .up): return .release
        case (.press, .down), (.pressAndRelease, .down): return .press
        case (.pressAndRelease, .up): return .release
        }
    }
}
