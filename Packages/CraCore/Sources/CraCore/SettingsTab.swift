import Foundation

/// The tabs of Settings, in Arc's order (Arc 1.172.2, measured 11 Nov 2026: Account, General, Profiles,
/// Max, Links, Shortcuts, Icon, Advanced, in a toolbar over a 684 × 650 pt window). Cra has no account;
/// its first tab (the member card, sync and Share Cra) takes Account's place and, like Arc's, carries the
/// user's first name. Its raw value stays `sync`, the name `settingsPane=` and scenarios use. Privacy and Extensions, which Arc has no tab for, follow Advanced
/// and leave Arc's own tabs where Arc has them. Tabs, Plugins and Performance are no tabs of their own:
/// their rows sit in General, Extensions and Advanced.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case sync, general, profiles, max, links, shortcuts, icon, advanced, privacy, extensions

    public var id: String { rawValue }

    /// The tab Settings opens on, as Arc's always opens on its first.
    public static var first: SettingsTab { allCases[0] }

    /// The tab's name with no user name to go on: the first tab is "Cra" then.
    public var title: String { title(fullName: "") }

    /// The tab's name. The first is the user's first name, as Arc names its Account tab after the member
    /// (Victor, 12 Nov 2026), from the name macOS has for them; "Cra" when macOS has none.
    public func title(fullName: String) -> String {
        switch self {
        case .sync: return fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "Cra"
        case .general: return "General"
        case .profiles: return "Profiles"
        case .max: return "Max"
        case .links: return "Links"
        case .shortcuts: return "Shortcuts"
        case .icon: return "Icon"
        case .advanced: return "Advanced"
        case .privacy: return "Privacy"
        case .extensions: return "Extensions"
        }
    }

    /// The tab a pane name opens. Names are `cra://debug?settingsPane=` values and what "Search Settings…"
    /// asks for: the eleven panes of the sidebar window (general, tabs, links, max, privacy, profiles,
    /// extensions, plugins, shortcuts, performance, advanced) and the tabs' own names.
    public init?(pane: String) {
        switch pane {
        case "tabs": self = .general
        case "plugins": self = .extensions
        case "performance": self = .advanced
        default:
            guard let tab = SettingsTab(rawValue: pane) else { return nil }
            self = tab
        }
    }
}
