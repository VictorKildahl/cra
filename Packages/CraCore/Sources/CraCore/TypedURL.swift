import Foundation

/// What typed text means as an address: the command bar's rule for telling a URL from a search,
/// and the scheme it gets when it has none.
public enum TypedURL {
    public static func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.contains(" ") { return false }
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil { return true }
        if t.hasPrefix("localhost") || t.hasPrefix("about:") || t.hasPrefix("view-source:") || t.hasPrefix("data:") || t.hasPrefix("file:") { return true }
        if t.range(of: #"^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil { return true }
        // host.tld[:port][/path]
        return t.range(of: #"^[\w\-]+(\.[\w\-]+)+(:\d+)?(/\S*)?$"#, options: .regularExpression) != nil
    }

    public static func fromInput(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil { return t }
        // Before the bare-scheme check: "localhost:3000" is a host and port, not a "localhost:" URL.
        if t.hasPrefix("localhost") || t.range(of: #"^(\d{1,3}\.){3}\d{1,3}"#, options: .regularExpression) != nil {
            return "http://" + t
        }
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#, options: .regularExpression) != nil { return t }
        return "https://" + t
    }

    /// Arc's Edit Pinned URL dialog: the address a pinned tab or favorite gets from the typed text,
    /// or nil when it isn't one (a search, a script, a web address without a host).
    public static func pinnedDestination(_ s: String) -> String? {
        let input = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeURL(input) else { return nil }
        let url = fromInput(input)
        guard let parsed = URL(string: url) else { return nil }
        if ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host?.isEmpty != false { return nil }
        return url
    }
}
