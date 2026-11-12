import Foundation

/// The tabs of Settings, in Arc's order (Arc 1.172.2, measured 11 Nov 2026: Account, General, Profiles,
/// Max, Links, Shortcuts, Icon, Advanced, in a toolbar over a 684 × 650 pt window). Cra has no account,
/// so its sync takes Account's place; Privacy and Extensions, which Arc has no tab for, follow Advanced
/// and leave Arc's own tabs where Arc has them. Tabs, Plugins and Performance are no tabs of their own:
/// their rows sit in General, Extensions and Advanced.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case sync, general, profiles, max, links, shortcuts, icon, advanced, privacy, extensions

    public var id: String { rawValue }

    /// The tab Settings opens on, as Arc's always opens on its first.
    public static var first: SettingsTab { allCases[0] }

    public var title: String {
        switch self {
        case .sync: return "Sync"
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
