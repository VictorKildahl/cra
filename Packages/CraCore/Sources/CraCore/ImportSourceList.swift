import Foundation

/// What the import window's browser step lists, and which apps its Dock art shows.
public enum ImportSourceList {
    /// Every browser Cra can import from, in its own order, with the ones that have something
    /// to bring over first. The rest stay listed, dimmed, so people see what Cra reads.
    public static func ordered(_ ids: [String], available: Set<String>) -> [String] {
        ids.filter(available.contains) + ids.filter { !available.contains($0) }
    }

    /// The two apps beside Cra's tile in the default browser step's Dock art. The left one is
    /// the current default browser, where Cra's tile lands; the right one is Arc, or Dia when Arc
    /// is on the left. Cra itself never stands in for either (it is the default on a Mac that has
    /// run Cra before), nor does the same app appear twice: the next installed browser of
    /// `fallbacks` takes the place.
    public static func dockNeighbours(defaultBrowser: String?, installed: Set<String>, isCra: (String) -> Bool,
                                      fallbacks: [String]) -> (left: String?, right: String?) {
        func usable(_ id: String) -> Bool { installed.contains(id) && !isCra(id) }
        var left = defaultBrowser.flatMap { usable($0) ? $0 : nil }
        let right = fallbacks.first { usable($0) && $0 != left }
        if left == nil { left = fallbacks.first { usable($0) && $0 != right } }
        return (left, right)
    }
}
