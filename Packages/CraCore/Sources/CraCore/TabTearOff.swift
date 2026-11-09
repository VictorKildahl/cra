import CoreGraphics

/// A sidebar tab dragged out of the window and let go where no Cra window is (GitHub #219).
/// Arc 1.172 (6 Nov 2026, offline copy, real drags): the tab leaves its space and opens alone in
/// a new Blank Window ("This Window", BlankWindow) the size of the window it came from; the
/// window it left shows no tab if that one was open. The new window centres on where the pointer
/// let go (two drops in the open: 926 × 500 at (1100, 700) and (500, 820) from the top left opened
/// at (637, 450) and (37, 570)); near the screen's edge it stays 20 pt inside the visible frame.
/// The window keeps the tab's profile, so the page stays signed in (#288).
public enum TabTearOff {
    /// How far inside the screen's visible frame the window stays.
    public static let inset: CGFloat = 20

    /// Whether a drag that ended this way opens the tab in a new window: a tab (not a folder or
    /// a split), let go where nothing took it and over no window of the app. An incognito tab
    /// stays in its window: a Blank Window's pages load in the normal profile.
    public static func tearsOff(isTab: Bool, incognito: Bool, dropAccepted: Bool, overAppWindow: Bool) -> Bool {
        isTab && !incognito && !dropAccepted && !overAppWindow
    }

    /// The new window's frame (AppKit screen coordinates, origin bottom left): `size`, centred on
    /// where the pointer let go, moved inside `visible` (the screen's visible frame) less the inset.
    /// A window larger than that room shrinks to fit it.
    public static func frame(size: CGSize, droppedAt point: CGPoint, visible: CGRect) -> CGRect {
        let room = visible.insetBy(dx: inset, dy: inset)
        guard room.width > 0, room.height > 0 else { return CGRect(origin: point, size: size) }
        let w = min(size.width, room.width), h = min(size.height, room.height)
        let x = min(max(point.x - w / 2, room.minX), room.maxX - w)
        let y = min(max(point.y - h / 2, room.minY), room.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
