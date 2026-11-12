import Foundation

/// What Arc 1.172 puts on an Easel besides pictures, text and plain shapes (its EaselObject.Content:
/// image, text, richText, shape, webCard, browser, link; read from Arc's Swift metadata and its
/// ARC_EaselUI.bundle export viewer, 11 Nov 2026), and the colours it draws them in.
extension Easel {
    /// Arc's EaselColor: eleven colours, each drawn from the easel's palette.
    public enum Shade: String, Codable, CaseIterable, Sendable {
        case black, gray, white, pink, red, yellow, lightGreen, darkGreen, lightBlue, darkBlue, purple
    }

    /// Arc's EaselPalette, picked on the canvas's menu (Color Palette ▸ Vibrant, Chill; Arc 1.172.2
    /// starts on Vibrant). Arc's enum also has `theme`, which its menu doesn't offer; Cra reads it
    /// as Vibrant.
    public enum Palette: String, Codable, CaseIterable, Sendable {
        case vibrant, chill, theme
        public var title: String {
            switch self {
            case .chill: "Chill"
            case .vibrant: "Vibrant"
            case .theme: "Theme"
            }
        }
        /// The rows of Arc's Color Palette menu, in its order.
        public static let menu: [Palette] = [.vibrant, .chill]
    }

    /// A shade as #RRGGBB in `palette` (Arc's ARCClients_BaseAssets colour sets Chill.Easel* and
    /// Vibrant.Easel*; nil is Vibrant). Black and white swap in the dark, as Arc's assets do.
    public static func hex(_ shade: Shade, palette: Palette?, dark: Bool) -> String {
        let vibrant = palette != .chill
        switch shade {
        case .black: return dark ? "#FFFFFF" : "#000000"
        case .white: return dark ? "#000000" : "#FFFFFF"
        case .gray: return "#BBBBBB"
        case .pink: return vibrant ? "#FF994E" : "#F2C2AC"
        case .red: return vibrant ? "#F53714" : "#D74807"
        case .yellow: return vibrant ? "#FFD335" : "#C2A12A"
        case .lightGreen: return vibrant ? "#34E895" : "#D0D87F"
        case .darkGreen: return vibrant ? "#107A00" : "#1D5914"
        case .lightBlue: return vibrant ? "#00C7F3" : "#55A2BD"
        case .darkBlue: return "#3139FB"
        case .purple: return vibrant ? "#C0009F" : "#A6729D"
        }
    }

    /// Arc keeps light green and light blue in Display P3 (its colour assets); the others are sRGB.
    public static func isDisplayP3(_ shade: Shade) -> Bool { shade == .lightGreen || shade == .lightBlue }

    /// The shade a new shape takes before one is picked (Arc's DEFAULT_SHAPE_COLORS).
    public static func defaultShade(_ kind: Item.Kind) -> Shade? {
        switch kind {
        case .rectangle: .lightGreen
        case .ellipse: .red
        case .arrow: .lightBlue
        case .freehand: .black
        default: nil
        }
    }

    /// Arc's colour picker over a picked shape (ColorPickerGrid, 11 Nov 2026): two rows, the second
    /// half a step in.
    public static let pickerRows: [[Shade]] = [[.black, .yellow, .pink, .red, .lightGreen, .darkGreen],
                                               [.white, .gray, .purple, .lightBlue, .darkBlue]]

    /// Whether the colour picker applies: shapes, arrows and strokes.
    public static func takesShade(_ kind: Item.Kind) -> Bool { defaultShade(kind) != nil }

    /// How a shape is painted: Arc fills rectangles and ellipses at 75 % and strokes everything
    /// 2.5 pt in the same colour.
    public static let shapeFillOpacity = 0.75
    public static let shapeStroke = 2.5

    /// A link on the canvas (Arc's LinkData, made from a pasted or dropped address): the page's
    /// og:title, og:description and og:image, read once when it lands.
    public struct Link: Codable, Equatable, Sendable {
        public var url: String
        public var title: String?
        public var summary: String?
        /// The og:image, kept next to the easel's file, by name.
        public var image: String?
        /// The site's icon, kept the same way.
        public var icon: String?
        public init(url: String, title: String? = nil, summary: String? = nil, image: String? = nil, icon: String? = nil) {
            (self.url, self.title, self.summary, self.image, self.icon) = (url, title, summary, image, icon)
        }
        /// The host the card shows under its text, without www.
        public var host: String {
            let h = URL(string: url)?.host ?? url
            return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
        }
    }

