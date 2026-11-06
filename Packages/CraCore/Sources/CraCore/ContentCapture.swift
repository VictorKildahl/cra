import CoreGraphics
import Foundation

/// Arc's Capture (⇧⌘2): the page dims and greys, the part about to be captured stays in colour,
/// a click takes the element under the pointer and a drag takes a rectangle. These are the decisions
/// behind it, in the overlay's coordinates: points, y down from the page's top-left corner, the way
/// the page and its screenshot count.
public enum ContentCapture {
    /// A press that moves less than this is a click (Arc's NSPanGestureRecognizer threshold).
    public static let dragThreshold: CGFloat = 4
    /// A drag smaller than this either way captures nothing.
    public static let minimumSize: CGFloat = 8

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= dragThreshold
    }

    /// The rectangle a drag spans, kept inside the page.
    public static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let r = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        return r.intersection(bounds).isNull ? .zero : r.intersection(bounds)
    }

    /// Whether a selection is big enough to capture.
    public static func isCapturable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSize && rect.height >= minimumSize
    }

    /// The pixels of a screenshot of the whole page (`imageSize` pixels for `pageSize` points) that
    /// `rect` covers, on whole pixels and inside the image.
    public static func pixelRect(for rect: CGRect, pageSize: CGSize, imageSize: CGSize) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0 else { return .zero }
        let sx = imageSize.width / pageSize.width, sy = imageSize.height / pageSize.height
        let r = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
        let clipped = r.intersection(CGRect(origin: .zero, size: imageSize))
        return clipped.isNull ? .zero : clipped
    }

    /// The element the picker chose, in points inside the page, or nil when it found none (the page
    /// then only takes drags, and Arc's hint says so). `result` is the picker's JSON: device pixels.
    public static func elementRect(fromPicker result: [String: Any], scale: CGFloat, pageBounds: CGRect) -> CGRect? {
        guard scale > 0, let x = number(result["x"]), let y = number(result["y"]),
              let w = number(result["width"]), let h = number(result["height"]), w > 0, h > 0 else { return nil }
        let r = CGRect(x: x / scale, y: y / scale, width: w / scale, height: h / scale).intersection(pageBounds)
        return r.isNull || r.isEmpty ? nil : r
    }

    // MARK: The lens and the menu (Arc 1.171, offline Arc, 2x window captures, 4 Nov 2026)

    /// An element shows in colour 2 pt beyond its edges (a dragged rectangle exactly)…
    public static let elementClearance: CGFloat = 2
    /// …inside a 4 pt ring (#161C2F), 4.5 pt corners inside and 8.5 pt outside.
    public static let lensRing: CGFloat = 4
    public static let lensInnerRadius: CGFloat = 4.5

    /// What shows in colour for the element under the pointer.
    public static func clearArea(element rect: CGRect) -> CGRect {
        rect.insetBy(dx: -elementClearance, dy: -elementClearance)
    }

    /// The ring's outer edge around the part shown in colour.
    public static func lensFrame(around clear: CGRect) -> CGRect {
        clear.insetBy(dx: -lensRing, dy: -lensRing)
    }

    /// The menu after a capture: 4.5 pt right of the ring, its top level with the ring's. Where the
    /// right has no room it goes left of the ring, and where neither side has, inside the page's
    /// right edge over the capture. Always `margin` inside the page.
    public static let menuGap: CGFloat = 4.5
    public static let menuMargin: CGFloat = 8

    public static func menuFrame(size: CGSize, besideLens lens: CGRect, in bounds: CGRect) -> CGRect {
        var x = lens.maxX + menuGap
        if x + size.width > bounds.maxX - menuMargin {
            let left = lens.minX - menuGap - size.width
            x = left >= bounds.minX + menuMargin ? left : bounds.maxX - menuMargin - size.width
        }
        let y = min(max(lens.minY, bounds.minY + menuMargin), bounds.maxY - menuMargin - size.height)
        return CGRect(x: max(bounds.minX + menuMargin, x), y: max(bounds.minY + menuMargin, y), width: size.width, height: size.height)
    }

    // MARK: Capture Image… (a page's context menu on an image)

    /// Arc 1.172 (Little Arc, 2x window capture, 6 Nov 2026): Capture Image… greys the page and
    /// moves the image, at its size on the page, to the middle of the page in the 4 pt ring with no
    /// clearance; the menu sits 10 pt right of the ring, top level with it, and image, ring and menu
    /// are centred on the page together, the menu counted 10 pt narrower than it draws (on a
    /// 1688 pt page a 160 pt image's ring starts at 623.5). The image's own place stays grey.
    public static let liftedMenuGap: CGFloat = 10
    static let liftedMenuCentringInset: CGFloat = 10

    /// The image (inside the ring) and the menu. An image too big for the page shrinks to fit;
    /// where the menu has no room beside it, it goes where `menuFrame` puts it.
    public static func liftedLayout(image: CGSize, menu: CGSize, in bounds: CGRect) -> (image: CGRect, menu: CGRect) {
        let room = bounds.insetBy(dx: menuMargin + lensRing, dy: menuMargin + lensRing)
        var size = image
        if size.width > room.width || size.height > room.height, size.width > 0, size.height > 0 {
            let k = min(room.width / size.width, room.height / size.height)
            size = CGSize(width: (size.width * k).rounded(.down), height: (size.height * k).rounded(.down))
        }
        let fits = size.width + 2 * lensRing + liftedMenuGap + menu.width <= bounds.width - 2 * menuMargin
        let centred = size.width + 2 * lensRing + liftedMenuGap + menu.width - liftedMenuCentringInset
        let x = fits ? bounds.midX - centred / 2 + lensRing : bounds.midX - size.width / 2
        // To the half point, as Arc's 2x captures land.
        let half = { (v: CGFloat) in (v * 2).rounded() / 2 }
        let rect = CGRect(x: half(x), y: half(bounds.midY - size.height / 2), width: size.width, height: size.height)
        let ring = lensFrame(around: rect)
        let beside = CGRect(x: ring.maxX + liftedMenuGap, y: ring.minY, width: menu.width, height: menu.height)
        let menuRect = fits && beside.maxY <= bounds.maxY - menuMargin ? beside : menuFrame(size: menu, besideLens: ring, in: bounds)
        return (rect, menuRect)
    }

    /// The image the context menu was opened on: the topmost image, picture, canvas or SVG image
    /// under the point, else the topmost element. Takes and returns device pixels, as the picker does.
    public static func imageRectScript(x: CGFloat, y: CGFloat) -> String {
        """
        (() => {
          const vv = visualViewport, dpr = devicePixelRatio, k = vv.scale;
          const px = \(Double(x)) / dpr / k + vv.offsetLeft, py = \(Double(y)) / dpr / k + vv.offsetTop;
          const all = document.elementsFromPoint(px, py);
          const el = all.find(e => ['IMG', 'PICTURE', 'CANVAS', 'image'].includes(e.tagName)) || all[0];
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return {x: (r.left - vv.offsetLeft) * k * dpr, y: (r.top - vv.offsetTop) * k * dpr, width: r.width * k * dpr, height: r.height * k * dpr};
        })()
        """
    }

    private static func number(_ v: Any?) -> CGFloat? {
        if let d = v as? Double { return CGFloat(d) }
        if let n = v as? NSNumber { return CGFloat(truncating: n) }
        return nil
    }

    /// Arc's click-to-capture picker (Arc 1.171, from the binary): of the elements under the
    /// pointer, the best scored one. Images score up; small (under 100 px a side), full-width,
    /// full-height, nearly-full-screen and inline elements score down; bigger ones score a little
    /// higher. Nothing scoring 0 or more means there is nothing to click. Arc measures in the visual
    /// viewport's units; Cra hands it device pixels and gets device pixels back, so page zoom and
    /// pinch zoom both come out right. Runs in an isolated world: the page's own scripts can't see it.
    public static func pickerScript(x: CGFloat, y: CGFloat) -> String {
        """
        (() => {
          const vv = visualViewport, dpr = devicePixelRatio, k = vv.scale;
          const px = \(Double(x)) / dpr / k + vv.offsetLeft, py = \(Double(y)) / dpr / k + vv.offsetTop;
          const screenArea = innerWidth * innerHeight;
          const score = el => {
            const size = el.getBoundingClientRect();
            const avgDim = (size.width + size.height) / 2, minDim = Math.min(size.width, size.height);
            let s = 0;
            if (minDim < 100) s -= 5;
            if (size.width >= innerWidth) s -= 5;
            if (size.height >= innerHeight) s -= 5;
            if (size.width * size.height > screenArea * 0.7) s -= 5;
            if (el.tagName === 'IMG' || el.tagName === 'PICTURE' || el.tagName === 'OBJECT') s += 5;
            s += avgDim / 500;
            if (getComputedStyle(el).display === 'inline') s -= 10;
            return s;
          };
          const scored = document.elementsFromPoint(px, py).map(el => ({el, s: score(el)})).filter(p => p.s >= 0);
          scored.sort((a, b) => b.s - a.s);
          if (!scored.length) return null;
          const r = scored[0].el.getBoundingClientRect();
          return {x: (r.left - vv.offsetLeft) * k * dpr, y: (r.top - vv.offsetTop) * k * dpr, width: r.width * k * dpr, height: r.height * k * dpr};
        })()
        """
    }
}
