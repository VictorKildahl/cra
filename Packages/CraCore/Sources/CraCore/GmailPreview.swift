import Foundation

/// Arc's Previews (Settings ▸ General ▸ Previews; Arc 1.172.1, hovered on Victor's Gmail favorite,
/// 7 Nov 2026): hovering a Gmail favorite shows its unread mail in a dark card under the tile
/// instead of the name tooltip, "No unread emails, you can exhale! 🍃" when there is none. Cra reads
/// Gmail's Atom feed of the inbox's unread mail with the space's own sign-in; nothing else is asked.
public enum GmailPreview {
    public struct Mail: Equatable, Sendable {
        public var from: String
        public var subject: String
        public init(from: String, subject: String) { (self.from, self.subject) = (from, subject) }
    }

    public struct Inbox: Equatable, Sendable {
        public var unread: Int
        public var mails: [Mail]
        public init(unread: Int, mails: [Mail]) { (self.unread, self.mails) = (unread, mails) }
    }

    /// Arc's line for an inbox with nothing unread.
    public static let emptyText = "No unread emails, you can exhale!"

    /// The feed for a Gmail favorite's account (u/0 unless the favorite names another).
    public static func feedURL(for favorite: String) -> String? {
        guard let u = URL(string: favorite), u.host == "mail.google.com" else { return nil }
        let parts = u.path.split(separator: "/")
        let account = parts.firstIndex(of: "u").flatMap { parts.indices.contains($0 + 1) ? String(parts[$0 + 1]) : nil } ?? "0"
        return "https://mail.google.com/mail/u/\(account)/feed/atom"
    }

    /// The feed's unread count and its newest mails (sender, subject), at most `limit`.
    public static func parse(_ xml: String, limit: Int = 5) -> Inbox? {
        guard xml.contains("<feed") else { return nil }
        let count = Int(first("fullcount", in: xml) ?? "") ?? 0
        var mails: [Mail] = []
        var rest = Substring(xml)
        while mails.count < limit, let start = rest.range(of: "<entry>"), let end = rest.range(of: "</entry>", range: start.upperBound..<rest.endIndex) {
            let entry = String(rest[start.upperBound..<end.lowerBound])
            let author = first("author", in: entry).flatMap { first("name", in: $0) } ?? ""
            mails.append(Mail(from: unescape(author), subject: unescape(first("title", in: entry) ?? "")))
            rest = rest[end.upperBound...]
        }
        return Inbox(unread: count, mails: mails)
    }

    private static func first(_ tag: String, in s: String) -> String? {
        guard let a = s.range(of: "<\(tag)>"), let b = s.range(of: "</\(tag)>", range: a.upperBound..<s.endIndex) else { return nil }
        return String(s[a.upperBound..<b.lowerBound])
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
    }
}
