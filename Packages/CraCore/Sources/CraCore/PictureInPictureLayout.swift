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

    /// The limits on the window's size: at least 224 × 126 pt for the video's shape, as in Arc
    /// 1.172 (a 16:9 video can't be made smaller than that), at most the display's visible frame.
    /// Arc stops at 61.7 % of the screen's width and the visible height less 20 pt; Cra goes to
    /// the whole visible frame on purpose (the maintainer's decision, 12 Nov). The window keeps
    /// the video's aspect ratio inside them. `screen` is the display's whole frame.
    public static func sizeLimits(aspect a: CGFloat, screen: CGRect, visible: CGRect) -> (min: CGSize, max: CGSize) {
        let minW = max(224, 126 * a)
        let maxW = max(224, visible.width.rounded(.down)), maxH = max(126, visible.height.rounded(.down))
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
        return rest(afterDropping: frame, from: nil, displays: displays.isEmpty ? [current] : displays)?.frame ?? frame
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
        guard shown < frame.width * frame.height - 0.5, let display = display(holding: frame, in: displays) else { return nil }
        let corner = PictureInPictureThrow.corner(for: frame, velocity: .zero, in: display.visible)
        return Landing(corner: corner, frame: PictureInPictureThrow.frame(in: corner, size: frame.size, visible: display.visible, margin: edgeMargin))
    }

    /// The display most of `frame` is on; of two with as much, the one nearer its centre.
    public static func display(holding frame: CGRect, in displays: [Display]) -> Display? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return displays.max { a, b in
            let oa = overlap(a.frame, frame), ob = overlap(b.frame, frame)
            return oa != ob ? oa < ob : distance(centre, a.frame) > distance(centre, b.frame)
        }
    }

    /// Where a window comes to rest and why it moves: `corner` is set when it was past the
    /// screen's edge and springs into a corner.
    public struct Rest: Equatable, Sendable {
        public var frame: CGRect
        public var corner: PictureInPictureThrow.Corner?

        public init(frame: CGRect, corner: PictureInPictureThrow.Corner?) {
            self.frame = frame
            self.corner = corner
        }
    }

    /// Where a window let go at `frame` comes to rest, or nil when it stays there. It always
    /// rests on one display, the one most of it is on:
    /// - Dragged from another display (`from`), it takes the same share of the new display's
    ///   width as it had of the old one's, inside the size limits.
    /// - Larger than the display allows, it shrinks to fit.
    /// - Partly past the screen's edge (off every display), it springs into the nearest corner,
    ///   10 pt in, as Arc's does (#332).
    /// - Across two displays, it slides the shortest way onto its display's visible frame.
    /// Wholly on one display it stays, under the menu bar or the Dock too.
    public static func rest(afterDropping frame: CGRect, from: Display?, displays: [Display]) -> Rest? {
        guard !frame.isEmpty, let display = display(holding: frame, in: displays) else { return nil }
        let size = size(frame.size, movedFrom: from, onto: display)
        if let corner = landing(afterDropping: frame, displays: displays) {
            return Rest(frame: self.frame(in: corner.corner, size: size, on: display), corner: corner.corner)
        }
        // The new size grows or shrinks around the window's centre.
        let sized = CGRect(x: (frame.midX - size.width / 2).rounded(), y: (frame.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        guard sized.size != frame.size || !display.frame.contains(sized) else { return nil }
        let end = fit(sized, into: display.visible)
        return end == frame ? nil : Rest(frame: end, corner: nil)
    }

    /// The size a window of `size` has once it moved from `from` onto `display`: the same share of
    /// that display's visible width as it had of the old one's (the maintainer's decision, 12 Nov),
    /// inside `display`'s limits. Without `from`, or on the same display, only the limits apply.
    public static func size(_ size: CGSize, movedFrom from: Display?, onto display: Display) -> CGSize {
        let aspect = size.width / max(size.height, 1)
        var width = size.width
        if let from, from.frame != display.frame, from.visible.width > 0 {
            width = (size.width / from.visible.width * display.visible.width).rounded()
        }
        return clamp(width: width, aspect: aspect, limits: sizeLimits(aspect: aspect, screen: display.frame, visible: display.visible))
    }

    /// The window in `corner` of `display`, 10 pt in from its visible frame's edges. A window as
    /// large as the visible frame has no room for the margin and fills it.
    public static func frame(in corner: PictureInPictureThrow.Corner, size: CGSize, on display: Display) -> CGRect {
        fit(PictureInPictureThrow.frame(in: corner, size: size, visible: display.visible, margin: edgeMargin), into: display.visible)
    }

    /// `r` moved the shortest way into `v`; one larger than `v` starts at its bottom left.
    static func fit(_ r: CGRect, into v: CGRect) -> CGRect {
        CGRect(x: min(max(r.minX, v.minX), max(v.maxX - r.width, v.minX)), y: min(max(r.minY, v.minY), max(v.maxY - r.height, v.minY)),
               width: r.width, height: r.height)
    }

    /// Chromium keeps its Picture in Picture window inside 80 % of the work area
    /// (`VideoOverlayWindowViews::UpdateMaxSize`), which Cra's limits go past. It cuts the window
    /// down to that cap when the cap changes (the window reached another display, or the Dock
    /// moved), each side on its own, so the video's shape is lost; and when the video's size
    /// changes (a stream switching quality), keeping the new shape. Given the size Cra last gave
    /// the window (`was`), the one Chromium just gave it (`now`), Chromium's cap and whether the
    /// cap had just changed, this is the size to put back on `display`: `was`'s width in the
    /// video's shape, inside Cra's limits. Nil when Chromium's size stands: it didn't cut the
    /// window down to the cap.
    public static func undoingChromiumCap(was: CGSize, now: CGSize, cap: CGSize, capChanged: Bool, on display: Display) -> CGSize? {
        guard now.width > 0, now.height > 0, was.width > 0, was.height > 0, cap.width > 0, cap.height > 0 else { return nil }
        let atCap = abs(now.width - cap.width) <= 1 || abs(now.height - cap.height) <= 1
        let cut = now.width < was.width - 1 || now.height < was.height - 1
        guard atCap, cut else { return nil }
        // A cut to a changed cap trims each side on its own: the shape is `was`'s. Otherwise
        // Chromium fitted the video's new shape into the cap.
        let shape = capChanged ? was : now
        let aspect = shape.width / max(shape.height, 1)
        let size = clamp(width: was.width, aspect: aspect, limits: sizeLimits(aspect: aspect, screen: display.frame, visible: display.visible))
        return size == now ? nil : size
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
