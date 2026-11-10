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

    /// Play/pause in the middle with the ±15 s skips on either side, sized by Arc's size classes
    /// (#262). Arc's glyphs on its own windows: play/pause only, about 23.5 pt, at 224 and 277 pt
    /// wide; from 396 pt the skips in ~31 pt circles beside a 37–40 pt play/pause, the same at 801.
    /// SF Symbol point sizes that draw those: play 28 (22 × 26 pt of ink) when tiny, 44 (35 × 39)
    /// from 280 pt, `gobackward.15` 28 (30 × 32.5). The diameters are the hover discs.
    public struct CentreControls: Equatable, Sendable {
        public var playPointSize: CGFloat
        public var playDiameter: CGFloat
        public var showsSkips: Bool
        public var skipPointSize: CGFloat
        public var skipDiameter: CGFloat
        /// Between a skip's disc and play's.
        public var gap: CGFloat
        /// The whole cluster, skips included when they show.
        public var clusterWidth: CGFloat { showsSkips ? playDiameter + 2 * (gap + skipDiameter) : playDiameter }
    }

    /// The centre cluster for a window `width` wide. For a video taller than 16:9 pass the width a
    /// 16:9 window of its height would have, so the cluster stays clear of the top bar.
    public static func centreControls(width: CGFloat) -> CentreControls {
        if width < 280 {
            return CentreControls(playPointSize: 28, playDiameter: 52, showsSkips: false, skipPointSize: 28, skipDiameter: 46, gap: 10)
        }
        return CentreControls(playPointSize: 44, playDiameter: 68, showsSkips: true, skipPointSize: 28, skipDiameter: 46, gap: width < 400 ? 10 : 24)
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

extension PictureInPictureLayout {
    /// A display as AppKit reports it: `id` names it across launches and rearrangements
    /// (CGDisplayCreateUUIDFromDisplayID), the frames are in screen coordinates (y up).
    public struct Display: Equatable, Sendable {
        public var id: String?
        public var frame: CGRect
        public var visible: CGRect

        public init(id: String?, frame: CGRect, visible: CGRect) {
            self.id = id
            self.frame = frame
            self.visible = visible
        }
    }

    /// Where the user last left the window: its frame, the display it was on and that display's
    /// frame then. Frames saved before #316 have no display.
    public struct Placement: Equatable, Sendable {
        public var frame: CGRect
        public var display: String?
        public var displayFrame: CGRect?

        public init(frame: CGRect, display: String?, displayFrame: CGRect?) {
            self.frame = frame
            self.display = display
            self.displayFrame = displayFrame
        }
    }

    /// Where the window opens, among all connected displays (#316), as Arc's "absolute" placement
    /// does: on the display it was left on, at the same place on it, even after the displays were
    /// rearranged; a frame without a display, on the display it lies on. Otherwise (nothing left,
    /// or that display unplugged) Arc's default corner of `current`, the display Chromium opened it on.
    /// A remembered frame partly off the screen (0.1.38 kept wherever a drag let it go, or the
    /// displays changed since) opens in the nearest corner instead, as a drop there lands (#332).
    public static func initialFrame(aspect: CGFloat, displays: [Display], current: Display, remembered: Placement?) -> CGRect {
        let frame = rememberedFrame(aspect: aspect, displays: displays, current: current, remembered: remembered)
        return landing(afterDropping: frame, displays: displays.isEmpty ? [current] : displays)?.frame ?? frame
    }

    static func rememberedFrame(aspect: CGFloat, displays: [Display], current: Display, remembered: Placement?) -> CGRect {
        if let r = remembered, !r.frame.isEmpty {
            if let id = r.display, let d = displays.first(where: { $0.id == id }) {
                let was = r.displayFrame ?? d.frame
                let frame = r.frame.offsetBy(dx: d.frame.minX - was.minX, dy: d.frame.maxY - was.maxY)
                return initialFrame(aspect: aspect, screen: d.frame, visible: d.visible, remembered: frame)
            }
            if r.display == nil, let d = displays.max(by: { overlap($0.visible, r.frame) < overlap($1.visible, r.frame) }),
               overlap(d.visible, r.frame) > 0 {
                return initialFrame(aspect: aspect, screen: d.frame, visible: d.visible, remembered: r.frame)
            }
        }
        return initialFrame(aspect: aspect, screen: current.frame, visible: current.visible, remembered: nil)
    }

    static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}

extension PictureInPictureLayout {
    /// Where a window let go partly off the screen comes to rest: a corner of a display and the
    /// frame there.
    public struct Landing: Equatable, Sendable {
        public var corner: PictureInPictureThrow.Corner
        public var frame: CGRect

        public init(corner: PictureInPictureThrow.Corner, frame: CGRect) {
            self.corner = corner
            self.frame = frame
        }
    }

    /// A window dropped by a mouse drag with part of it past the screen's edge (off every
    /// display) springs back into the nearest corner of the display most of it is on, 10 pt in,
    /// as Arc's does (#332). Wholly on screen, under the menu bar or the Dock or across two
    /// displays, it stays where it was let go: nil.
    public static func landing(afterDropping frame: CGRect, displays: [Display]) -> Landing? {
        guard !frame.isEmpty, !displays.isEmpty else { return nil }
        // Mirrored displays share a frame; count the screen once.
        var screens: [CGRect] = []
        for d in displays where !screens.contains(d.frame) { screens.append(d.frame) }
        let shown = screens.reduce(0) { $0 + overlap($1, frame) }
        guard shown < frame.width * frame.height - 0.5 else { return nil }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let display = displays.max { a, b in
            let oa = overlap(a.frame, frame), ob = overlap(b.frame, frame)
            return oa != ob ? oa < ob : distance(centre, a.frame) > distance(centre, b.frame)
        }!
        let corner = PictureInPictureThrow.corner(for: frame, velocity: .zero, in: display.visible)
        return Landing(corner: corner, frame: PictureInPictureThrow.frame(in: corner, size: frame.size, visible: display.visible, margin: edgeMargin))
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
