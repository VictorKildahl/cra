import CraCore
import Foundation
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
        #expect(TidyDownloads.clean("Ladybug.png", original: "AdobeStock_1.jpeg") == "Ladybug.jpeg")
        #expect(TidyDownloads.clean("Notes", original: "notes_v2") == "Notes")
    }

    @Test(arguments: [
        ("Notes.txt", "notes_v2", "Notes"),
        ("Notes.TXT", "notes_v2.pdf", "Notes.pdf"),
        ("Notes.pdf", "notes_v2.PDF", "Notes.PDF"),
        ("Archive.tar.zip", "archive_old.tar.gz", "Archive.tar.gz"),
        ("Release.2026.pdf", "report_old.txt", "Release.2026.txt"),
        ("Notes.", "notes_v2.pdf", "Notes.pdf"),
        ("Notes.txt", "notes_v2.", "Notes."),
        ("Notes", "notes_v2.", "Notes."),
        ("Notes.txt", ".old", "Notes.old"),
        ("\"Résumé  📄.txt\"", "notes_v2.PDF", "Résumé 📄.PDF"),
    ])
    func cleanRestoresOnlyTheOriginalFinalDotSuffix(answer: String, original: String, expected: String) {
        #expect(TidyDownloads.clean(answer, original: original) == expected)
    }

    @Test(arguments: [
        ("Notes.txt", "Notes"),
        ("Notes.txt", "Notes.pdf"),
        ("Notes.txt", "Notes."),
        (".hidden.pdf", "a.pdf"),
        ("..", "a.pdf"),
    ])
    func cleanRejectsUnchangedOrHiddenNamesAfterSuffixRestoration(answer: String, original: String) {
        #expect(TidyDownloads.clean(answer, original: original) == nil)
    }

    @Test func cleanChecksTheLengthOfTheRestoredFilename() {
        let stem = String(repeating: "x", count: 76)
        #expect(TidyDownloads.clean(stem + ".jpeg", original: "a.pdf") == stem + ".pdf")
        #expect(TidyDownloads.clean(stem + "x.jpeg", original: "a.pdf") == nil)
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
        let taken: Set = ["Report.pdf", "Report (1).pdf", "Notes"]
        #expect(TidyDownloads.unique("Report.pdf", existing: taken.contains) == "Report (2).pdf")
        #expect(TidyDownloads.unique("Notes", existing: taken.contains) == "Notes (1)")
        #expect(TidyDownloads.unique("New.pdf", existing: taken.contains) == "New.pdf")
    }

    @Test(arguments: [
        ("Archive.tar.gz", "Archive.tar (1).gz"),
        ("Notes.", "Notes (1)."),
        ("Résumé 📄.PDF", "Résumé 📄 (1).PDF"),
    ])
    func uniqueInsertsTheNumberBeforeTheFinalDotSuffix(name: String, expected: String) {
        #expect(TidyDownloads.unique(name, existing: { $0 == name }) == expected)
    }

    @Test func uniqueCanUseTheHundredthCandidate() {
        #expect(TidyDownloads.unique("Report.pdf", existing: { $0 != "Report (100).pdf" }) == "Report (100).pdf")
    }

    @Test func uniqueStopsWhenAllHundredCandidatesAreOccupied() {
        var checked: [String] = []
        #expect(TidyDownloads.unique("Report.pdf", existing: {
            checked.append($0)
            return true
        }) == nil)
        #expect(checked.count == 101)
        #expect(checked.last == "Report (100).pdf")
    }

    @Test func uniqueChecksActualSiblingFilesAndRefusesExhaustion() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let contents = Data("existing download".utf8)
        let occupied = ["Report.pdf"] + (1...100).map { "Report (\($0)).pdf" }
        for name in occupied.prefix(2) { try contents.write(to: folder.appendingPathComponent(name)) }
        let exists: (String) -> Bool = { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        #expect(TidyDownloads.unique("Report.pdf", existing: exists) == "Report (2).pdf")
        for name in occupied.dropFirst(2) { try contents.write(to: folder.appendingPathComponent(name)) }
        #expect(TidyDownloads.unique("Report.pdf", existing: exists) == nil)
    }
}
