import CraCore
import Testing

struct ImportReportTests {
    static func page(_ url: String, _ kind: ImportKind = .tabs) -> ImportSkip {
        ImportSkip(title: "Settings", url: url, reason: .notAWebPage, kind: kind)
    }

    /// After an import each tile says how much came over of everything the source had of its
    /// kind, so a tab left out shows as one short of the total.
    @Test func allCopiedReadsTheWholeTotal() {
        #expect(ImportReport(.tabs, copied: 198).summary == "198 of 198 tabs")
        #expect(ImportReport(.tabs, copied: 198).total == 198)
    }

    @Test func aSkippedItemCountsInTheTotalOnly() {
        let report = ImportReport(.tabs, copied: 197, skipped: [Self.page("chrome://settings/")])
        #expect(report.total == 198)
        #expect(report.summary == "197 of 198 tabs")
    }

    @Test func oneIsSingular() {
        #expect(ImportReport(.tabs, copied: 1).summary == "1 of 1 tab")
        #expect(ImportReport(.tabs, copied: 0, skipped: [Self.page("about:blank")]).summary == "0 of 1 tab")
        #expect(ImportReport(.favorites, copied: 1).summary == "1 of 1 favorite")
    }

    /// Each tile counts its own kind, so no number mixes favorites with tabs; the archive's are tabs, as its tile
    /// says before the import.
    @Test(arguments: [
        (ImportKind.tabs, "42 of 42 tabs"),
        (.favorites, "42 of 42 favorites"),
        (.archive, "1500 of 1501 tabs"),
    ])
    func eachKindReadsInItsOwnWords(_ kind: ImportKind, _ text: String) {
        let report = kind == .archive ? ImportReport(kind, copied: 1500, skipped: [Self.page("https://example.com/old", .archive)])
            : ImportReport(kind, copied: 42)
        #expect(report.summary == text)
    }

    @Test(arguments: [(ImportKind.tabs, "No tabs"), (.favorites, "No favorites"), (.archive, "No tabs")])
    func nothingReadSaysSo(_ kind: ImportKind, _ text: String) {
        #expect(ImportReport(kind).summary == text)
    }

    /// A tile too narrow for "1500 of 1501 tabs ›" drops the noun, at the same font size as its
    /// neighbours; with nothing read it keeps its words.
    @Test func theShortWordingDropsTheNoun() {
        #expect(ImportReport(.archive, copied: 1500, skipped: [Self.page("https://example.com/old", .archive)]).shortSummary == "1500 of 1501")
        #expect(ImportReport(.favorites, copied: 1).shortSummary == "1 of 1")
        #expect(ImportReport(.tabs).shortSummary == "No tabs")
    }

    /// A file that could not be read is one row, and adds nothing to the total: how many tabs it
    /// held is unknown.
    @Test func anUnreadableFileIsARowWithoutACount() {
        let file = ImportSkip.unreadable("Open tabs", file: "/Sessions/Session_1")
        let report = ImportReport(.tabs, copied: 3, skipped: [file])
        #expect(report.total == 3 && report.summary == "3 of 3 tabs")
        #expect(file.title == "Open tabs" && file.url == "/Sessions/Session_1" && file.reason == .unreadable && file.kind == .tabs)
        #expect(ImportReport(.tabs, skipped: [file]).summary == "No tabs")
    }

    /// A tile shows when it has something to count or to list: a profile whose only open tabs
    /// file can't be read still gets its tabs tile, so the row is seen.
    @Test func aTileWithOnlySkipsStillShows() {
        #expect(ImportReport(.tabs, skipped: [.unreadable("Open tabs", file: "")]).isShown)
        #expect(ImportReport(.archive, skipped: [Self.page("chrome://settings/", .archive)]).isShown)
        #expect(ImportReport(.favorites, copied: 2).isShown)
        #expect(!ImportReport(.favorites).isShown)
    }

    /// Each skip lands on the tile of its kind.
    @Test func eachSkipGoesToItsKindsTile() {
        let tab = Self.page("chrome://newtab/"), favorite = Self.page("about:blank", .favorites), archived = Self.page("file:///a", .archive)
        let reports = ImportReports(tabs: 5, favorites: [(list: "home", url: "https://a.example/")], archive: 7,
                                    skipped: [(list: "home", skip: tab), (list: "home", skip: favorite), (list: "", skip: archived)])
        #expect(reports[.tabs] == ImportReport(.tabs, copied: 5, skipped: [tab]))
        #expect(reports[.favorites] == ImportReport(.favorites, copied: 1, skipped: [favorite]))
        #expect(reports[.archive] == ImportReport(.archive, copied: 7, skipped: [archived]))
    }

    /// Spaces that share favorites (an Arc Top Apps container, Zen's Essentials, Yab's shared tiles) each
    /// carry the same list: a favorite counts, and is listed, once per list and address.
    @Test func aSharedFavoriteCountsOnce() {
        let left = Self.page("about:blank", .favorites)
        let reports = ImportReports(tabs: 0, favorites: [(list: "essentials", url: "https://a.example/"), (list: "essentials", url: "https://b.example/"),
                                                         (list: "essentials", url: "https://a.example/")],
                                    archive: 0, skipped: [(list: "essentials", skip: left), (list: "essentials", skip: left)])
        #expect(reports[.favorites].copied == 2 && reports[.favorites].skipped == [left])
        #expect(reports[.favorites].summary == "2 of 3 favorites")
    }

