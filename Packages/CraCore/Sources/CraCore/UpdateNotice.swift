/// What the software updater has to say (Arc's SidebarBanner `updateAvailable`), and when that
/// goes into a toast. The banner sits in the sidebar, so a window with its sidebar hidden would
/// never show it (X DM 8 Nov 2026: "if I'm using the sidebar in the hidden, I may not even notice
/// it"). There Cra says it with its one toast (Arc's ShinyToast), the way Arc's "New Tab Created"
/// takes the toast only while the sidebar that would show the new row is hidden.
public enum UpdateNotice: Equatable, Sendable {
    /// Downloaded, one restart away.
    case ready(version: String)
    /// Found while automatic updates are off.
    case available(version: String)

    /// The banner's news: a downloaded update before a found one, nothing once its ✕ was pressed
    /// (that hides it until the next launch, as in Arc).
    public static func current(ready: String?, found: String?, dismissed: Bool) -> UpdateNotice? {
        guard !dismissed else { return nil }
        if let ready { return .ready(version: ready) }
        if let found { return .available(version: found) }
        return nil
    }

    public var version: String {
        switch self {
        case .ready(let version), .available(let version): version
        }
    }

    /// Arc's banner title, also the toast's text.
    public var title: String {
        switch self {
        case .ready: "An update is ready!"
        case .available: "New Cra Version Available"
        }
    }

    public var subtitle: String {
        switch self {
        case .ready: "Click to restart"
        case .available(let version): "Cra \(version)"
        }
    }

    /// The toast's button: what clicking the banner does.
    public var button: String {
        switch self {
        case .ready: "Restart"
        case .available: "Update"
        }
    }

    /// The notice to toast in the front window, or nil. Only while that window's sidebar is hidden
    /// (shown, the banner says it), and once a launch for each notice (`told`: the last one
    /// toasted), so hiding and showing the sidebar doesn't bring it back. A later notice (the
    /// found update finished downloading, a newer release) is news again.
    public static func toast(_ notice: UpdateNotice?, told: UpdateNotice?, sidebarVisible: Bool) -> UpdateNotice? {
        guard let notice, notice != told, !sidebarVisible else { return nil }
        return notice
    }
}
