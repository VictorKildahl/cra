/// The order of AppleScript's `tabs of window` (#428). Arc 1.172.2 lists the tabs of every space
/// in the window, each favorite once (measured 13 Nov 2026 with counts: 100 tabs on a window of 5
/// spaces whose own lists summed to 92 without the 8 favorites). Raycast's Arc extension reads
/// `every tab of window 1` for Search Tabs and finds a tab by `first tab whose id is "…"` there,
/// so a tab in another space has to be in the list.
///
/// Cra lists the open space first, in its ⌘1…⌘9 order, so `tab 3 of window 1` is still ⌘3 as it
/// was before; the other spaces follow in the sidebar's space order. A tab two spaces share (a
/// shared favorite, #154) comes once, where it first appears. `tabs of space` stays each space's
/// own list, favorites included: in Cra a space has its own favorites.
public enum AppleScriptTabOrder {
    /// - Parameters:
    ///   - focused: the window's open space.
    ///   - spaces: the window's spaces in sidebar order, `focused` among them.
    ///   - tabs: a space's tabs as `tabs of space` lists them.
    public static func window<ID: Hashable>(focused: ID, spaces: [ID], tabs: (ID) -> [ID]) -> [ID] {
        var seen = Set<ID>()
        var list: [ID] = []
        for space in [focused] + spaces.filter({ $0 != focused }) {
            for tab in tabs(space) where seen.insert(tab).inserted { list.append(tab) }
        }
        return list
    }
}
