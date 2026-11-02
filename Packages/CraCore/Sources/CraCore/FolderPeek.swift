/// Arc keeps the open tab in sight when it sits in a closed folder (GitHub #85). Arc 1.171, 2 Nov
/// 2026: picking such a tab (from the command bar, say) leaves the folders closed and lists the
/// tab one level under the outermost closed one, whose glyph gets three dots; Arc's window state
/// keeps it as `expandedItems: [folder: .peeked([tab ids])]`. Opening that folder shows all of it
/// again; closing it keeps only the open tab in sight, as a closed folder always does.
public enum FolderPeek {
    /// The folder a tab is listed under while it is open: the outermost closed one among its
    /// folders, which run from the outermost in. Nil when they are all open.
    public static func host<ID: Hashable>(folders: [ID], isExpanded: (ID) -> Bool) -> ID? {
        folders.first { !isExpanded($0) }
    }

    /// The peeks once `tab` is open; tabs already peeked stay, as in Arc.
    public static func opening<ID: Hashable>(_ tab: ID, folders: [ID], isExpanded: (ID) -> Bool,
                                             peeks: [ID: [ID]]) -> [ID: [ID]] {
        guard let host = host(folders: folders, isExpanded: isExpanded), peeks[host]?.contains(tab) != true else { return peeks }
        var out = peeks
        out[host, default: []].append(tab)
        return out
    }

    /// The peeks once `folder` opens (nothing to keep in sight) or closes (only the open tab,
    /// when it is inside).
    public static func expanding<ID: Hashable>(_ folder: ID, _ expanded: Bool, openTabInside: ID?,
                                               peeks: [ID: [ID]]) -> [ID: [ID]] {
        var out = peeks
        out[folder] = expanded ? nil : openTabInside.map { [$0] }
        return out
    }

    /// The peeks once `tab` closes (⌘W) or leaves the sidebar.
    public static func removing<ID: Hashable>(_ tab: ID, peeks: [ID: [ID]]) -> [ID: [ID]] {
        var out: [ID: [ID]] = [:]
        for (folder, tabs) in peeks {
            let kept = tabs.filter { $0 != tab }
            if !kept.isEmpty { out[folder] = kept }
        }
        return out
    }

    /// The rows a closed folder lists under itself: its peeked tabs that are still inside it,
    /// in sidebar order (`tabsInside`, nested folders included).
    public static func listed<ID: Hashable>(in folder: ID, peeks: [ID: [ID]], tabsInside: [ID]) -> [ID] {
        guard let peeked = peeks[folder], !peeked.isEmpty else { return [] }
        let wanted = Set(peeked)
        return tabsInside.filter(wanted.contains)
    }
}
