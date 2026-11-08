import CraCore
import Foundation
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
        #expect(inbox?.mails.map(\.from) == ["Ada Lovelace", "Billing"])
        #expect(inbox?.mails.map(\.subject) == ["Lunch & plans", "Invoice #42"])
    }

    /// Arc's card row: sender and age, subject, then the feed's opening lines; a click opens the mail.
    @Test func readsEachMailsSnippetTimeAndLink() throws {
        let feed = """
        <feed><fullcount>1</fullcount><entry><title>Run failed: CI</title><summary>CI workflow run CI: No jobs were run &amp; more</summary>
        <link rel="alternate" href="https://mail.google.com/mail/u/0?account_id=a@b.com&amp;message_id=19a&amp;view=conv&amp;extsrc=atom" type="text/html" />
        <modified>2026-11-08T07:31:00Z</modified><issued>2026-11-08T07:30:00Z</issued><author><name>Victor</name></author></entry></feed>
        """
        let mail = try #require(GmailPreview.parse(feed)?.mails.first)
        #expect(mail.snippet == "CI workflow run CI: No jobs were run & more")
        #expect(mail.received == Date(timeIntervalSince1970: 1_794_123_000))
        #expect(mail.link == "https://mail.google.com/mail/u/0?account_id=a@b.com&message_id=19a&view=conv&extsrc=atom")
    }

    @Test func listsTheWholeFeed() {
        let entries = (1...20).map { "<entry><title>\($0)</title><author><name>S</name></author></entry>" }.joined()
        #expect(GmailPreview.parse("<feed><fullcount>31</fullcount>\(entries)</feed>")?.mails.count == 20)
    }

    /// The ages Arc printed on 8 Nov 2026: "50s", "1m", "3h", "10h".
    static let ages: [(Double, String)] = [(50, "50s"), (61, "1m"), (10_859, "3h"), (36_000, "10h"), (172_805, "2d"), (-5, "0s")]

    @Test(arguments: ages)
    func agesLikeArc(seconds: Double, label: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(GmailPreview.age(of: now.addingTimeInterval(-seconds), now: now) == label)
    }

    @Test func composesInTheFavoritesAccount() {
        #expect(GmailPreview.composeURL(for: "https://mail.google.com/mail/u/1/#inbox") == "https://mail.google.com/mail/u/1/#inbox?compose=new")
        #expect(GmailPreview.composeURL(for: "https://example.com/") == nil)
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
