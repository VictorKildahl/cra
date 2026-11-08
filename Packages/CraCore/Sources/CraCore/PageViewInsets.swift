import CoreGraphics

/// How far Chromium keeps a page's input view (WebContentsViewCocoa) inside its Chrome window
/// from each edge. Usually zero: the page fills the window. A bar that Chromium's views draw above
/// the page, like the "<extension> started debugging this browser" infobar that `chrome.debugger`
/// shows, pushes it down. EmbeddedPages moves the view into a pane card, and the card laid it over
/// the whole web area while the compositor still drew the page below the bar, so every click
/// landed one bar-height low (GitHub #241).
public struct PageViewInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public static let zero = PageViewInsets(top: 0, left: 0, bottom: 0, right: 0)

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// Read back from the frame Chromium gave the view. `NativeViewHostMac::ShowWidget` passes the
    /// contents' rect from the Chrome window's top left with the window's client height, and
    /// `WebContentsNSViewBridge::SetBounds` sets it in whatever superview the view has, flipped
    /// against that height unless the superview is flipped. Nil when the frame doesn't fit the
    /// client area, so it can't be Chromium's layout. Chromium's rects are whole points: it cuts
    /// the window's size down to whole points (`gfx::Rect` from an `NSRect`), and so does this.
    public init?(chromiumFrame frame: CGRect, superviewFlipped: Bool, clientSize: CGSize) {
        let clientSize = CGSize(width: clientSize.width.rounded(.down), height: clientSize.height.rounded(.down))
        guard frame.width > 0, frame.height > 0, clientSize.width > 0, clientSize.height > 0 else { return nil }
        let top = superviewFlipped ? frame.minY : clientSize.height - frame.maxY
        let edges = [top, frame.minX, clientSize.height - top - frame.height, clientSize.width - frame.maxX]
        guard edges.allSatisfy({ $0 > -1 }) else { return nil }
        let whole = edges.map { max(0, $0.rounded()) }
        self.init(top: whole[0], left: whole[1], bottom: whole[2], right: whole[3])
    }

    /// The view's frame in `bounds`, the rect the page's compositor fills, with these insets.
    public func frame(in bounds: CGRect, flipped: Bool) -> CGRect {
        let width = max(0, bounds.width - left - right)
        let height = max(0, bounds.height - top - bottom)
        return CGRect(x: bounds.minX + left, y: bounds.minY + (flipped ? top : bottom), width: width, height: height)
    }
}
