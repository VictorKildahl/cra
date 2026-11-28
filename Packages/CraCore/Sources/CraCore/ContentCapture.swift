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
    /// How long a capture sent to an easel waits for the page to say where it is scrolled. A page
    /// whose next address hasn't responded holds that answer back, so past this the capture goes
    /// to the easel with its address and title only.
    public static let sourceAnswerWait: TimeInterval = 0.5

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

    // MARK: The element under the pointer

    /// One element under the pointer, as the picker script lists them.
    public struct PickerElement: Equatable, Sendable {
        public var tag: String
        public var isInline: Bool
        /// Inside an open shadow root. Arc's score never looks there; ⌥ does (Reddit's posts).
        public var inShadowRoot: Bool
        /// In CSS pixels, which Arc's score measures.
        public var size: CGSize
        /// In device pixels, which `elementRect` takes.
        public var rect: CGRect

        public init(tag: String, isInline: Bool, inShadowRoot: Bool, size: CGSize, rect: CGRect) {
            self.tag = tag
            self.isInline = isInline
            self.inShadowRoot = inShadowRoot
            self.size = size
            self.rect = rect
        }
    }

    /// Everything under the pointer, topmost first, and the window's size in CSS pixels.
    public struct PickerStack: Equatable, Sendable {
        public var viewport: CGSize
        public var elements: [PickerElement]

        public init(viewport: CGSize, elements: [PickerElement]) {
            self.viewport = viewport
            self.elements = elements
        }
    }

    /// The picker script's answer, or nil when it isn't one.
    public static func pickerStack(from result: [String: Any]) -> PickerStack? {
        guard let view = result["view"] as? [String: Any], let vw = number(view["w"]), let vh = number(view["h"]),
              vw > 0, vh > 0, let rows = result["stack"] as? [[String: Any]] else { return nil }
        let elements = rows.compactMap { row -> PickerElement? in
            guard let w = number(row["w"]), let h = number(row["h"]), let x = number(row["x"]), let y = number(row["y"]),
                  let width = number(row["width"]), let height = number(row["height"]) else { return nil }
            return PickerElement(tag: row["tag"] as? String ?? "", isInline: row["inline"] as? Bool ?? false,
                                 inShadowRoot: row["shadow"] as? Bool ?? false, size: CGSize(width: w, height: h),
                                 rect: CGRect(x: x, y: y, width: width, height: height))
        }
        return PickerStack(viewport: CGSize(width: vw, height: vh), elements: elements)
    }

    /// Arc's score for an element (Arc 1.171, from the binary). Images score up; small (under 100 px
    /// a side), full-width, full-height, nearly-full-screen and inline elements score down; bigger
    /// ones score a little higher.
    public static func arcScore(_ e: PickerElement, viewport: CGSize) -> Double {
        let w = Double(e.size.width), h = Double(e.size.height)
        var s = 0.0
        if min(w, h) < 100 { s -= 5 }
        if w >= Double(viewport.width) { s -= 5 }
        if h >= Double(viewport.height) { s -= 5 }
        if w * h > Double(viewport.width * viewport.height) * 0.7 { s -= 5 }
        if ["IMG", "PICTURE", "OBJECT"].contains(e.tag) { s += 5 }
        s += (w + h) / 2 / 500
        if e.isInline { s -= 10 }
        return s
    }

    /// With ⌥, the smallest element worth a click, in CSS pixels each way (a capture's own minimum).
    public static let deeperMinimum: CGFloat = minimumSize

    /// What a click captures. Arc's choice: the best scored element, the topmost of equals (its sort
    /// is stable), none when nothing scores 0 or more; the page then only takes drags.
    /// `deeper` (⌥ held, #451) is Cra's: the element right under the pointer, a title line or a
    /// button, the way a page inspector picks.
    public static func choose(in stack: PickerStack, deeper: Bool) -> PickerElement? {
        if deeper {
            // The topmost one big enough to capture that isn't the whole page.
            return stack.elements.first { e in
                e.size.width >= deeperMinimum && e.size.height >= deeperMinimum
                    && !(e.size.width >= stack.viewport.width && e.size.height >= stack.viewport.height)
            }
        }
        var best: (element: PickerElement, score: Double)?
        for e in stack.elements where !e.inShadowRoot {
            let s = arcScore(e, viewport: stack.viewport)
            if s >= 0, s > best?.score ?? -.infinity { best = (e, s) }
        }
        return best?.element
    }

    /// The chosen element in points inside the page, or nil when it is off the page.
    public static func elementRect(_ element: PickerElement?, scale: CGFloat, pageBounds: CGRect) -> CGRect? {
        guard let r = element?.rect else { return nil }
        return elementRect(fromPicker: ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height], scale: scale, pageBounds: pageBounds)
    }

    /// The picker: every element under the point, topmost first, with what `choose` weighs. Arc's
    /// script listed `document.elementsFromPoint` and scored it in the page; Cra lists the same and
    /// scores in `choose`, so ⌥ can choose again without asking the page. Inside open shadow roots
    /// the deepest come first, marked. Takes and returns device pixels, so page zoom and pinch zoom
    /// both come out right. Runs in an isolated world: the page's own scripts can't see it.
    public static func pickerScript(x: CGFloat, y: CGFloat) -> String {
        """
        (() => {
          const vv = visualViewport, dpr = devicePixelRatio, k = vv.scale;
          const px = \(Double(x)) / dpr / k + vv.offsetLeft, py = \(Double(y)) / dpr / k + vv.offsetTop;
          const levels = [];
          let root = document;
          for (let i = 0; root && i < 16; i++) {
            const shadow = root !== document, here = root;
            const els = root.elementsFromPoint(px, py).filter(e => !shadow || e.getRootNode() === here);
            levels.unshift(els.map(el => [el, shadow]));
            root = els[0] && els[0].shadowRoot;
          }
          const stack = levels.flat().slice(0, 96).map(([el, shadow]) => {
            const r = el.getBoundingClientRect();
            return {tag: el.tagName, inline: getComputedStyle(el).display === 'inline', shadow, w: r.width, h: r.height,
                    x: (r.left - vv.offsetLeft) * k * dpr, y: (r.top - vv.offsetTop) * k * dpr, width: r.width * k * dpr, height: r.height * k * dpr};
          });
          return {view: {w: innerWidth, h: innerHeight}, stack};
        })()
        """
    }

    // MARK: Little Window host selection (#835)

    /// A candidate browser window that can host Capture for a standalone Little Window.
    public struct HostWindow: Equatable, Sendable {
        public let id: UUID
        public let isStandalone: Bool

        public init(id: UUID, isStandalone: Bool) {
            self.id = id
            self.isStandalone = isStandalone
        }
    }

    /// Picks the normal browser window that hosts Capture for an ordinary Little Window:
    /// prefers `lastNormalWindowID` (when non-standalone), else the first non-standalone window,
    /// else `fallbackID` (#835).
    public static func hostWindowID(
        from windows: [HostWindow],
        lastNormalWindowID: UUID?,
        fallbackID: UUID? = nil
    ) -> UUID? {
        windows.first { $0.id == lastNormalWindowID && !$0.isStandalone }?.id
            ?? windows.first { !$0.isStandalone }?.id
            ?? fallbackID
    }
}
