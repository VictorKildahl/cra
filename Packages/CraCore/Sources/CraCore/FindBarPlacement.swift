import CoreGraphics

/// Where the find bar sits over the focused page, and Ask on Page's card, which takes its place.
///
/// Rects are in AppKit's coordinates (y grows upward), so the page's top edge is its `maxY`.
public enum FindBarPlacement {
    /// The bar's frame, in the coordinates `page` is in: the page's top trailing corner, `inset`
    /// from both edges.
    ///
    /// - `visibleMaxX`: the window's trailing edge. Beside the Library a page keeps its width and
    ///   goes past it, and the corner is that of the part the window shows (#340).
    /// - `toolbarOverPage`: how much of the page's top the floating toolbar covers while it is out
    ///   (`ToolbarAutoHide`). The bar's window is above everything in Cra's own, the toolbar
    ///   included, so there it would cover the toolbar's right end (#405): it hangs under the
    ///   toolbar until that has gone.
    public static func frame(page: CGRect, visibleMaxX: CGFloat? = nil, size: CGSize, inset: CGFloat,
                             toolbarOverPage: CGFloat = 0) -> CGRect {
        var maxX = page.maxX
        if let visibleMaxX, maxX > visibleMaxX { maxX = max(page.minX, visibleMaxX) }
        return CGRect(x: maxX - size.width - inset, y: page.maxY - max(0, toolbarOverPage) - size.height - inset,
                      width: size.width, height: size.height)
    }
}
