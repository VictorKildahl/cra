import CoreGraphics
import Foundation

/// The pictures that stand in for tabs: in the tab button, and on a flick's cards.
public enum MobileSnapshot {
    /// Whether a picture whose average colour is this is a capture that failed rather than a page.
    /// A web view caught before it draws, or while it is hidden, comes back all black; a dark page
    /// still has text, images and its own grey, which lift the average well clear of this.
    public static func looksBlank(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        red + green + blue < 0.06
    }
}
