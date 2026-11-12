import Foundation

/// Arc's Easel (File ▸ New Easel ⌃⇧E, Arc 1.172.1, docs/arc-parity.md "Easels, measured"): a tall
/// canvas the page area shows instead of a page, with a title box and things drawn with the toolbar's
/// tools. Saved on its own, one JSON file per easel; the sidebar row only points at it.
public struct Easel: Codable, Equatable, Sendable {
    /// Arc's canvas: the page's width, 2436 pt tall, scrolling.
    public static let canvasHeight: Double = 2436
    /// Arc's title box: 894 pt wide, centred, 52 pt below the top.
    public static let titleWidth: Double = 894, titleTop: Double = 52

    public var id: UUID
    public var title: String
    public var items: [Item]
    /// The title box's Aa style and size (nil: Arc's default bold, 34 pt).
    public var titleStyle: FontStyle?
    public var titleSize: Double?
    /// Arc's palette for the shapes' colours (nil: chill).
    public var palette: Palette?
    /// The picture or capture the Easels page shows for it (Arc's customOGImageID, "Set as Easel
    /// thumbnail"); nil draws the whole easel small.
    public var thumbnail: UUID?

    /// Arc's Aa on the text pill cycles four looks: its bold sans, EB Garamond, Söhne Breit (wide)
    /// and a bold mono. Cra draws them with macOS's own designs (Söhne is a paid font).
    public enum FontStyle: String, Codable, CaseIterable, Sendable {
        case standard, serif, wide, mono
        public var next: FontStyle {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    public init(id: UUID = UUID(), title: String = "Untitled Easel", items: [Item] = []) {
        (self.id, self.title, self.items) = (id, title, items)
    }

    // The file keeps what Cra 0.1.40 and older can read in `items` (they fail on a kind they don't
    // know, and would then show the easel empty) and the newer kinds in `cards`, which they skip.
    // Each item carries its place in the stack as `z`, so the two lists merge back in order.
    private enum CodingKeys: String, CodingKey { case id, title, items, cards, titleStyle, titleSize, palette, thumbnail }
    private enum StackKey: String, CodingKey { case z }

    private struct Stacked: Codable {
        var item: Item
        var z: Int?
        init(_ item: Item, z: Int) { (self.item, self.z) = (item, z) }
        init(from decoder: Decoder) throws {
            item = try Item(from: decoder)
            z = try decoder.container(keyedBy: StackKey.self).decodeIfPresent(Int.self, forKey: .z)
        }
        func encode(to encoder: Encoder) throws {
            try item.encode(to: encoder)
            var c = encoder.container(keyedBy: StackKey.self)
            try c.encodeIfPresent(z, forKey: .z)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        titleStyle = try c.decodeIfPresent(FontStyle.self, forKey: .titleStyle)
        titleSize = try c.decodeIfPresent(Double.self, forKey: .titleSize)
        palette = try? c.decodeIfPresent(Palette.self, forKey: .palette)
        thumbnail = try? c.decodeIfPresent(UUID.self, forKey: .thumbnail)
        let old = try c.decodeIfPresent([Stacked].self, forKey: .items) ?? []
        // A card this Cra can't read is left out rather than losing the easel.
        let cards = (try? c.decodeIfPresent([Lenient].self, forKey: .cards))?.compactMap(\.value) ?? []
        // Without z (older files), an item keeps its place in `items`.
        let all = old.enumerated().map { (z: $0.element.z ?? $0.offset, n: $0.offset, item: $0.element.item) }
            + cards.enumerated().map { (z: $0.element.z ?? Int.max, n: old.count + $0.offset, item: $0.element.item) }
        items = all.sorted { ($0.z, $0.n) < ($1.z, $1.n) }.map(\.item)
    }

    private struct Lenient: Decodable {
        let value: Stacked?
        init(from decoder: Decoder) throws { value = try? Stacked(from: decoder) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(titleStyle, forKey: .titleStyle)
        try c.encodeIfPresent(titleSize, forKey: .titleSize)
        try c.encodeIfPresent(palette, forKey: .palette)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
        let stacked = items.enumerated().map { Stacked($0.element, z: $0.offset) }
        try c.encode(stacked.filter { $0.item.kind.isLegacy }, forKey: .items)
        let cards = stacked.filter { !$0.item.kind.isLegacy }
        if !cards.isEmpty { try c.encode(cards, forKey: .cards) }
    }

    /// The address an easel's tab holds: `easel://<id>`. The page area shows the easel there.
    public static let scheme = "easel"
    public var url: String { "\(Self.scheme)://\(id.uuidString)" }
    public static func id(fromURL url: String) -> UUID? {
        guard url.hasPrefix("\(scheme)://") else { return nil }
        return UUID(uuidString: String(url.dropFirst(scheme.count + 3)))
    }

    /// The toolbar's tools, in Arc's order (EaselIconPointer … EaselIconFreehand).
    public enum Tool: String, CaseIterable, Sendable {
        case pointer, image, text, ellipse, rectangle, arrow, freehand
    }

    public struct Rect: Codable, Equatable, Sendable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { (self.x, self.y, self.width, self.height) = (x, y, width, height) }
        /// The box two corners span, whichever way the drag went.
        public init(from a: Point, to b: Point) {
            self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        }
        public func contains(_ p: Point) -> Bool { p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height }
        public func offset(by d: Point) -> Rect { Rect(x: x + d.x, y: y + d.y, width: width, height: height) }
    }

    public struct Point: Codable, Equatable, Sendable {
        public var x, y: Double
        public init(_ x: Double, _ y: Double) { (self.x, self.y) = (x, y) }
    }

    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public enum Kind: Codable, Equatable, Sendable {
            case text(String, size: Double)
            case ellipse
            case rectangle
            case arrow(from: Point, to: Point)
            case freehand([Point])
            /// A picture kept next to the easel's file, by name.
            case image(file: String)
            /// A link card (EaselObjects.swift).
            case link(Link)
            /// A part of a page, captured (EaselObjects.swift).
            case capture(Capture)

            /// Kinds Cra 0.1.40 and older can read in `items`; the rest are saved under `cards`.
            var isLegacy: Bool {
                switch self {
                case .link, .capture: false
                default: true
                }
            }
        }
        public var id: UUID
        public var kind: Kind
        public var frame: Rect
        /// A text's Aa style (nil: standard).
        public var style: FontStyle?
        /// #RRGGBB; nil draws in the palette's foreground.
        public var color: String?
        /// Arc's colour for a shape, from the easel's palette (nil: the shape's default).
        public var shade: Shade?
        /// A picture's description for VoiceOver (Arc's Add Alt Text…).
        public var altText: String?

        public init(id: UUID = UUID(), kind: Kind, frame: Rect, color: String? = nil) {
            (self.id, self.kind, self.frame, self.color) = (id, kind, frame, color)
        }

        /// The box a drag with `tool` from `a` to `b` makes; nil for tools that don't draw by dragging.
        public static func drawn(_ tool: Tool, from a: Point, to b: Point) -> Item? {
            let box = Rect(from: a, to: b)
            switch tool {
            case .ellipse: return Item(kind: .ellipse, frame: box)
            case .rectangle: return Item(kind: .rectangle, frame: box)
            case .arrow: return Item(kind: .arrow(from: a, to: b), frame: box)
            case .pointer, .image, .text, .freehand: return nil
            }
        }

        /// The same item moved by `d`.
        public func moved(by d: Point) -> Item {
            var out = self
            out.frame = frame.offset(by: d)
            switch kind {
            case .arrow(let a, let b): out.kind = .arrow(from: Point(a.x + d.x, a.y + d.y), to: Point(b.x + d.x, b.y + d.y))
            case .freehand(let pts): out.kind = .freehand(pts.map { Point($0.x + d.x, $0.y + d.y) })
            default: break
            }
            return out
        }
    }

    /// The topmost item under a point (the last drawn wins), for the pointer tool.
    public func item(at p: Point) -> Item? { items.last { $0.frame.contains(p) } }

    /// A freehand stroke's box, from its points.
    public static func freehand(_ points: [Point]) -> Item? {
        guard let first = points.first else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        return Item(kind: .freehand(points), frame: Rect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                                                         width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0)))
    }
}
