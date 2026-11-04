import Foundation

/// One Extensions.sidePanelRequested event: an extension asked to show, hide or toggle its side
/// panel for a page (its toolbar action with `openPanelOnActionClick`, `chrome.sidePanel.open()`
/// or `close()`). Chromium sends it to Cra instead of opening its own side panel, which CEF never
/// shows (scripts/cef-patches/extension-side-panels.patch). MetaMask opens in its side panel by
/// default, so before this its toolbar button did nothing, in Cra as in Arc.
public struct ExtensionSidePanelRequest: Equatable, Sendable {
    public enum Kind: String, Sendable { case toggle, open, close }

    public let extensionID: String
    /// Chromium profile folder ("Default", "Profile 1").
    public let profile: String
    public let kind: Kind
    /// The panel's page for that tab; empty for `close`.
    public let url: String
    /// The page target of the tab the request is for.
    public let targetID: String

    public init(extensionID: String, profile: String, kind: Kind, url: String, targetID: String) {
        self.extensionID = extensionID
        self.profile = profile
        self.kind = kind
        self.url = url
        self.targetID = targetID
    }

    /// The event's params; nil when they are not one, or when a show/toggle names a page that is
    /// not one of the extension's own.
    public init?(params: Data) {
        guard let p = try? JSONSerialization.jsonObject(with: params) as? [String: Any],
              let id = p["id"] as? String, !id.isEmpty, let profile = p["profile"] as? String,
              let kind = (p["request"] as? String).flatMap(Kind.init(rawValue:)),
              let target = p["targetId"] as? String else { return nil }
        let url = p["url"] as? String ?? ""
        if kind != .close, !Self.isOwnPage(url, of: id) { return nil }
        self.init(extensionID: id, profile: profile, kind: kind, url: url, targetID: target)
    }

    /// `url` is a page of the extension `id` (chrome-extension://<id>/…).
    static func isOwnPage(_ url: String, of id: String) -> Bool {
        guard let u = URL(string: url), u.scheme == "chrome-extension", u.host == id else { return false }
        return true
    }

    /// What the window's panel does about this request, given what it shows. Chrome shows one
    /// panel per window: opening another extension's replaces it; toggling or closing only ever
    /// hides the asking extension's own.
    public func change(from current: ExtensionSidePanelState?) -> ExtensionSidePanelChange {
        let wanted = ExtensionSidePanelState(extensionID: extensionID, profile: profile, url: url)
        let showsThis = current.map { $0.extensionID == extensionID && $0.profile == profile } ?? false
        switch kind {
        case .toggle: return showsThis ? .hide : .show(wanted)
        case .open: return current == wanted ? .none : .show(wanted)
        case .close: return showsThis ? .hide : .none
        }
    }
}

/// What a window's extension side panel shows.
public struct ExtensionSidePanelState: Equatable, Sendable {
    public var extensionID: String
    public var profile: String
    public var url: String

    public init(extensionID: String, profile: String, url: String) {
        self.extensionID = extensionID
        self.profile = profile
        self.url = url
    }
}

public enum ExtensionSidePanelChange: Equatable, Sendable {
    case none
    case show(ExtensionSidePanelState)
    case hide
}

/// The panel's width: Chrome's side panel starts at 320 pt and drags wider; Cra starts a little
/// wider (MetaMask's panel layout wants ~360) and always leaves the pages room.
public enum ExtensionSidePanelWidth {
    public static let initial: Double = 360
    public static let minimum: Double = 320
    public static let maximum: Double = 640
    /// A single page keeps at least this much beside the panel; a window narrower than panel +
    /// page does not show the panel (it comes back when the window is wide enough).
    public static let minimumPageWidth: Double = 400

    /// What the pages need beside the panel: one page its minimum, a split every pane its own
    /// minimum and the gaps between them (side by side), so the panel never squeezes a pane.
    public static func pageMinimum(panes: Int, paneMinimum: Double, gap: Double, sideBySide: Bool = true) -> Double {
        guard sideBySide, panes > 1 else { return minimumPageWidth }
        return max(minimumPageWidth, Double(panes) * paneMinimum + Double(panes - 1) * gap)
    }

    /// `width` within the limits, and narrow enough that `container` (the content area, gap
    /// included) keeps `pages` for the pages.
    public static func clamp(_ width: Double, container: Double, gap: Double, pages: Double = minimumPageWidth) -> Double {
        let room = container - gap - pages
        return max(minimum, min(width, maximum, room))
    }

    /// Whether the panel fits beside the pages at all.
    public static func fits(container: Double, gap: Double, pages: Double = minimumPageWidth) -> Bool {
        container - gap - pages >= minimum
    }
}