    /// Two spaces that each own the same favorite bring two: the source holds
    /// two, whatever profile they sign in on.
    @Test func theSameFavoriteInTwoListsCountsTwice() {
        let left = Self.page("about:blank", .favorites)
        let reports = ImportReports(tabs: 0, favorites: [(list: "space-1", url: "https://mail.example/"), (list: "space-2", url: "https://mail.example/")],
                                    archive: 0, skipped: [(list: "space-1", skip: left), (list: "space-2", skip: left)])
        #expect(reports[.favorites].copied == 2 && reports[.favorites].skipped == [left, left])
        #expect(reports[.favorites].summary == "2 of 4 favorites")
    }

    @Test(arguments: [
        (ImportSkipReason.notAWebPage, "Not a web page"),
        (.olderArchive(limit: 1500), "Older than the newest 1500 archived tabs"),
        (.notALiveItem, "Not one of the live folder's items"),
        (.unreadable, "Could not be read"),
        (.craAddress, "Cra's own address"),
        (.onlyInItsBrowser, "Only works in the browser it came from"),
    ])
    func eachReasonReads(_ reason: ImportSkipReason, _ text: String) {
        #expect(reason.text == text)
    }

    /// Only an item with an address was ever a tab: one without is not counted or listed.
    @Test func aRefusedPageNeedsAnAddress() {
        #expect(ImportSkip.notAWebPage("chrome://settings/", title: "Settings") == ImportSkip(title: "Settings", url: "chrome://settings/", reason: .notAWebPage))
        #expect(ImportSkip.notAWebPage("chrome://settings/", title: "Settings", kind: .archive)?.kind == .archive)
        #expect(ImportSkip.notAWebPage(nil, title: "New Tab") == nil)
        #expect(ImportSkip.notAWebPage("", title: "New Tab") == nil)
    }

    /// An importer that still takes web pages only (Dia's archive) lists what it refuses as every
    /// importer does: a blank or new tab page not at all, cra: and blob: for their own reasons.
    @Test func aPageRefusedForNotBeingWebFollowsTheAddressRule() {
        #expect(ImportSkip.notAWebPage("about:blank", title: "New Tab") == nil)
        #expect(ImportSkip.notAWebPage("chrome://newtab/", title: "New Tab") == nil)
        #expect(ImportSkip.notAWebPage("cra://settings", title: "Settings")?.reason == .craAddress)
        #expect(ImportSkip.notAWebPage("blob:https://example.com/5f1c", title: "Download")?.reason == .onlyInItsBrowser)
    }

    /// Why an import leaves an address behind (#742): every address with something behind it is
    /// listed; a blank or new tab page was never a tab and isn't, so an empty tab doesn't read as a loss.
    @Test(arguments: [
        ("https://example.com/", nil), ("file:///Users/me/notes.html", nil), ("javascript:void(0)", nil), ("chrome://settings/", nil),
        ("about:blank", nil), ("about:newtab", nil), ("about:home", nil), ("chrome://newtab/", nil), ("", nil),
        ("cra://settings", ImportSkipReason.craAddress), (" CRA:debug ", .craAddress),
        ("blob:https://example.com/5f1c", .onlyInItsBrowser), ("place:sort=8&maxResults=10", .onlyInItsBrowser),
    ] as [(String, ImportSkipReason?)])
    func whyAnAddressIsLeftOut(_ url: String, _ reason: ImportSkipReason?) {
        #expect(ImportedAddress.leftOut(url) == reason)
        if reason != nil { #expect(!ImportedAddress.keeps(url)) }
    }

    /// The skip row for a left-out address carries its reason; a kept address, a blank or new tab
    /// page and no address give none.
    @Test func aLeftOutAddressIsListed() {
        #expect(ImportSkip.leftOut("cra://settings", title: "Settings") == ImportSkip(title: "Settings", url: "cra://settings", reason: .craAddress))
        #expect(ImportSkip.leftOut("blob:https://example.com/5f1c", title: "Download", kind: .favorites)
                == ImportSkip(title: "Download", url: "blob:https://example.com/5f1c", reason: .onlyInItsBrowser, kind: .favorites))
        #expect(ImportSkip.leftOut("chrome://settings/", title: "Settings") == nil)
        #expect(ImportSkip.leftOut("about:blank", title: "New Tab") == nil)
        #expect(ImportSkip.leftOut(nil, title: "New Tab") == nil)
    }

    /// Copy puts the list on the pasteboard as plain text: one item a line, its title, address and
    /// reason apart by tabs, so it pastes into a message or a spreadsheet.
    @Test func theListCopiesAsPlainText() {
        let report = ImportReport(.tabs, copied: 1, skipped: [
            ImportSkip(title: "Settings", url: "chrome://settings/", reason: .notAWebPage),
            ImportSkip(title: "", url: "file:///Users/me/a.pdf", reason: .notAWebPage),
        ])
        #expect(report.plainText == "Settings\tchrome://settings/\tNot a web page\n\tfile:///Users/me/a.pdf\tNot a web page")
    }
}
