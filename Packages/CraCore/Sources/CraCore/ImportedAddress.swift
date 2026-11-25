import Foundation

/// Which tabs and bookmarks an import from another browser brings over, by address. Any address
/// comes, as Arc import always had it: files, bookmarklets, the other browser's own pages.
public enum ImportedAddress {
    /// Whether an imported tab or bookmark at `url` comes over. Left out is what can't work after
    /// the import: nothing, a blank or new tab page, a blob: (gone with the browser that made it),
    /// Firefox's place: queries into its own history, and Cra's own cra: commands, which nothing in a
    /// tab may run (an import is data from another app).
    public static func keeps(_ url: String) -> Bool { refusal(url) == nil }

    /// Why an imported tab or bookmark at `url` stays behind, for the import's skipped list: nil when
    /// it comes over, and nil for a blank or new tab page, which was never a tab.
    public static func leftOut(_ url: String) -> ImportSkipReason? {
        if case .listed(let reason) = refusal(url) { return reason }
        return nil
    }

    private enum Refusal: Equatable { case neverATab, listed(ImportSkipReason) }

    private static func refusal(_ url: String) -> Refusal? {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if AppLinks.isBlank(u) || u == "about:newtab" || u == "about:home" { return .neverATab }
        if u.hasPrefix("blob:") || u.hasPrefix("place:") { return .listed(.onlyInItsBrowser) }
        if u.hasPrefix("cra:") { return .listed(.craAddress) }
        guard let slashes = u.range(of: "://"), !["http", "https"].contains(u[..<slashes.lowerBound]) else { return nil }
        // A browser's new tab page: chrome://newtab/, opera://startpage, chrome://vivaldi-webui/startpage.
        let rest = u[slashes.upperBound...], host = rest.prefix { !"/?#".contains($0) }
        return ["newtab", "startpage", "startpageshared"].contains(host) || rest.hasPrefix("vivaldi-webui/startpage") ? .neverATab : nil
    }
}