    /// A capture of part of a page (Arc's WebCard): its picture, the page it came from, and where on
    /// the page it was, so it can show that part of the live page instead of the picture.
    public struct Capture: Codable, Equatable, Sendable {
        public var url: String
        public var title: String?
        /// The picture, kept next to the easel's file, by name.
        public var image: String
        public var captured: Date?
        /// Arc's CaptureLayoutInfo: the page's viewport, how far it was scrolled, and the captured
        /// rectangle in the viewport (points).
        public var viewport: Size?
        public var scroll: Point?
        public var area: Rect?
        /// Arc's WebCardState: the live page instead of the picture.
        public var live: Bool?
        public init(url: String, title: String? = nil, image: String, captured: Date? = nil,
                    viewport: Size? = nil, scroll: Point? = nil, area: Rect? = nil, live: Bool? = nil) {
            (self.url, self.title, self.image, self.captured) = (url, title, image, captured)
            (self.viewport, self.scroll, self.area, self.live) = (viewport, scroll, area, live)
        }
        /// Whether it can go live: it knows which part of the page it shows.
        public var canGoLive: Bool { viewport != nil && area != nil }
    }

    public struct Size: Codable, Equatable, Sendable {
        public var width, height: Double
        public init(_ width: Double, _ height: Double) { (self.width, self.height) = (width, height) }
    }

    /// A link card as it lands (Arc 1.172.2's EaselLinkView, measured 11 Nov 2026 in a 1688 pt wide
    /// canvas): the page's picture across the top, then a bar with the site's icon, the title and ↗.
    public static let linkCardSize = Size(459, 324)
    public static let linkBarHeight: Double = 59

    /// A click (no drag) with the rectangle or ellipse tool places one this size, centred on it.
    public static let placedShapeSide: Double = 200

    /// What a shape tool makes from a press at `a` and a release at `b`: a drag draws the box it
    /// spans, a click places Arc's 200 pt shape there; arrows need a drag.
    public static func shape(_ tool: Tool, from a: Point, to b: Point) -> Item? {
        if abs(a.x - b.x) + abs(a.y - b.y) > 6 { return Item.drawn(tool, from: a, to: b) }
        guard tool == .rectangle || tool == .ellipse else { return nil }
        let h = placedShapeSide / 2
        return Item.drawn(tool, from: Point(a.x - h, a.y - h), to: Point(a.x + h, a.y + h))
    }

    /// The video a link plays, for its card's ▶ (Arc's EaselVideo, the hosts its viewer embeds).
    public static func isVideo(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return ["youtube.com", "youtu.be", "m.youtube.com", "vimeo.com", "player.vimeo.com", "twitch.tv", "dailymotion.com"].contains(h)
    }

    /// Where the live page goes so that `capture.area` fills `frame`: the page's view at the
    /// capture's viewport size, scaled by the card's zoom, offset so the area sits on the card.
    /// The page is scrolled to `capture.scroll` first.
    public static func liveLayout(_ capture: Capture, in frame: Rect) -> (page: Rect, zoom: Double)? {
        guard let vp = capture.viewport, let area = capture.area, area.width > 0, area.height > 0 else { return nil }
        let zoom = frame.width / area.width
        return (Rect(x: -area.x * zoom, y: -area.y * zoom, width: vp.width * zoom, height: vp.height * zoom), zoom)
    }

    /// An address someone pasted or dropped, as a web address, or nil when it isn't one.
    public static func webAddress(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isWhitespace), let u = URL(string: t),
              let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host?.isEmpty == false else { return nil }
        return t
    }

    /// The pictures an item names next to the easel's file.
    public static func files(of item: Item) -> [String] {
        switch item.kind {
        case .image(let f): [f]
        case .capture(let c): [c.image]
        case .link(let l): [l.image, l.icon].compactMap { $0 }
        default: []
        }
    }

    /// A picture's name as Cra writes them (a UUID and an extension): no folders, no "..", nothing
    /// hidden. Items pasted from another app's pasteboard must name only such files.
    public static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 128 && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\") && !name.contains(":")
            && !name.contains("\0")
    }

    /// Whether an item can stand for the easel on the Easels page: a picture or a capture.
    public static func canBeThumbnail(_ kind: Item.Kind) -> Bool {
        switch kind {
        case .image, .capture: true
        default: false
        }
    }

    /// The item the Easels page shows, if one was set and is still there.
    public var thumbnailItem: Item? {
        thumbnail.flatMap { id in items.first { $0.id == id && Self.canBeThumbnail($0.kind) } }
    }

    // MARK: Layering (Arc's object menu: Bring to Front, Send to Back)

    /// The item drawn above all the others.
    public mutating func bringToFront(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.append(items.remove(at: i))
    }

    /// The item drawn below all the others.
    public mutating func sendToBack(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.insert(items.remove(at: i), at: 0)
    }

    public func isFront(_ id: UUID) -> Bool { items.last?.id == id }
    public func isBack(_ id: UUID) -> Bool { items.first?.id == id }

    /// A copy of `item` to paste or duplicate: a new id, `offset` down and right.
    public static func copy(of item: Item, offset: Double = 20) -> Item {
        var c = item.moved(by: Point(offset, offset))
        c.id = UUID()
        return c
    }
}
