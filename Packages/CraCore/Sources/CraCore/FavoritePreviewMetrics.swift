import Foundation

/// Arc's Previews card beside a favorite (Gmail, Calendar), measured at 2x and 60 fps on Victor's
/// signed-in Arc 1.172.1, 8 Nov 2026.
public enum FavoritePreviewMetrics {
    /// The card: 238 pt wide, at most 270 pt tall; longer content scrolls under it.
    public static let width: CGFloat = 238
    public static let maxHeight: CGFloat = 270
    /// A mail row: 84 pt with a 1 pt line under it, its text 11 pt in from the card's edges.
    public static let mailRowHeight: CGFloat = 84
    public static let inset: CGFloat = 11
    /// The pointer's row: a lighter rounded card, 3 pt in from the row.
    public static let hoverInset: CGFloat = 3
    /// The round buttons at the bottom right (Gmail's ＋; Calendar's gear and ＋).
    public static let buttonSize: CGFloat = 32
    public static let buttonInset: CGFloat = 9.5
    public static let buttonGap: CGFloat = 8
    /// The Calendar card: 255 pt tall, an hour 42 pt with its label at the top left, events from
    /// 42 pt in (where the now line starts) to 5 pt from the right edge.
    public static let calendarHeight: CGFloat = 255
    public static let hourHeight: CGFloat = 42
    public static let eventsLeft: CGFloat = 42
    public static let eventsRight: CGFloat = 5
}

/// How Arc's Previews card comes and goes (60 fps capture, 8 Nov 2026): it shows about 0.25 s after
/// the pointer lands on the tile (once the content is in hand), grows from about 80 % while it
/// fades in over some 4 frames, and when the pointer leaves both the tile and the card, it waits
/// about 0.15 s, then fades out, shrinking a little, over about 4 frames.
public enum FavoritePreviewMotion {
    public static let showDelay: TimeInterval = 0.25
    public static let openScale: CGFloat = 0.8
    public static let openDuration: TimeInterval = 0.075
    public static let closeDelay: TimeInterval = 0.15
    public static let closeScale: CGFloat = 0.95
    public static let closeDuration: TimeInterval = 0.07
}
