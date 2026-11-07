import CraCore
import Testing

/// Arc's Previews for a Gmail favorite, from Gmail's Atom feed of unread mail.
struct GmailPreviewTests {
    static let feed = """
    <?xml version="1.0" encoding="UTF-8"?><feed version="0.3" xmlns="http://purl.org/atom/ns#"><title>Gmail - Inbox</title>
    <fullcount>2</fullcount><entry><title>Lunch &amp; plans</title><summary>…</summary><author><name>Ada Lovelace</name><email>ada@example.com</email></author></entry>
    <entry><title>Invoice #42</title><author><name>Billing</name></author></entry></feed>
    """

    @Test func readsTheUnreadMail() {
        let inbox = GmailPreview.parse(Self.feed)
        #expect(inbox?.unread == 2)
        #expect(inbox?.mails == [.init(from: "Ada Lovelace", subject: "Lunch & plans"), .init(from: "Billing", subject: "Invoice #42")])
    }

    @Test func anEmptyInboxIsArcsExhale() {
        let inbox = GmailPreview.parse(#"<feed><fullcount>0</fullcount></feed>"#)
        #expect(inbox == .init(unread: 0, mails: []))
        #expect(GmailPreview.emptyText == "No unread emails, you can exhale!")
    }

    @Test func aSignInPageIsNoFeed() {
        #expect(GmailPreview.parse("<html><body>Sign in</body></html>") == nil)
    }

    @Test(arguments: [("https://mail.google.com/mail/u/0/#inbox", "https://mail.google.com/mail/u/0/feed/atom"),
                      ("https://mail.google.com/mail/u/2/", "https://mail.google.com/mail/u/2/feed/atom"),
                      ("https://mail.google.com/", "https://mail.google.com/mail/u/0/feed/atom")])
    func theFeedOfTheFavoritesAccount(favorite: String, feed: String) {
        #expect(GmailPreview.feedURL(for: favorite) == feed)
    }

    @Test func otherSitesHaveNone() {
        #expect(GmailPreview.feedURL(for: "https://www.youtube.com/") == nil)
    }
}
