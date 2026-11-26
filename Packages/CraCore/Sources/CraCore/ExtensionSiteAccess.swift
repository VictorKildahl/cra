import Foundation

/// The site access line in a pinned extension's right-click menu (GitHub #695), as Arc's is: Chromium's
/// extension menu (ExtensionContextMenuModel's page access items, title case on the Mac). An extension that
/// asks for site access (host permissions or activeTab) gets either "Can't Read or Change Site's Data",
/// greyed out, on a page it may never run on (chrome://, the Web Store), or the "This Can Read and Change
/// Site Data" submenu: when you click it, on this site, or on all sites, then Learn More. Which choice is
/// on and which can be picked is Chromium's (PermissionsManager), reported by the engine.
public enum ExtensionSiteAccess: Equatable, Sendable {
    public enum Choice: String, CaseIterable, Sendable {
        case onClick, onSite, onAllSites
    }

    /// The extension wants site access but can't have it on this page.
    case cantAccess
    /// The three choices for `site` (the page's host as Chrome's menu names it: Unicode, without "www."),
    /// `current` on, `enabled` the ones the person can pick.
    case choices(site: String, current: Choice?, enabled: Set<Choice>)

    /// One row of the line's submenu.
    public struct Row: Equatable, Sendable {
        public let title: String
        /// nil for Learn More and the separator.
        public let choice: Choice?
        public let checked: Bool
        public let enabled: Bool
        public var isSeparator: Bool { title.isEmpty }
    }

    /// The engine's report (CraBrowser.extensionSiteAccess): nil, no line; "cantAccess"; or "site",
    /// "current" and "enabled".
    public init?(engine: [String: Any]?) {
        guard let engine else { return nil }
        if (engine["cantAccess"] as? Bool) == true { self = .cantAccess; return }
        guard let site = engine["site"] as? String else { return nil }
        let enabled = Set((engine["enabled"] as? [String] ?? []).compactMap(Choice.init(rawValue:)))
        self = .choices(site: site, current: (engine["current"] as? String).flatMap(Choice.init(rawValue:)), enabled: enabled)
    }

    public static let cantAccessTitle = "Can't Read or Change Site's Data"
    public static let submenuTitle = "This Can Read and Change Site Data"
    public static let learnMoreTitle = "Learn More About Site Access"
    /// Chrome's help article for site access (kRuntimeHostPermissionsHelpURL).
    public static let learnMorePage = "https://support.google.com/chrome?p=enable_extensions"

    public var title: String {
        switch self {
        case .cantAccess: Self.cantAccessTitle
        case .choices: Self.submenuTitle
        }
    }

    public static func title(_ choice: Choice, site: String) -> String {
        switch choice {
        case .onClick: "When You Click the Extension"
        case .onSite: "On \(site)"
        case .onAllSites: "On All Sites"
        }
    }

    /// The submenu: the three choices (a radio group), a separator and Learn More. None for `cantAccess`.
    public var rows: [Row] {
        guard case let .choices(site, current, enabled) = self else { return [] }
        return Choice.allCases.map { Row(title: Self.title($0, site: site), choice: $0, checked: $0 == current, enabled: enabled.contains($0)) }
            + [Row(title: "", choice: nil, checked: false, enabled: false),
               Row(title: Self.learnMoreTitle, choice: nil, checked: false, enabled: true)]
    }
}
