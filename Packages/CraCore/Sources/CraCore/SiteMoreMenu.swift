/// The rows of the site menu's "…" (the address bar's site button, then "…"), in groups between separators.
/// Arc 1.172.2's rows and order, with Cra's "Clear Site Data" after Arc's two clearing rows (#853): the
/// page's whole origin (storage, IndexedDB, service workers and cookies) in one click.
public enum SiteMoreMenu {
    public enum Row: String, Sendable, CaseIterable {
        case clearCache = "Clear Cache"
        case clearCookies = "Clear Cookies"
        case clearSiteData = "Clear Site Data"
        case manageBoosts = "Manage Boosts…"
        case newBoost = "New Boost…"
        case manageExtensions = "Manage Extensions…"
        case addExtension = "Add Extension…"
        case allSiteSettings = "All Site Settings"

        public var title: String { rawValue }
    }

    public static let groups: [[Row]] = [
        [.clearCache, .clearCookies, .clearSiteData],
        [.manageBoosts, .newBoost],
        [.manageExtensions, .addExtension],
        [.allSiteSettings],
    ]
}
