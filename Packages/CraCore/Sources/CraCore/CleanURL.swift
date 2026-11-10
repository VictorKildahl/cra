import Foundation

/// What Cra puts on the clipboard for a page's address.
public enum CleanURL {
    /// Query keys that only tell a site where a click came from. Arc's Copy URL leaves them out
    /// ("Copy the current tab's URL without trackers", Arc 1.172's Essential Keyboard Shortcuts).
    static let trackerKeys: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
        "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking", "mkt_tok",
        "oly_anon_id", "oly_enc_id", "vero_id", "vero_conv", "_ga", "_gl", "s_cid", "wickedid", "rb_clickid",
        "ref_src", "ref_url",
    ]

    /// The address without tracking parameters (utm_* and the click ids above). Anything that isn't
    /// an http(s) URL with such a parameter comes back unchanged, byte for byte.
    public static func withoutTrackers(_ url: String) -> String {
        guard let q = url.firstIndex(of: "?"), url.hasPrefix("http://") || url.hasPrefix("https://") else { return url }
        let hash = url[q...].firstIndex(of: "#") ?? url.endIndex
        let pairs = url[url.index(after: q)..<hash].split(separator: "&", omittingEmptySubsequences: false)
        let kept = pairs.filter { pair in
            let key = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let lower = key.lowercased()
            return !(lower.hasPrefix("utm_") || trackerKeys.contains(lower))
        }
        guard kept.count != pairs.count else { return url }
        return String(url[..<q]) + (kept.isEmpty ? "" : "?" + kept.joined(separator: "&")) + String(url[hash...])
    }

    /// The tabs Copy URL (⇧⌘C) copies (#322): with tabs picked in the sidebar, every pick in sidebar
    /// order, as in Arc ("Copied item links"); otherwise the open tab. A pick no longer listed (its
    /// folder closed since) still counts, as ⌘W still closes it, and goes after the listed ones.
    public static func tabsToCopy(picked: Set<UUID>, listed: [UUID], open: UUID?) -> [UUID] {
        guard !picked.isEmpty else { return open.map { [$0] } ?? [] }
        let shown = listed.filter(picked.contains)
        return shown + picked.subtracting(shown).sorted { $0.uuidString < $1.uuidString }
    }

    /// What ⇧⌘C puts on the clipboard for those tabs: each address without trackers, one per line.
    public static func links(_ urls: [String]) -> String {
        urls.map(withoutTrackers).joined(separator: "\n")
    }

    /// Copy URL as Quote: the selection in curly quotes, then a link that scrolls to it and marks it
    /// (a text fragment, `#:~:text=`). Arc links to a quote card on arc.net; nothing leaves the Mac
    /// here, so the link is the page's own. Longer quotes link by their first and last five words.
    public static func quote(_ selection: String, url: String) -> String? {
        let words = selection.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        let text = words.joined(separator: " ")
        let base = withoutTrackers(String(url[..<(url.firstIndex(of: "#") ?? url.endIndex)]))
        let directive = words.count > 10
            ? escape(words.prefix(5).joined(separator: " ")) + "," + escape(words.suffix(5).joined(separator: " "))
            : escape(text)
        return "“\(text)”\n\(base)#:~:text=\(directive)"
    }

    /// Text-fragment escaping: percent-encode everything but unreserved characters, and `-`, `,`
    /// and `&` too, which are the directive's own syntax.
    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
