import CoreGraphics

/// Where the pointer keeps the downloads list open. The list stands at the bottom of the tab list
/// and opens from a hover on the Library button in the dock below it, but the now-playing cards and
/// the What's New banner can stand between the two. A pointer crossing them on its way up to a
/// download left the button and hadn't reached the list, so the list closed under it (GitHub #575).
/// While the list is open, the column from its rows down to the Library button counts as the list.
///
/// Points and rects are in the sidebar column's flipped space (y grows downwards).
public enum DownloadsTrayHover {
    /// The list's hover area: its rows, and while it is open the column below them down to the top
    /// of the Library button. A button reaching up into the list adds nothing.
    public static func area(list: CGRect, buttonTop: CGFloat, open: Bool) -> CGRect {
        guard open, buttonTop > list.maxY else { return list }
        return CGRect(x: list.minX, y: list.minY, width: list.width, height: buttonTop - list.minY)
    }

    /// Whether the pointer at `point` keeps the list open (or, closed, is over its rows).
    public static func holds(_ point: CGPoint, list: CGRect, buttonTop: CGFloat, open: Bool) -> Bool {
        let a = area(list: list, buttonTop: buttonTop, open: open)
        return point.x >= a.minX && point.x < a.maxX && point.y >= a.minY && point.y < a.maxY
    }
}

/// Whether hovering the now-playing cards opens them (to the tab's title and the close button). They
/// grow up over the bottom of the tab list, where the downloads list stands: with that list open, the
/// pointer crossing the cards is on its way to a download (#575), and the cards stay as they rest.
public enum NowPlayingHover {
    public static func opens(overCards: Bool, cards: Int, downloadsListOpen: Bool) -> Bool {
        overCards && cards > 0 && !downloadsListOpen
    }
}
