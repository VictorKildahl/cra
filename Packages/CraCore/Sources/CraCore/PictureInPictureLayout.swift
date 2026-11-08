import CoreGraphics
import Foundation

/// Where Arc's Picture in Picture window opens, and how its hover controls are laid out.
public enum PictureInPictureLayout {
    /// The even layer over the whole frame while the controls show: Arc's
    /// `Color.black.opacity(0.33)`, in and out with `.easeInOut(duration: 0.2)` (Arc 1.172 binary).
    public static let scrimAlpha: CGFloat = 0.33
    public static let fadeDuration: Double = 0.2
    public static let addressFontSize: CGFloat = 11
    /// The address keeps this far from a button, and isn't shown in less room than this.
    static let addressGap: CGFloat = 8
    static let addressMinWidth: CGFloat = 24

    /// Arc's size classes, by window width: tiny under 280 pt, small under 400, then normal.
    /// Its controls sit 12 pt in when tiny and 16 pt otherwise, inside 8 pt of button padding
    /// (10 from 400 pt) around a 12 pt glyph: a button's centre is 26, 30 or 32 pt from the
    /// edges. The reporter measured 26 on a tiny window (#246).
    public static func buttonCentreInset(width: CGFloat) -> CGFloat {
        width < 280 ? 12 + 8 + 6 : width < 400 ? 16 + 8 + 6 : 16 + 10 + 6
    }

    /// Back to Tab grows its words from 400 pt wide; Minimize and Close stay glyphs.
    public static func labelsBackToTab(width: CGFloat) -> Bool { width >= 400 }

    /// The top bar in a window `width` wide, y going down from the top edge: back to tab on the
    /// left (`backWidth` wide: a glyph, or the glyph and its words), close on the right, the
    /// address centred on the window between them (truncated in the middle when it doesn't fit;
    /// nil when there's no room at all).
    public struct TopBar: Equatable, Sendable {
        public var back: CGRect
        public var close: CGRect
        public var address: CGRect?
    }

    public static func topBar(width: CGFloat, buttonSize b: CGFloat, backWidth: CGFloat? = nil, addressWidth: CGFloat) -> TopBar {
        let c = buttonCentreInset(width: width)
        let y = c - b / 2
        let back = CGRect(x: c - b / 2, y: y, width: backWidth ?? b, height: b)
        let close = CGRect(x: width - c - b / 2, y: y, width: b, height: b)
        let room = 2 * (min(width / 2 - back.maxX, close.minX - width / 2) - addressGap)
        let w = min(addressWidth, room)
        let address = addressWidth > 0 && w >= addressMinWidth
            ? CGRect(x: width / 2 - w / 2, y: c - addressFontSize, width: w, height: 2 * addressFontSize) : nil
        return TopBar(back: back, close: close, address: address)
    }

    /// Arc's limits on the window's size (Arc 1.172 binary): at least 224 × 126 pt for the
    /// video's shape (a 16:9 video can't be made smaller than that), at most 61.7 % of the
    /// screen's width and the visible frame's height less 20 pt. The window keeps the video's
    /// aspect ratio inside them.
    public static func sizeLimits(aspect a: CGFloat, screen: CGRect, visible: CGRect) -> (min: CGSize, max: CGSize) {
        let minW = max(224, 126 * a)
        let maxW = max(224, (0.617 * screen.width).rounded(.down)), maxH = max(126, visible.height - 20)
        return (CGSize(width: minW, height: (minW / a).rounded()), CGSize(width: maxW, height: maxH))
    }

    /// The largest size of the video's shape within the limits, no bigger than `size`'s width.
    static func clamp(width: CGFloat, aspect a: CGFloat, limits: (min: CGSize, max: CGSize)) -> CGSize {
        let w = min(max(width, limits.min.width), limits.max.width, limits.max.height * a).rounded()
        return CGSize(width: w, height: (w / a).rounded())
    }

    /// 10 pt from the top and right edges of the visible frame when it first opens.
    public static let edgeMargin: CGFloat = 10
    /// Arc on a 1728×1117 display (24 Oct): 782×440 for a 16:9 video. Arc's code has no fixed
    /// default (it keeps the size the window starts with, inside its limits), and a 223×125 Arc
    /// window is its minimum, not a fresh one (#246).
    public static let defaultHeightFraction: CGFloat = 440.0 / 1084.0

    /// Where the window opens: the frame the user last left it at (Arc's "absolute" placement),
    /// keeping its width and following this video's aspect ratio, or else Arc's default in the
    /// top-right corner of the visible frame; inside Arc's size limits either way. AppKit screen
    /// coordinates (y up).
    public static func initialFrame(aspect: CGFloat, screen: CGRect, visible: CGRect, remembered: CGRect?) -> CGRect {
        let limits = sizeLimits(aspect: aspect, screen: screen, visible: visible)
        if let r = remembered, !r.isEmpty, visible.intersects(r) {
            let size = clamp(width: r.width, aspect: aspect, limits: limits)
            return CGRect(x: r.minX, y: r.maxY - size.height, width: size.width, height: size.height)
        }
        let size = clamp(width: (visible.height * defaultHeightFraction * aspect).rounded(), aspect: aspect, limits: limits)
        return CGRect(x: visible.maxX - edgeMargin - size.width, y: visible.maxY - edgeMargin - size.height,
                      width: size.width, height: size.height)
    }

    /// The address in the top bar: the page's host as Arc writes it ("www.youtube.com"), and
    /// Chrome's words for a file on this Mac.
    public static func address(of url: String) -> String {
        guard let u = URL(string: url) else { return "" }
        if u.isFileURL { return "File on your device" }
        return u.host ?? ""
    }
}
