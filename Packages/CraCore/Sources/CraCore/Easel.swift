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
        }
        public var id: UUID
        public var kind: Kind
        public var frame: Rect
        /// A text's Aa style (nil: standard).
        public var style: FontStyle?
        /// #RRGGBB; nil draws in the palette's foreground.
        public var color: String?

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
