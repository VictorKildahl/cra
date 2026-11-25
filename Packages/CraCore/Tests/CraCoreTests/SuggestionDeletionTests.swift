import CraCore
import Foundation
import Testing

/// Arc's Delete Suggestion: the ✕ on a visited page's row in the command bar, and ⌥⌘⌫ on the selected one.
struct SuggestionDeletionTests {
    let t = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Only a visited page's row can be deleted: not a tab, an archived tab, a search, a site or a command.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/779")) func onlyVisitedPagesAreDeleted() {
        #expect(SuggestionDeletion.page(rowID: "hist:https://www.history.com/earthquake") == "https://www.history.com/earthquake")
        for id in ["typed", "tab:\(UUID())", "arch:\(UUID())", "sugg:history vilnius", "sugg:https://example.com/",
                   "top:github.com", "cmd:newTab", "hist:"] {
            #expect(SuggestionDeletion.page(rowID: id) == nil, "\(id)")
        }
    }

    /// ⌥⌘⌫, as Arc's tooltip shows it; not ⌘⌫ or ⌥⌫, which edit the text, nor ⇧⌘⌫ (Clear Browsing Data).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/779")) func theShortcutIsOptionCommandDelete() {
        let cmd = KeyChord.Modifiers.command.rawValue, opt = KeyChord.Modifiers.option.rawValue
        let shift = KeyChord.Modifiers.shift.rawValue
        #expect(SuggestionDeletion.isShortcut(keyCode: 51, modifiers: cmd | opt))
        // Caps Lock or the function key held as well still count.
        #expect(SuggestionDeletion.isShortcut(keyCode: 51, modifiers: cmd | opt | 0x10000 | 0x800000))
        #expect(!SuggestionDeletion.isShortcut(keyCode: 51, modifiers: cmd))
        #expect(!SuggestionDeletion.isShortcut(keyCode: 51, modifiers: opt))
        #expect(!SuggestionDeletion.isShortcut(keyCode: 51, modifiers: cmd | shift))
        #expect(!SuggestionDeletion.isShortcut(keyCode: 51, modifiers: cmd | opt | shift))
        #expect(!SuggestionDeletion.isShortcut(keyCode: 0, modifiers: cmd | opt))
        #expect(SuggestionDeletion.tooltip == "Delete Suggestion (⌥⌘⌫)")
    }

    /// The page leaves the bar's profile's history, with the picks it learned for it; others stay.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/779")) func deletingTakesThePageAndItsLearnedPicks() {
        let page = "https://www.history.com/earthquake", other = "https://example.com/"
        var e = HistoryEntry(url: page, title: "Earthquake", lastVisit: t, visitCount: 3)
        e.profiles = ["default"]
        var o = HistoryEntry(url: other, title: "Example", lastVisit: t, visitCount: 1)
        o.profiles = ["default"]
        let ranking = RankingData(queriesToSelected: ["earth": page, "hist": page, "ex": other], commandUsage: ["newTab": 2])
        let (history, r) = SuggestionDeletion.deleting(page, profile: nil, history: [page: e, other: o], ranking: ranking)
        #expect(history == [other: o])
        #expect(r.queriesToSelected == ["ex": other])
        #expect(r.commandUsage == ["newTab": 2])
    }

    /// A page visited on two profiles leaves only the bar's: the other profile's bar still suggests it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/779")) func anotherProfileKeepsThePage() {
        let page = "https://www.history.com/earthquake"
        var e = HistoryEntry(url: page, title: "Earthquake", lastVisit: t, visitCount: 3)
        e.profiles = ["default", work.uuidString]
        let (history, _) = SuggestionDeletion.deleting(page, profile: work, history: [page: e], ranking: RankingData())
        #expect(history[page]?.profiles == ["default"])
        #expect(CommandBarProfileScope.suggests(history[page]!, on: nil))
        #expect(!CommandBarProfileScope.suggests(history[page]!, on: work))
    }

    /// History saved before Cra kept profiles is suggested everywhere, so deleting it takes it everywhere.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/779")) func anEntryWithoutProfilesGoes() {
        let page = "https://www.history.com/earthquake"
        let e = HistoryEntry(url: page, title: "Earthquake", lastVisit: t, visitCount: 3)
        let (history, _) = SuggestionDeletion.deleting(page, profile: work, history: [page: e], ranking: RankingData())
        #expect(history.isEmpty)
    }

    /// The selection stays on the row's line, as in Chrome's omnibox; past the end it takes the last row.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/779")) func theSelectionStaysOnItsLine() {
        #expect(SuggestionDeletion.selection(afterDeleting: 2, count: 4) == 2)
        #expect(SuggestionDeletion.selection(afterDeleting: 4, count: 4) == 3)
        #expect(SuggestionDeletion.selection(afterDeleting: 0, count: 0) == 0)
    }
}
