import CoreGraphics

/// The bar of Space icons along the bottom of the Spaces sheet (#885). Arc Search measures
/// (Victor's screenshots of 1.49): 34 pt icons, 29 pt apart, centred in the bar. When they don't
/// fit the sheet's width, the bar scrolls sideways with a 29 pt margin at each end and keeps the
/// open Space's icon in view.
///
/// The bar was a row that didn't scroll, and a row asks for its full width: on an iPhone 13 mini
/// (375 pt) eight Spaces asked for 475 pt, and the sheet grew past both edges of the screen with
/// it, cutting off the start of every row and the close button.
public enum MobileSpaceBar {
    public static let icon: CGFloat = 34
    public static let spacing: CGFloat = 29
    /// The space before the first icon and after the last while the bar scrolls.
    public static let margin: CGFloat = 29

    /// The icons' width, end to end.
    public static func iconsWidth(count: Int) -> CGFloat {
        count > 0 ? CGFloat(count) * icon + CGFloat(count - 1) * spacing : 0
    }

    /// Whether the icons need to scroll in a bar `width` wide: they are wider than it. Icons that fit
    /// stay centred and still, as they always were.
    public static func scrolls(count: Int, width: CGFloat) -> Bool {
        iconsWidth(count: count) > width
    }
}
