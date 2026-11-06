import CraCore
import Testing

/// A closed folder keeps its open tab in sight (Arc 1.171, GitHub #85).
struct FolderPeekTests {
    // Pinned: outer ▸ inner ▸ tab, both closed unless a test opens them.
    let outer = "outer", inner = "inner", tab = "tab", other = "other"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func outermostClosedFolderHostsTheTab() {
        #expect(FolderPeek.host(folders: [outer, inner], isExpanded: { _ in false }) == outer)
        #expect(FolderPeek.host(folders: [outer, inner], isExpanded: { $0 == outer }) == inner)
        #expect(FolderPeek.host(folders: [outer, inner], isExpanded: { _ in true }) == nil)
        #expect(FolderPeek.host(folders: [String](), isExpanded: { _ in false }) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func openingATabInClosedFoldersPeeksItUnderTheOutermost() {
        let peeks = FolderPeek.opening(tab, folders: [outer, inner], isExpanded: { _ in false }, peeks: [:])
        #expect(peeks == [outer: [tab]])
        // Again: nothing changes. Another tab joins the same peek, the first one stays (Arc).
        #expect(FolderPeek.opening(tab, folders: [outer, inner], isExpanded: { _ in false }, peeks: peeks) == peeks)
        #expect(FolderPeek.opening(other, folders: [outer], isExpanded: { _ in false }, peeks: peeks) == [outer: [tab, other]])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func openingATabInOpenFoldersPeeksNothing() {
        #expect(FolderPeek.opening(tab, folders: [outer, inner], isExpanded: { _ in true }, peeks: [:]).isEmpty)
        #expect(FolderPeek.opening(tab, folders: [String](), isExpanded: { _ in false }, peeks: [:]).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func openingTheFolderDropsItsPeekClosingKeepsTheOpenTab() {
        let peeks = [outer: [tab, other]]
        #expect(FolderPeek.expanding(outer, true, openTabInside: tab, peeks: peeks).isEmpty)
        #expect(FolderPeek.expanding(outer, false, openTabInside: tab, peeks: [:]) == [outer: [tab]])
        #expect(FolderPeek.expanding(outer, false, openTabInside: nil, peeks: peeks).isEmpty)
        // Other folders' peeks are left alone.
        #expect(FolderPeek.expanding(inner, true, openTabInside: nil, peeks: peeks) == peeks)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/213"))
    func aClickOpensAClosedFolderEvenWithItsOpenTabInSight() {
        #expect(FolderPeek.clickOpens(expanded: false))
        #expect(!FolderPeek.clickOpens(expanded: true))
        // Opened, the folder shows all of it; closed again, only the open tab stays in sight.
        #expect(FolderPeek.expanding(outer, true, openTabInside: tab, peeks: [outer: [tab]]).isEmpty)
        #expect(FolderPeek.expanding(outer, false, openTabInside: tab, peeks: [:]) == [outer: [tab]])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func closingAFolderKeepsOnlyTheOpenTab() {
        // Closing it keeps only the open tab: a peek of another tab goes, the open tab's stays.
        #expect(FolderPeek.expanding(outer, false, openTabInside: nil, peeks: [outer: [other]]).isEmpty)
        #expect(FolderPeek.expanding(outer, false, openTabInside: tab, peeks: [outer: [tab, other]]) == [outer: [tab]])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func closingATabDropsItFromEveryPeek() {
        let peeks = [outer: [tab, other], inner: [tab]]
        #expect(FolderPeek.removing(tab, peeks: peeks) == [outer: [other]])
        #expect(FolderPeek.removing(other, peeks: [outer: [other]]).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"))
    func listedRowsFollowTheSidebarAndSkipTabsThatLeft() {
        let peeks = [outer: [other, tab, "moved away"]]
        #expect(FolderPeek.listed(in: outer, peeks: peeks, tabsInside: ["a", tab, other]) == [tab, other])
        #expect(FolderPeek.listed(in: inner, peeks: peeks, tabsInside: [tab]).isEmpty)
    }
}
