import Foundation

/// Arc Max's Tidy Downloads (renameDownloads), on the Mac's own Apple Intelligence model: a finished
/// download gets a short, readable name from its file name, the tab's title and the site (Arc 1.171's
/// beginRename(…defaultFilename:sourceUrl:webContentsTitle:referrerTitle:)). This decides what the
/// model is asked and which answers may become a file's name; renaming the file is the app's.
public enum TidyDownloads {
    static let maximumLength = 80

    public static let instructions = """
    You rename files as they finish downloading, so they are helpful, concise and readable: two to four \
    words. Keep names that already say what the file is mostly as they are. For names that say nothing \
    (image.png, download.pdf, IDs), use what the tab's title or the website says. Remove machine-made \
    cruft such as IDs, (1), (copy), stock-photo prefixes and seconds in times; write dates short and human \
    ("Aug 14"); fix casing and spacing. Answer with the new name only, keeping the file's extension.
    """

    /// Pairs showing the style (made up for Cra, in the spirit of Arc's).
    public static let examples: [(file: String, title: String, site: String, name: String)] = [
        ("Cra-0.1.30.dmg", "Cra · A browser like Arc", "crabrowser.app", "Cra 0.1.30.dmg"),
        ("invoice_884213_2026-10-02.pdf", "Your invoice from Acme Hosting - Gmail", "mail.google.com", "Acme Hosting Invoice Oct 2.pdf"),
        ("IMG_20260912_141533.jpg", "Photos from the beach trip - Google Drive", "drive.google.com", "Beach Trip Sep 12.jpg"),
        ("image.png", "Logo feedback - Slack", "app.slack.com", "Logo Feedback.png"),
        ("Screenshot 2026-09-26 at 11.12.18 PM.png", "DM with Sara - X", "x.com", "Sep 26 Screenshot from Sara.png"),
        ("annual-report-final(1).pdf", "Annual report 2025 | Nordic Rail", "nordicrail.com", "Nordic Rail Annual Report 2025.pdf"),
    ]

    /// The request: the file's name, the tab it came from and the site.
    public static func prompt(file: String, tabTitle: String, url: String) -> String {
        var lines = ["Examples, as 'file', 'tab title', 'site' → new name:"]
        for e in examples { lines.append("'\(e.file)', '\(e.title)', '\(e.site)' → \(e.name)") }
        lines.append("")
        lines.append("Rename: '\(file)', '\(clip(tabTitle, 160))', '\(host(url))'")
        return lines.joined(separator: "\n")
    }

    /// The model's answer as a file name in the same folder, or nil when it isn't usable: empty,
    /// hidden (".…"), the same name, or with path characters. The original extension stays.
    public static func clean(_ answer: String, original: String) -> String? {
        var s = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        s = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’`")))
        s = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Arc 1.171's 0x1002d488c/0x1002d6b38: replace the model's final-dot suffix
        // with the original's, including an empty suffix or a trailing dot.
        if let dot = s.lastIndex(of: ".") { s = String(s[..<dot]) }
        guard !s.isEmpty, !s.hasPrefix(".") else { return nil }
        s += original.lastIndex(of: ".").map { String(original[$0...]) } ?? ""
        guard s.count <= maximumLength, s != original else { return nil }
        return s
    }

    /// A free name in `existing` for `name`: "Report.pdf", then "Report 2.pdf", "Report 3.pdf"…
    public static func unique(_ name: String, existing: (String) -> Bool) -> String {
        guard existing(name) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        for n in 2...999 {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !existing(candidate) { return candidate }
        }
        return name
    }

    static func host(_ url: String) -> String {
        guard let h = URL(string: url)?.host?.lowercased() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static func clip(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n)) }
}
