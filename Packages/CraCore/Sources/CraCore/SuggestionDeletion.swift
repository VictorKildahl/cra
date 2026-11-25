import Foundation

/// Arc's Delete Suggestion in the command bar (#779): hovering a visited page's row shows a ✕ at its end, whose
/// tooltip reads "Delete Suggestion ⌥⌘⌫", and ⌥⌘⌫ deletes the selected row (Arc 1.172, the reporter's capture of
/// 25 Nov 2026; Arc's SearchClient.deleteSuggestion). The page leaves the profile's history, as a deleted history
/// row does in Chrome's omnibox (HistoryService::DeleteURLs): history.json here, Chromium's History in the engine.
public enum SuggestionDeletion {
    private static let historyPrefix = "hist:"

    /// What Arc's ✕ shows in its tooltip, its shortcut as key caps.
    public static let tooltip = "Delete Suggestion (⌥⌘⌫)"

    /// The page a row deletes: a visited page's row ("hist:<address>"). Nothing else in the bar is deleted: tabs,
    /// archived tabs, the typed text, the search engine's suggestions, popular sites and commands.
    public static func page(rowID: String) -> String? {
        guard rowID.hasPrefix(historyPrefix) else { return nil }
        let url = String(rowID.dropFirst(historyPrefix.count))
        return url.isEmpty ? nil : url
    }

    /// ⌥⌘⌫: Delete (key code 51) with ⌥ and ⌘ and neither ⇧ nor ⌃. ⌘⌫ and ⌥⌫ edit the text, ⇧⌘⌫ is Clear Browsing Data.
    public static func isShortcut(keyCode: UInt16, modifiers: UInt) -> Bool {
        keyCode == 51 && KeyChord.Modifiers(rawValue: modifiers).intersection([.shift, .control, .option, .command]) == [.option, .command]
    }

    /// History and learned picks without `url` on `profile` (the bar's). An entry visited on other profiles too
    /// keeps them, so their bars still suggest it; one saved before Cra kept profiles is suggested on every profile,
    /// and goes. The picks learned for the page (a query that opened it) go, so it isn't boosted if visited again.
    public static func deleting(_ url: String, profile: UUID?, history: [String: HistoryEntry],
                                ranking: RankingData) -> (history: [String: HistoryEntry], ranking: RankingData) {
        var h = history
        if var e = h[url], let profiles = e.profiles {
            let left = profiles.filter { $0 != CommandBarProfileScope.key(profile) }
            if left.isEmpty {
                h[url] = nil
            } else {
                e.profiles = left
                h[url] = e
            }
        } else {
            h[url] = nil
        }
        var r = ranking
        r.queriesToSelected = r.queriesToSelected.filter { $0.value != url }
        return (h, r)
    }

    /// The row selected once row `deleted` went and `count` rows are left: the same line, or the last one.
    public static func selection(afterDeleting deleted: Int, count: Int) -> Int {
        max(0, min(deleted, count - 1))
    }
}
