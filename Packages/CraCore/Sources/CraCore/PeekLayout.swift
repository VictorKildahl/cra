import CoreGraphics
import Foundation

/// Where Arc's Peek card and its buttons go in a browser window (y up, as in AppKit).
///
/// Arc 1.171 (offline Arc, 1728 × 1084 pt window with a 347 pt sidebar, AX frames, 3 Nov 2026): the
/// card is centred on the area right of the sidebar (sidebar edge to the window's edge, not the page
/// card's), 80 % of its width (1105 of 1381 pt), 12 pt in from the window's top and bottom. Close,
/// Expand and Add To Split are 34 × 33 pt round buttons in a column 13 pt right of the card, the
/// first 7 pt below its top, 43.5 pt apart. The page behind fades to 28 %, the card has 8 pt corners
/// and a 32 pt bar.
///
/// The motion (Arc 1.171, offline Arc, small links in two corners, 60 fps recordings, 6 Nov 2026,
/// GitHub #204): the card grows out of the clicked link and closes back into it. A picture of the
/// link fills the card's frame at first and fades out over it; closing, it fades back in as the card
/// lands on the link. The 3 Nov run that read "from the whole area" used a page that was one big
/// link, so the link was the area. Arc 1.172 only moved Chromium.
public enum PeekLayout {
    public static let widthFraction: CGFloat = 0.8
    public static let verticalInset: CGFloat = 12
    public static let cornerRadius: CGFloat = 8
    public static let barHeight: CGFloat = 32
    public static let buttonSize = CGSize(width: 34, height: 33)
    public static let buttonGap: CGFloat = 13
    public static let buttonTop: CGFloat = 7
    public static let buttonPitch: CGFloat = 43.5
    public static let buttonCount = 3
    /// The page under a Peek (Arc: 233/240/254 → 178/172/151 over the window's background).
    public static let pageAlpha: CGFloat = 0.28
    /// The page under a Peek also draws back a little, its margins widening, unless pages fill the
    /// window edge to edge (no margins to widen) (PR #221).
    public static let pageScale: CGFloat = 0.985

    public struct Backdrop: Sendable, Equatable {
        public let alpha: CGFloat
        public let scale: CGFloat
        public init(alpha: CGFloat, scale: CGFloat) { (self.alpha, self.scale) = (alpha, scale) }
    }

    /// How the page behind looks with a Peek over it (`veiled`) or without.
    public static func backdrop(veiled: Bool, edgeToEdge: Bool) -> Backdrop {
        .init(alpha: veiled ? pageAlpha : 1, scale: veiled && !edgeToEdge ? pageScale : 1)
    }

