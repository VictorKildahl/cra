import CraCore
import Testing

/// Tidy Downloads: what the model is asked about a finished download and which answers rename it.
struct TidyDownloadsTests {
    @Test func promptGivesFileTabAndSite() {
        let p = TidyDownloads.prompt(file: "folio_6691488.PDF", tabTitle: "Your Guest Stay Folio", url: "https://mail.google.com/mail/u/0/#inbox")
        #expect(p.hasPrefix("Examples, as 'file', 'tab title', 'site' → new name:\n'Cra-0.1.30.dmg'"))
        #expect(p.hasSuffix("Rename: 'folio_6691488.PDF', 'Your Guest Stay Folio', 'mail.google.com'"))
    }

    @Test func cleanKeepsTheExtension() {
        #expect(TidyDownloads.clean("Hello World Master", original: "Hello-World-master.zip") == "Hello World Master.zip")
        #expect(TidyDownloads.clean("\"Guest Stay Folio Aug 14.pdf\"", original: "folio_6691488.PDF") == "Guest Stay Folio Aug 14.PDF")
        #expect(TidyDownloads.clean("Ladybug.png", original: "AdobeStock_1.jpeg") == "Ladybug.png.jpeg")
        #expect(TidyDownloads.clean("Notes", original: "notes_v2") == "Notes")
    }

    @Test func cleanRefusesUnusableNames() {
        #expect(TidyDownloads.clean("", original: "a.pdf") == nil)
        #expect(TidyDownloads.clean(".pdf", original: "a.pdf") == nil)
        #expect(TidyDownloads.clean(".hidden", original: "notes") == nil)
        #expect(TidyDownloads.clean("a.pdf", original: "a.pdf") == nil)
        #expect(TidyDownloads.clean(String(repeating: "x", count: 90), original: "a.pdf") == nil)
        // Path characters can't move the file elsewhere.
        #expect(TidyDownloads.clean("../../etc/Report", original: "r.pdf") == nil)
        #expect(TidyDownloads.clean("Q3/Q4 Report", original: "r.pdf") == "Q3-Q4 Report.pdf")
        #expect(TidyDownloads.clean("Q3: Plan", original: "plan.key") == "Q3- Plan.key")
    }

    @Test func uniqueNamesDontOverwrite() {
        let taken: Set = ["Report.pdf", "Report 2.pdf", "Notes"]
        #expect(TidyDownloads.unique("Report.pdf", existing: taken.contains) == "Report 3.pdf")
        #expect(TidyDownloads.unique("Notes", existing: taken.contains) == "Notes 2")
        #expect(TidyDownloads.unique("New.pdf", existing: taken.contains) == "New.pdf")
    }
}
