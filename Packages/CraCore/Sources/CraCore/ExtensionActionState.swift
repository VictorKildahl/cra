import Foundation

/// What an extension set on its toolbar action while running (chrome.action.setIcon, setTitle,
/// setBadgeText), from Chromium's Extensions.actionUpdated (scripts/cef-patches/
/// extensions-action-updates.patch, GitHub #106). Empty values are ones it did not set.
public struct ExtensionActionState: Equatable, Sendable {
    /// PNG bytes of the icon it set.
    public var icon: Data?
    public var title = ""
    public var badgeText = ""
    /// "#RRGGBBAA".
    public var badgeColor = ""

    public init(icon: Data? = nil, title: String = "", badgeText: String = "", badgeColor: String = "") {
        self.icon = icon
        self.title = title
        self.badgeText = badgeText
        self.badgeColor = badgeColor
    }

    public var isEmpty: Bool { icon == nil && title.isEmpty && badgeText.isEmpty && badgeColor.isEmpty }

    /// Chrome's rule, value by value: what the extension set for the tab, else what it set for
    /// every tab.
    public func over(_ fallback: ExtensionActionState) -> ExtensionActionState {
        ExtensionActionState(icon: icon ?? fallback.icon, title: title.isEmpty ? fallback.title : title,
                             badgeText: badgeText.isEmpty ? fallback.badgeText : badgeText,
                             badgeColor: badgeColor.isEmpty ? fallback.badgeColor : badgeColor)
    }
}

/// One Extensions.actionUpdated event.
public struct ExtensionActionUpdate: Equatable, Sendable {
    public let extensionID: String
    /// Chromium profile folder ("Default", "Profile 1").
    public let profile: String
    /// The page target of the tab the values are for; nil for every tab.
    public let targetID: String?
    public let state: ExtensionActionState

    /// Icons are 16 pt (32 px at 2x); anything near this size is not one.
    static let maxIconBytes = 256 * 1024
    static let pngDataURLPrefix = "data:image/png;base64,"

    public init(extensionID: String, profile: String, targetID: String?, state: ExtensionActionState) {
        self.extensionID = extensionID
        self.profile = profile
        self.targetID = targetID
        self.state = state
    }

    /// The event's params; nil when they are not one. An icon that is not a PNG data URL, or
    /// too large to be an icon, counts as none.
    public init?(params: Data) {
        guard let p = try? JSONSerialization.jsonObject(with: params) as? [String: Any],
              let id = p["id"] as? String, !id.isEmpty, let profile = p["profile"] as? String else { return nil }
        let target = (p["targetId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var icon: Data?
        if let url = p["icon"] as? String, url.hasPrefix(Self.pngDataURLPrefix),
           url.utf8.count <= Self.maxIconBytes * 4 / 3 + Self.pngDataURLPrefix.utf8.count {
            icon = Data(base64Encoded: String(url.dropFirst(Self.pngDataURLPrefix.count)))
        }
        self.init(extensionID: id, profile: profile, targetID: target,
                  state: ExtensionActionState(icon: icon, title: p["title"] as? String ?? "",
                                              badgeText: p["badgeText"] as? String ?? "",
                                              badgeColor: p["badgeColor"] as? String ?? ""))
    }
}

/// Every reported action: each extension's values for every tab, per profile, and each Cra
/// tab's own values.
public struct ExtensionActionStates: Equatable, Sendable {
    struct Key: Hashable, Sendable { let profile: String; let extensionID: String }
    private var everyTab: [Key: ExtensionActionState] = [:]
    /// Tab → extension ID → what was set for that tab only.
    private var tabs: [UUID: [String: ExtensionActionState]] = [:]

    public init() {}

    /// `tab` is the Cra tab the update's page target belongs to (nil for an update for every tab).
    public mutating func apply(_ update: ExtensionActionUpdate, tab: UUID?) {
        if let tab {
            tabs[tab, default: [:]][update.extensionID] = update.state.isEmpty ? nil : update.state
            if tabs[tab]?.isEmpty == true { tabs[tab] = nil }
        } else {
            let key = Key(profile: update.profile, extensionID: update.extensionID)
            everyTab[key] = update.state.isEmpty ? nil : update.state
        }
    }

    /// Chromium forgets a tab's values with its page (closed or put to sleep).
    public mutating func removeTab(_ tab: UUID) {
        tabs[tab] = nil
    }

    /// What the extension shows on `tab` (in `profile`), or on a tab it set nothing for.
    public func state(extensionID: String, profile: String, tab: UUID?) -> ExtensionActionState {
        let shared = everyTab[Key(profile: profile, extensionID: extensionID)] ?? ExtensionActionState()
        guard let own = tab.flatMap({ tabs[$0]?[extensionID] }) else { return shared }
        return own.over(shared)
    }
}