    /// A sublayer transform (applied about the layer's anchor) that scales by `scale` around
    /// `center`, both in the layer's own coordinates.
    public static func backdropTransform(scale: CGFloat, around center: CGPoint, anchor: CGPoint) -> CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                          tx: (center.x - anchor.x) * (1 - scale), ty: (center.y - anchor.y) * (1 - scale))
    }
    /// Arc's open, frame by frame at 60 fps, from the start of the link picture's fade: the picture
    /// fades out on an ease-out over 0.075 s (0.40, 0.21, 0.065 a frame apart). The frame's centre
    /// and width go from the link's to the card's on an ease-out cubic over 0.205 s from 0.016 s;
    /// its height lags, on an ease-out cubic over 0.21 s from 0.028 s. The page fades to
    /// `pageAlpha` on an ease-out cubic over 0.18 s. The buttons fade in once the picture is gone.
    public static let openFadeDuration: Double = 0.075
    public static let openScaleDelay: Double = 0.016
    public static let openScaleDuration: Double = 0.205
    public static let openHeightDelay: Double = 0.028
    public static let openHeightDuration: Double = 0.21
    public static let openButtonsDelay: Double = 0.075
    public static let openButtonsDuration: Double = 0.06
    public static let openVeilDuration: Double = 0.18
    /// Arc's close: the frame goes back to the link in 0.16 s (near linear, width and height
    /// together; 0.12 s when the link was the whole area, a much shorter way), the link picture
    /// fading back in from 0.07 s for 0.09 s, the buttons gone in 0.05 s, while the page comes
    /// back over 0.2 s.
    public static let closeScaleDuration: Double = 0.16
    public static let closeToAreaDuration: Double = 0.12
    public static let closeFadeDelay: Double = 0.07
    public static let closeFadeDuration: Double = 0.09
    public static let closeButtonsDuration: Double = 0.05
    public static let closeVeilDuration: Double = 0.2
    /// How long the whole open runs.
    public static var openDuration: Double {
        max(openScaleDelay + openScaleDuration, openHeightDelay + openHeightDuration, openButtonsDelay + openButtonsDuration)
    }

    /// A CSS-style cubic Bézier timing curve from (0, 0) to (1, 1).
    public struct Curve: Sendable, Equatable {
        public let x1, y1, x2, y2: Double
        public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2) }

        public static let easeOut = Curve(0, 0, 0.58, 1)
        public static let easeOutCubic = Curve(0.215, 0.61, 0.355, 1)
        /// Arc's near-linear way back.
        public static let close = Curve(0.25, 0.25, 0.5, 1)

        /// Progress at `u` (time, 0…1, clamped).
        public func callAsFunction(_ u: Double) -> Double {
            let u = min(max(u, 0), 1)
            if u == 0 || u == 1 { return u }
            func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
            // Bisection: x(t) rises monotonically for control x's in 0…1.
            var lo = 0.0, hi = 1.0, t = u
            for _ in 0..<40 {
                t = (lo + hi) / 2
                if bez(t, x1, x2) < u { lo = t } else { hi = t }
            }
            return bez(t, y1, y2)
        }
    }

    /// `curve` run over `duration` from `delay`, at time `t`.
    static func progress(_ t: Double, delay: Double, duration: Double, _ curve: Curve) -> Double {
        duration > 0 ? curve((t - delay) / duration) : (t >= delay ? 1 : 0)
    }

    /// Between `source` and `card`: the centre and width `p` of the way, the height `q`.
    public static func frame(from source: CGRect, to card: CGRect, p: Double, q: Double) -> CGRect {
        let p = CGFloat(p), q = CGFloat(q)
        let cx = source.midX + (card.midX - source.midX) * p, cy = source.midY + (card.midY - source.midY) * p
        let w = source.width + (card.width - source.width) * p, h = source.height + (card.height - source.height) * q
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// One moment of a Peek's motion: the card's frame, the link picture's and the buttons' opacity.
    public struct Moment: Equatable, Sendable {
        public var frame: CGRect
        public var sourceOpacity: Double
        public var buttonsOpacity: Double
        public init(frame: CGRect, sourceOpacity: Double, buttonsOpacity: Double) {
            (self.frame, self.sourceOpacity, self.buttonsOpacity) = (frame, sourceOpacity, buttonsOpacity)
        }
    }

    /// The open, `t` seconds in, growing from `source` (the link) to `card`.
    public static func opening(from source: CGRect, to card: CGRect, at t: Double) -> Moment {
        let p = progress(t, delay: openScaleDelay, duration: openScaleDuration, .easeOutCubic)
        let q = progress(t, delay: openHeightDelay, duration: openHeightDuration, .easeOutCubic)
        return Moment(frame: frame(from: source, to: card, p: p, q: q),
                      sourceOpacity: 1 - progress(t, delay: 0, duration: openFadeDuration, .easeOut),
                      buttonsOpacity: progress(t, delay: openButtonsDelay, duration: openButtonsDuration, .easeOut))
    }

    /// The close, `t` seconds in, from `card` back into `source`.
    public static func closing(from card: CGRect, to source: CGRect, at t: Double, duration: Double = closeScaleDuration) -> Moment {
        let p = progress(t, delay: 0, duration: duration, .close)
        return Moment(frame: frame(from: card, to: source, p: p, q: p),
                      sourceOpacity: progress(t, delay: closeFadeDelay, duration: closeFadeDuration, .easeOut),
                      buttonsOpacity: 1 - progress(t, delay: 0, duration: closeButtonsDuration, .easeOut))
    }

    /// How long the whole close runs.
    public static func closeDuration(scale: Double = closeScaleDuration) -> Double { max(scale, closeFadeDelay + closeFadeDuration) }

    /// The page's picture inside `frame` (in the frame's own coordinates, y up): Arc scales it by the
    /// frame's width against the card's and pins it to the frame's top-left; the frame clips the rest.
    public static func content(in frame: CGRect, card: CGRect) -> CGRect {
        let s = card.width > 0 ? frame.width / card.width : 1
        return CGRect(x: 0, y: frame.height - card.height * s, width: card.width * s, height: card.height * s)
    }

    /// The button column beside `frame`: scaled like the page, its top `buttonTop` under the frame's
    /// top and its left edge `buttonGap` (scaled) right of the frame, as in Arc.
    public static func column(_ column: CGRect, card: CGRect, frame: CGRect) -> CGRect {
        let s = card.width > 0 ? frame.width / card.width : 1
        let w = column.width * s, h = column.height * s
        let top = frame.maxY - (card.maxY - column.maxY)
        return CGRect(x: frame.maxX + (column.minX - card.maxX) * s, y: top - h, width: w, height: h)
    }

    /// Where a link is (`fraction` of the page's view, y down, as a page script measures it) in
    /// the view `page` (y up), kept on the page; nil when it isn't there.
    public static func source(fraction: CGRect, in page: CGRect) -> CGRect? {
        guard fraction.width > 0, fraction.height > 0, fraction.minX.isFinite, fraction.minY.isFinite,
              fraction.width.isFinite, fraction.height.isFinite else { return nil }
        let r = CGRect(x: page.minX + fraction.minX * page.width, y: page.maxY - fraction.maxY * page.height,
                       width: fraction.width * page.width, height: fraction.height * page.height).intersection(page)
        return r.isNull || r.width < 1 || r.height < 1 ? nil : r
    }

    /// The page script that finds the link a Peek opens from: the link under `pointer` (fractions
    /// of the view, y down; nil without one), else the focused one (Return on a link). Its answer
    /// is the link's rect in fractions of the visual viewport, or null. It keeps the link for
    /// `sourceAgainScript`. Runs in Cra's isolated world, where the page can't replace the DOM's
    /// functions.
    public static func sourceScript(pointer: CGPoint?) -> String {
        let x = pointer.map { "\(Double($0.x))" } ?? "NaN", y = pointer.map { "\(Double($0.y))" } ?? "NaN"
        return """
        (() => {
          const vv = visualViewport;
          const link = e => e && e.closest && e.closest('a[href], area[href]');
          let a = isFinite(\(x)) ? link(document.elementFromPoint(\(x) * vv.width + vv.offsetLeft, \(y) * vv.height + vv.offsetTop)) : null;
          if (!a) a = link(document.activeElement);
          window.__craPeekSource = a || null;
          return a ? \(sourceRectJS) : null;
        })()
        """
    }

    /// The same link's rect again as the Peek closes (it may have moved), or null when it's gone.
    public static let sourceAgainScript = """
        (() => {
          const a = window.__craPeekSource, vv = visualViewport;
          return a && a.isConnected ? \(sourceRectJS) : null;
        })()
        """

    static let sourceRectJS = """
        (() => { const r = a.getBoundingClientRect(); \
        return {x: (r.left - vv.offsetLeft) / vv.width, y: (r.top - vv.offsetTop) / vv.height, \
        width: r.width / vv.width, height: r.height / vv.height}; })()
        """

    /// The rect a source script answered with (fractions, y down), or nil.
    public static func fraction(fromScript result: [String: Any]) -> CGRect? {
        func number(_ v: Any?) -> CGFloat? { (v as? NSNumber).map { CGFloat($0.doubleValue) } }
        guard let x = number(result["x"]), let y = number(result["y"]),
              let w = number(result["width"]), let h = number(result["height"]) else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The area a Peek covers: right of the sidebar (`contentMinX`, window coordinates) to the
    /// window's right edge, its full height.
    public static func area(window: CGSize, contentMinX: CGFloat) -> CGRect {
        CGRect(x: contentMinX, y: 0, width: max(0, window.width - contentMinX), height: window.height)
    }

    public static func card(in area: CGRect) -> CGRect {
        let w = (area.width * widthFraction).rounded()
        return CGRect(x: (area.midX - w / 2).rounded(), y: area.minY + verticalInset,
                      width: w, height: max(0, area.height - 2 * verticalInset))
    }

    /// The column's buttons, top first, beside `card`.
    public static func buttons(beside card: CGRect) -> [CGRect] {
        (0..<buttonCount).map { i in
            let top = card.maxY - buttonTop - CGFloat(i) * buttonPitch
            return CGRect(x: card.maxX + buttonGap, y: ((top - buttonSize.height) * 2).rounded() / 2,
                          width: buttonSize.width, height: buttonSize.height)
        }
    }

    /// The column itself: all the buttons in one frame.
    public static func column(beside card: CGRect) -> CGRect {
        buttons(beside: card).reduce(CGRect.null) { $0.union($1) }
    }
}
