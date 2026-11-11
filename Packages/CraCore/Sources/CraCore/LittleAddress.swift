import Foundation

/// What a Little Window's address pill shows for its page (Arc 1.172.1, 10 Nov 2026: for
/// http://cra-measure.lvh.me:47110/page?e=link1 the pill read `cra-measure.lvh.me`, and an open
/// padlock took the magnifier's place, as the page isn't served over https; #330).
public enum LittleAddress {
    /// The host alone, without a leading `www.`, as the main window's URL pill shows it. nil for a
    /// page with no host to show (about:blank, an internal page, a file), which the caller prints as
    /// it was.
    public static func host(of url: String) -> String? {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = parsed.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.contains(":") ? "[\(host)]" : host
    }

    /// A page served over plain http: Arc's `hasInsecureContext`. Pages that aren't served over a
    /// network at all (about:blank, a file, an internal page) are not warned about.
    public static func isInsecure(_ url: String) -> Bool {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "http" else { return false }
        return parsed.host?.isEmpty == false
    }
}
