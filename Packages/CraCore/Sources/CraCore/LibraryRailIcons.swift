import CoreGraphics
import Foundation

/// The six pages of the Library's rail, each with an icon of two colours that plays once when its page
/// is picked.
///
/// Arc's rail (Arc 1.174, `HomeButton/PageSidebarItem.swift`, read from its code) shows one animation
/// per page on a 60-per-second timeline with three marks: `hover-start` (1), `hover-end` (11) and
/// `selection-end` (35; 45 for Boosts). Every shape belongs to one of two colours, `primaryColor` (the
/// lines) and `secondaryColor` (what fills them). When a page becomes the one shown, its icon plays
/// hover-start to selection-end once, at the timeline's own speed, and rests there; nothing plays when
/// it stops being shown, and nothing plays under the pointer (1.174 names hover-end and never stops on
/// it).
///
/// How each part moves is Arc's, key for key: where it goes and turns, when, and on which easing curve
/// (the numbers below are its animations' transform keys, positions in its 128-unit canvas). The
/// drawings are Cra's own: Arc's artwork comes with no licence, so none of its shapes are copied here.
/// Where one of Arc's shapes changes form (the arrow's shaft, the box's slot, the brush's bristles),
/// Cra's shape is moved by the same amount, measured from the bounding boxes of Arc's.
///
/// Points are in a 36 pt box, y down. Angles are degrees clockwise.
public enum LibraryRailIcon: String, CaseIterable, Sendable {
    case media, downloads, easels, spaces, boosts, archive

    /// The last frame of the animation that plays when the page is picked.
    public var selectionEnd: Double { self == .boosts ? 45 : 35 }
}

public enum LibraryRailIcons {
    /// The box an icon is drawn in.
    public static let canvas: CGFloat = 36
    /// Arc's lines are 8 of its units wide: 1.75 pt.
    public static let lineWidth: CGFloat = 1.75
    /// Frames per second of the timeline.
    public static let frameRate = 60.0
    /// Where an icon rests and its selection starts, and the end of the wind-up before it lets go.
    public static let hoverStart = 1.0
    public static let hoverEnd = 11.0
    /// One unit of Arc's 128-unit canvas, shown 28 pt wide.
    public static let unit = 28.0 / 128

    // MARK: Motion

    /// One value over the timeline: it holds its first value before the first key and its last after the
    /// last one. Between two keys it follows the first key's easing curve, a cubic from (0, 0) to (1, 1)
    /// whose two handles may leave 0...1 upward or downward, so a value can overshoot.
    public struct Track: Equatable, Sendable {
        public var keys: [Key]
        public struct Key: Equatable, Sendable {
            public var frame: Double
            public var value: Double
            /// The handles of the curve from this key to the next: leaving this key, arriving at the next.
            public var out: CGPoint
            public var into: CGPoint
            public init(_ frame: Double, _ value: Double, out: CGPoint = CGPoint(x: 0.33, y: 0), into: CGPoint = CGPoint(x: 0.67, y: 1)) {
                self.frame = frame
                self.value = value
                self.out = out
                self.into = into
            }
        }

        public init(keys: [Key]) { self.keys = keys }
        /// Keys on the usual ease in and out.
        public init(_ keys: [(Double, Double)]) { self.keys = keys.map { Key($0.0, $0.1) } }

        public func value(at frame: Double) -> Double {
            guard let first = keys.first, let last = keys.last else { return 0 }
            if frame <= first.frame { return first.value }
            if frame >= last.frame { return last.value }
            for i in 1..<keys.count where frame <= keys[i].frame {
                let a = keys[i - 1], b = keys[i]
                let t = (frame - a.frame) / (b.frame - a.frame)
                return a.value + (b.value - a.value) * Self.ease(t, a.out, a.into)
            }
            return last.value
        }

        /// How far along a change is when `t` of its time has gone, on the curve with these handles.
        public static func ease(_ t: Double, _ out: CGPoint, _ into: CGPoint) -> Double {
            func curve(_ u: Double, _ a: Double, _ b: Double) -> Double {
                let v = 1 - u
                return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
            }
            guard t > 0 else { return 0 }
            guard t < 1 else { return 1 }
            var low = 0.0, high = 1.0, u = t
            for _ in 0..<40 {
                let x = curve(u, Double(out.x), Double(into.x))
                if abs(x - t) < 1e-9 { break }
                if x < t { low = u } else { high = u }
                u = (low + high) / 2
            }
            return curve(u, Double(out.y), Double(into.y))
        }
    }

    /// One piece of an icon. Pieces are drawn in order, and a piece with a `silhouette` hides what is
    /// behind it, the way a card hides the card under it. (A CGPath never changes once made, which is
    /// what makes this safe to share.)
    public struct Part: @unchecked Sendable {
        /// The closed outline: what it hides behind it, and what the secondary colour fills.
        public var silhouette: CGPath?
        /// Lines in the primary colour.
        public var strokes: CGPath?
        /// Lines that change form with the frame, in place of `strokes`.
        public var shape: (@Sendable (Double) -> CGPath)?
        /// Filled shapes in the primary colour, kept inside the silhouette when there is one.
        public var fills: CGPath?
        /// How much wider than its lines the piece's hiding is: the gap it leaves in what it crosses.
        public var gap: CGFloat = 0
        /// The piece this one rides on (an index into the icon's parts), so a squiggle moves with its canvas.
        public var parent: Int?
        /// The point it turns and grows about.
        public var pivot: CGPoint = .zero
        public var rotation: Track?
        public var dx: Track?
        public var dy: Track?
        public var scale: Track?
        /// How much of it shows, 0...1.
        public var opacity: Track?

        public init(silhouette: CGPath? = nil, strokes: CGPath? = nil, shape: (@Sendable (Double) -> CGPath)? = nil, fills: CGPath? = nil,
                    gap: CGFloat = 0, parent: Int? = nil, pivot: CGPoint = .zero, rotation: Track? = nil, dx: Track? = nil, dy: Track? = nil,
                    scale: Track? = nil, opacity: Track? = nil) {
            self.silhouette = silhouette
            self.strokes = strokes
            self.shape = shape
            self.fills = fills
            self.gap = gap
            self.parent = parent
            self.pivot = pivot
            self.rotation = rotation
            self.dx = dx
            self.dy = dy
            self.scale = scale
            self.opacity = opacity
        }

        /// Its lines at `frame`.
        public func lines(at frame: Double) -> CGPath? { shape?(frame) ?? strokes }

        /// Where the piece is at `frame`, without its parent's move.
        public func transform(at frame: Double) -> CGAffineTransform {
            let turn = (rotation?.value(at: frame) ?? 0) * .pi / 180
            let grow = scale?.value(at: frame) ?? 1
            return CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
                .concatenating(CGAffineTransform(scaleX: grow, y: grow))
                .concatenating(CGAffineTransform(rotationAngle: turn))
                .concatenating(CGAffineTransform(translationX: pivot.x + (dx?.value(at: frame) ?? 0), y: pivot.y + (dy?.value(at: frame) ?? 0)))
        }
    }

    /// Where piece `index` of `parts` is at `frame`, its parents' moves included.
    public static func transform(of index: Int, in parts: [Part], at frame: Double) -> CGAffineTransform {
        var t = parts[index].transform(at: frame)
        var up = parts[index].parent
        while let p = up {
            t = t.concatenating(parts[p].transform(at: frame))
            up = parts[p].parent
        }
        return t
    }

    // MARK: Playing

    /// Which frame an icon shows, as a function of time. The app asks on each display refresh; a test
    /// asks for any moment it likes.
    ///
    /// Picking the page plays hover-start to selection-end once: 34 frames, 0.57 s (Boosts 44, 0.73 s).
    /// Selection-end is the resting drawing again, so a picked icon rests like the others. Picking it
    /// again while it plays starts it over.
    public struct Player: Equatable, Sendable {
        public let icon: LibraryRailIcon
        private var start = -Double.infinity

        public init(_ icon: LibraryRailIcon) { self.icon = icon }

        /// How long the selection takes.
        public var duration: Double { (icon.selectionEnd - LibraryRailIcons.hoverStart) / LibraryRailIcons.frameRate }

        public func frame(at time: Double) -> Double {
            guard start.isFinite else { return LibraryRailIcons.hoverStart }
            return min(icon.selectionEnd, LibraryRailIcons.hoverStart + max(0, time - start) * LibraryRailIcons.frameRate)
        }

        public func isSettled(at time: Double) -> Bool { !start.isFinite || time - start >= duration }

        /// The page was picked.
        public mutating func selected(at time: Double) { start = time }

        /// Takes its rest at once: with Reduce Motion, and when the icon leaves its window.
        public mutating func settle() { start = -.infinity }
    }

    // MARK: Drawing

    /// Draws `icon` as it is at `frame` into the 36 pt box at the context's origin (y down). `secondary`
    /// nil leaves the insides empty: a piece in front still hides the lines behind it.
    ///
    /// The insides go down first and the lines over them, as in Arc's animations. A piece hides the
    /// lines of the pieces behind it (with its `gap` around it), never their insides.
    public static func draw(_ icon: LibraryRailIcon, frame: Double, in ctx: CGContext, primary: CGColor, secondary: CGColor?) {
        let all = parts(icon)
        let solid = primary.copy(alpha: 1) ?? primary
        let places = all.indices.map { transform(of: $0, in: all, at: frame) }
        let shown = all.map { CGFloat(min(1, max(0, $0.opacity?.value(at: frame) ?? 1))) }
        if let secondary {
            for (i, part) in all.enumerated() where shown[i] > 0 {
                guard let outline = part.silhouette else { continue }
                ctx.saveGState()
                ctx.concatenate(places[i])
                ctx.setAlpha(shown[i])
                ctx.setFillColor(secondary)
                ctx.addPath(outline)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
        // The lines in a layer of their own, so a piece hides only this icon's other lines and never what
        // is under the icon.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { ctx.endTransparencyLayer() }
        for (i, part) in all.enumerated() where shown[i] > 0 {
            ctx.saveGState()
            ctx.concatenate(places[i])
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if let outline = part.silhouette {
                ctx.setBlendMode(.clear)
                ctx.setLineWidth(lineWidth + 2 * part.gap)
                ctx.addPath(outline)
                ctx.drawPath(using: .fillStroke)
                ctx.setBlendMode(.normal)
            }
            // One layer at the primary's alpha, so where two lines meet is no stronger than elsewhere.
            ctx.setAlpha(primary.alpha * shown[i])
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setStrokeColor(solid)
            ctx.setFillColor(solid)
            ctx.setLineWidth(lineWidth)
            if let fills = part.fills {
                ctx.saveGState()
                if let outline = part.silhouette {
                    ctx.addPath(outline)
                    ctx.clip()
                }
                ctx.addPath(fills)
                ctx.fillPath()
                ctx.restoreGState()
            }
            if let strokes = part.lines(at: frame) {
                ctx.addPath(strokes)
                ctx.strokePath()
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    /// The rectangle the icon's ink falls in at rest, lines included.
    public static func restBounds(_ icon: LibraryRailIcon) -> CGRect {
        let all = parts(icon)
        var box = CGRect.null
        for (i, part) in all.enumerated() where (part.opacity?.value(at: hoverStart) ?? 1) > 0.5 {
            var t = transform(of: i, in: all, at: hoverStart)
            for path in [part.silhouette, part.lines(at: hoverStart)].compactMap({ $0 }) {
                if let moved = path.copy(using: &t) { box = box.union(moved.boundingBoxOfPath.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)) }
            }
            if let fills = part.fills, part.silhouette == nil, let moved = fills.copy(using: &t) { box = box.union(moved.boundingBoxOfPath) }
        }
        return box
    }

    // MARK: Arc's keys

    typealias Key = Track.Key
    static func key(_ frame: Double, _ value: Double, _ out: (Double, Double) = (0.33, 0), _ into: (Double, Double) = (0.67, 1)) -> Key {
        Key(frame, value, out: CGPoint(x: out.0, y: out.1), into: CGPoint(x: into.0, y: into.1))
    }
    /// A straight line between keys, as Arc's (0.17, 0.17) to (0.83, 0.83).
    static func even(_ frame: Double, _ value: Double) -> Key { key(frame, value, (0.17, 0.17), (0.83, 0.83)) }

    /// Positions in Arc's canvas, as how far from the first key in points.
    static func moved(_ keys: [Key]) -> Track {
        let rest = keys[0].value
        return Track(keys: keys.map { Key($0.frame, ($0.value - rest) * unit, out: $0.out, into: $0.into) })
    }
    /// Sizes, as shares of the first key's.
    static func grown(_ keys: [Key]) -> Track {
        let rest = keys[0].value
        return Track(keys: keys.map { Key($0.frame, $0.value / rest, out: $0.out, into: $0.into) })
    }

    // MARK: Cra's drawings

    public static func parts(_ icon: LibraryRailIcon) -> [Part] {
        switch icon {
        case .media: media
        case .downloads: downloads
        case .easels: easels
        case .spaces: spaces
        case .boosts: boosts
        case .archive: archive
        }
    }

    static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }

    static func lines(_ runs: [[CGPoint]]) -> CGPath {
        let p = CGMutablePath()
        for run in runs { p.addLines(between: run) }
        return p
    }

    /// Two photographs, the back one leaning left, and a sun of its own in the front one. The wind-up
    /// presses both down and straightens the back one; then the front one jumps and nods, the sun
    /// jumps higher, and the back one swings left and settles.
    static let media: [Part] = {
        // Arc's two photographs are centred (16.0, 16.6) and (21.2, 21.0), its sun (18.2, 18.9).
        let back = CGRect(x: 7.2, y: 10.0, width: 17.55, height: 13.25)
        let front = CGRect(x: 12.45, y: 14.4, width: 17.55, height: 13.25)
        // The front photograph's picture: two hills that fill its lower part.
        let hills = CGMutablePath()
        hills.addLines(between: [CGPoint(x: front.minX, y: 25.4), CGPoint(x: 16.9, y: 23.0), CGPoint(x: 19.6, y: 24.8),
                                 CGPoint(x: 24.4, y: 21.2), CGPoint(x: front.maxX, y: 25.2),
                                 CGPoint(x: front.maxX, y: front.maxY), CGPoint(x: front.minX, y: front.maxY)])
        hills.closeSubpath()
        let sun = CGPoint(x: 18.2, y: 18.9)
        return [
            Part(silhouette: rounded(back, 2.6), strokes: rounded(back, 2.6), pivot: CGPoint(x: back.midX, y: back.midY),
                 rotation: Track(keys: [key(1, -7), key(11, 3), key(22, -18.58, (0.3, 0), (0.81, 1)), key(28, -3.21, (0.16, 0), (0.79, 1)), key(35, -7)]),
                 dx: moved([key(1, 54.8, (0.2, 0), (0.83, 1)), key(11, 57.3, (0.3, 0), (0.7, 1)), key(13, 57.3, (0.32, 0), (0.83, 1)), key(35, 54.8)]),
                 dy: moved([key(1, 57.74, (0.21, 0), (0.83, 1)), key(11, 65.24, (0.3, 0), (0.7, 1)), key(13, 65.24, (0.34, 0), (0.79, 0.8)),
                            key(22, 47.8, (0.3, -0.73), (0.7, 1.4)), key(35, 57.74)])),
            Part(silhouette: rounded(front, 2.6), strokes: rounded(front, 2.6), fills: hills, pivot: CGPoint(x: front.midX, y: front.midY),
                 rotation: Track(keys: [key(1, 0), key(11, 0, (0.26, 0), (0.76, 1.43)), key(20, 9.32, (0.29, 0.63), (0.38, 1)), key(31, 0)]),
                 dx: moved([key(11, 78.83, (0.2, 0.96), (0.66, 1)), key(20, 75.83, (0.43, 0), (0.64, 1)), key(31, 78.83)]),
                 dy: moved([key(1, 77.74, (0.23, 0), (0.7, 1)), key(11, 80.74, (0.25, 0), (0.67, 1)), key(20, 62.61, (0.4, 0), (0.66, 1)),
                            key(22, 62.61, (0.28, 0), (0.72, 1)), key(31, 77.74)])),
            Part(fills: circle(sun, 2.0), pivot: sun,
                 dx: moved([key(13, 64.76, (0.14, 0.36), (0.61, 0.92)), key(20, 61.74, (0.14, -0.06), (0.35, 1)), key(35, 64.76)]),
                 dy: moved([key(1, 67.89, (0.32, 0), (0.67, 1)), key(11, 73.61, (0.32, 0), (0.66, 1)), key(13, 73.61, (0.09, 0.35), (0.76, 0.72)),
                            key(20, 51.97, (0.21, -0.71), (0.45, 1)), key(35, 67.89)])),
        ]
    }()

    /// An arrow into a ring. The wind-up presses the arrow down into a shorter shaft as the ring gives a
    /// little; then both jump, the arrow further and later, and drop back past their rest.
    static let downloads: [Part] = {
        let c = CGPoint(x: 18, y: 18)
        let tip = CGPoint(x: 18, y: 22.2), top: CGFloat = 13.6
        // Arc's arrow loses 12 of its 47.3 units from the top by frame 11 and has 1.9 still to go at 21.
        let shorter = Track(keys: [key(1, 0), key(11, 12 * unit), key(21, 1.9 * unit), key(35, 0)])
        let arrow: @Sendable (Double) -> CGPath = { frame in
            lines([[CGPoint(x: tip.x, y: top + shorter.value(at: frame)), tip],
                   [CGPoint(x: 14.65, y: 18.85), tip, CGPoint(x: 21.35, y: 18.85)]])
        }
        return [
            Part(silhouette: circle(c, 9.55), strokes: circle(c, 9.55),
                 dy: moved([key(1, 63.81, (0.33, 0), (0.71, 2.31)), key(11, 66.31, (0.23, 0.15), (0.36, 0.96)), key(19, 52.35, (0.48, -0.04), (0.83, 0.89)),
                            key(30, 64.66, (0.17, -0.7), (0.83, 0.83)), key(35, 63.81)])),
            Part(shape: arrow,
                 dy: moved([key(1, 63.6, (0.33, 0), (0.7, 1.28)), key(11, 73.6, (0.44, 0.2), (0.44, 0.97)), key(21, 52.77, (0.45, -0.03), (0.83, 0.9)),
                            key(30, 64.26, (0.17, -0.98), (0.83, 0.83)), key(35, 63.6)])),
        ]
    }()

    /// A canvas with a bar across its top and a squiggle on it. The wind-up tips it down as the squiggle
    /// shrinks; then it is tossed up and settles.
    static let easels: [Part] = {
        let board = CGRect(x: 8.8, y: 9.3, width: 18.4, height: 17.4)
        let bar = CGPath(rect: CGRect(x: board.minX, y: board.minY, width: board.width, height: 4.6), transform: nil)
        let squiggle = CGMutablePath()
        squiggle.move(to: CGPoint(x: 14.2, y: 23.2))
        squiggle.addCurve(to: CGPoint(x: 17.2, y: 20.6), control1: CGPoint(x: 13.8, y: 20.2), control2: CGPoint(x: 16.6, y: 18.4))
        squiggle.addCurve(to: CGPoint(x: 19.5, y: 21.3), control1: CGPoint(x: 17.8, y: 22.8), control2: CGPoint(x: 19.3, y: 23.2))
        squiggle.addCurve(to: CGPoint(x: 21.9, y: 17.9), control1: CGPoint(x: 19.7, y: 19.4), control2: CGPoint(x: 20.5, y: 18.1))
        return [
            Part(silhouette: rounded(board, 3), strokes: rounded(board, 3), fills: bar, pivot: CGPoint(x: board.midX, y: board.midY),
                 rotation: Track(keys: [key(1, 0), key(11, 6.07), key(18, -3.46), key(35, 0)]),
                 dy: moved([key(1, 66.23), key(11, 71.23), key(18, 60.27), key(35, 66.23)])),
            Part(strokes: squiggle, parent: 0, pivot: CGPoint(x: 18, y: 20.5),
                 scale: grown([key(1, 90, (0.37, 1.25), (0.67, 1)), key(11, 70, (0.28, 0.27), (0.67, 1)), key(18, 90)])),
        ]
    }()

    /// Two cards, the back one leaning left. The wind-up leans the back one right and down; then the
    /// front one flicks up and round as the back one rocks left, and both settle.
    static let spaces: [Part] = {
        // Arc's cards are centred (15.3, 17.4) and (20.8, 20.6). Its back card is drawn leaning 8° left and its
        // layer turns from there, so 8° comes off each of that layer's angles.
        let back = CGRect(x: 8.375, y: 8.325, width: 13.85, height: 18.15)
        let front = CGRect(x: 13.875, y: 11.525, width: 13.85, height: 18.15)
        let lean = -8.0
        return [
            Part(silhouette: rounded(back, 3), strokes: rounded(back, 3), pivot: CGPoint(x: back.midX, y: back.midY),
                 rotation: Track(keys: [key(1, -9.5 + lean), key(13, 14 + lean), key(23, -19.83 + lean), key(35, -9.5 + lean)]),
                 dx: moved([key(1, 51.59), key(13, 56.59), key(23, 51.59), key(35, 51.59)]),
                 dy: moved([key(1, 61.39), key(13, 71.89), key(23, 55.22), key(35, 61.39)])),
            Part(silhouette: rounded(front, 3), strokes: rounded(front, 3), pivot: CGPoint(x: front.midX, y: front.midY),
                 rotation: Track(keys: [key(1, 0), key(11, -5), key(19, 28.96), key(35, 0)]),
                 dy: moved([key(1, 75.98), key(11, 78.23), key(19, 55.76), key(35, 75.98)])),
        ]
    }()

    /// A broad brush across a tilted tile, with two sparks. The brush swings one way and the other from
    /// its handle, its bristles trailing; the tile rocks against it; the sparks sink, go out one after
    /// the other, and come back from above.
    static let boosts: [Part] = {
        // Arc's tile is about 20 pt across, turning about (17.5, 17.8); its brush turns about the end of
        // its handle, (8, 28), and reaches (22.7, 11.2).
        let tile = CGRect(x: 7.3, y: 7.4, width: 20.6, height: 20.6)
        // The brush stands upright here and is laid over by `lean`: bristles, the band, the handle.
        let lean = CGAffineTransform(translationX: 14.28, y: 20.75).rotated(by: 40 * .pi / 180)
        func leaned(_ path: CGPath) -> CGPath { var t = lean; return path.copy(using: &t) ?? path }
        let bristles = CGMutablePath()
        bristles.move(to: CGPoint(x: -4.2, y: 0))
        bristles.addLine(to: CGPoint(x: -4.2, y: -4.4))
        bristles.addQuadCurve(to: CGPoint(x: -1.8, y: -6.6), control: CGPoint(x: -4.2, y: -6.6))
        bristles.addLine(to: CGPoint(x: 4.2, y: -6.6))
        bristles.addLine(to: CGPoint(x: 4.2, y: 0))
        bristles.closeSubpath()
        let grip = CGMutablePath()
        grip.addPath(leaned(rounded(CGRect(x: -4.2, y: 0, width: 8.4, height: 2.8), 0.9)))
        grip.addPath(leaned(rounded(CGRect(x: -1.7, y: 2.8, width: 3.4, height: 9.4), 1.7)))
        func spark(_ c: CGPoint, _ r: CGFloat) -> CGPath {
            // Four points with sides drawn in toward the middle.
            let p = CGMutablePath()
            let tips = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
            p.move(to: tips[0])
            for k in 1...4 {
                let a = tips[k - 1], b = tips[k % 4]
                p.addQuadCurve(to: b, control: CGPoint(x: c.x + (a.x + b.x - 2 * c.x) * 0.2, y: c.y + (a.y + b.y - 2 * c.y) * 0.2))
            }
            p.closeSubpath()
            return p
        }
        let big = CGPoint(x: 23.3, y: 13.6), small = CGPoint(x: 19.4, y: 10.9)
        let handleEnd = CGPoint(x: 0, y: 12.2).applying(lean)
        let bandTop = CGPoint(x: 0, y: 0).applying(lean)
        return [
            Part(silhouette: rounded(tile, 5.2), strokes: rounded(tile, 5.2), pivot: CGPoint(x: tile.midX, y: tile.midY),
                 rotation: Track(keys: [key(6, -15, (0.46, 0), (0.74, 1)), key(17, -23, (0.23, 0), (0.83, 0.96)), key(29, -5.4, (0.17, -0.06), (0.83, 0.83)), key(39, -15)]),
                 dy: moved([key(6, 63.14, (0.35, 0), (0.69, 1)), key(17, 68.14, (0.32, 0), (0.59, 1)), key(29.373, 55.14, (0.4, 0), (0.54, 1)), key(39.373, 63.14)])),
            Part(silhouette: grip, strokes: grip, gap: 1.1, pivot: handleEnd,
                 rotation: Track(keys: [key(1, 0, (0.66, 0), (0.73, 1.17)), key(14, 11.95, (0.29, 0.06), (0.69, 0.91)), key(25, -16.56, (0.44, -0.27), (0.53, 1)), key(39, 0)]),
                 dy: moved([key(1, 109.5, (0.6, 0.94), (0.83, 1.29)), key(15, 112.0, (0.33, 0.05), (0.67, 1)), key(22, 97.96, (0.33, 0), (0.48, 1)), key(34, 109.5)])),
            // Arc's bristles shift 8.7 units to the left at their tips by frame 27 and are back by 43.
            Part(silhouette: leaned(bristles), strokes: leaned(bristles), gap: 1.1, parent: 1, pivot: bandTop,
                 rotation: Track(keys: [key(22, 0), key(27, -10), key(43, 0)])),
            Part(fills: spark(big, 2.9), pivot: big,
                 dy: moved([key(9, 50.17, (0.29, 0), (0.83, 1.11)), key(17.191, 61.23, (0.17, 0.06), (0.64, 1)), key(28, 33.34, (0.45, 0), (0.63, 1)), key(40, 50.17)]),
                 scale: Track(keys: [even(15, 1), even(19, 0), even(24, 0), even(28, 1)])),
            Part(fills: spark(small, 1.9), pivot: small,
                 dy: moved([key(12, 37.08, (0.29, 0), (0.83, 1.16)), key(20.191, 44.63, (0.17, 0.07), (0.64, 1)), key(31, 20.25, (0.45, 0), (0.63, 1)), key(42, 37.08)]),
                 scale: Track(keys: [even(25, 1), even(29, 0), even(34, 0), even(38, 1)])),
        ]
    }()

    /// A box with a lid and a slot. The wind-up presses the lid down and the slot bends into a smile;
    /// then the lid flies up and tips, the box jumps after it showing its rim, and they come back
    /// together.
    static let archive: [Part] = {
        let lid = CGRect(x: 8.625, y: 10.2, width: 18.75, height: 3.8)
        let body = CGMutablePath()
        let left: CGFloat = 10.2, right: CGFloat = 25.8, top: CGFloat = 14.0, bottom: CGFloat = 27.05, r: CGFloat = 2.4
        body.move(to: CGPoint(x: left, y: top))
        body.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: right, y: bottom), radius: r)
        body.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: top), radius: r)
        body.addLine(to: CGPoint(x: right, y: top))
        let closed = body.mutableCopy() ?? CGMutablePath()
        closed.closeSubpath()
        // Arc's slot sags 2.5 units in the middle at frame 11 and is straight again by 21.
        let sag = Track(keys: [key(1, 0), key(11, 2.5 * unit), key(21, 0)])
        let slot: @Sendable (Double) -> CGPath = { frame in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 14.8, y: 18.2))
            p.addQuadCurve(to: CGPoint(x: 21.2, y: 18.2), control: CGPoint(x: 18, y: 18.2 + 2 * sag.value(at: frame)))
            return p
        }
        return [
            Part(silhouette: closed, strokes: body,
                 dy: moved([key(11, 79.05, (0.15, 0.41), (0.34, 1)), key(21, 63.25, (0.33, 0), (0.62, 0.55)), key(27, 79.05)])),
            // The box's rim, which shows while the lid is off it (Arc keeps it at 7 % under the resting lid).
            Part(strokes: lines([[CGPoint(x: left, y: top + 1.5), CGPoint(x: right, y: top + 1.5)]]), parent: 0,
                 opacity: Track(keys: [even(14, 0.07), even(17, 1), even(33, 1), even(35, 0)])),
            Part(shape: slot,
                 dy: moved([key(1, 65, (0.38, 0), (0.44, 1)), key(11, 74.04, (0.43, 0), (0.73, -0.57)), key(16, 72.42, (0.34, 0.28), (0.7, 0.79)),
                            key(21, 61.03, (0.22, -1.27), (0.34, 1.22)), key(35, 65)])),
            Part(silhouette: rounded(lid, 1.6), strokes: rounded(lid, 1.6), pivot: CGPoint(x: lid.midX, y: lid.midY),
                 rotation: Track(keys: [key(11, 0, (0.6, 0), (0.65, 1.27)), key(22, -5.57, (0.43, 0.14), (0.38, 1)), key(29, 3, (0.41, 0), (0.49, 1)), key(35, 0)]),
                 dy: moved([key(1, 37.15, (0.21, 0), (0.56, 1)), key(11, 45.44, (0.38, 0), (0.55, 1)), key(22, 17.08, (0.73, 0), (0.63, 1)), key(35, 37.15)])),
        ]
    }()
}

/// A tile of the Library's rail: its size, where its icon and label sit, and how it looks at rest,
/// under the pointer, pressed and when its page is the one shown. Arc 1.174's numbers, read from its
/// code (`PageSidebarItemButtonStyle`, `AnimatedPageSidebarItemView`, `HomePageView`) and checked
/// against a 2x capture.
public enum LibraryRailTile {
    /// The rail is 112 pt with 8 pt before the tiles and 7 after; a tile is at most 80 pt tall in a
    /// 100 pt slot.
    public static let size = CGSize(width: 97, height: 80)
    public static let cornerRadius: CGFloat = 12
    /// Between one tile and the next.
    public static let spacing: CGFloat = 20
    /// Arc's icon is a 28 pt view over the 11 pt label's line, 4 pt apart, the pair centred in the tile.
    /// Cra's drawings have a 36 pt box around the same centre, so nothing is cut off as they move.
    public static let arcIconSize: CGFloat = 28
    public static let iconBox: CGFloat = LibraryRailIcons.canvas
    public static let iconLabelGap: CGFloat = 4
    public static let labelSize: CGFloat = 11
    /// The label's line: 11 pt bold.
    public static let labelLine: CGFloat = 13
    /// How far the icon's box is under the top of a tile this tall: over its label, the pair centred, or
    /// centred alone when the label is dropped.
    public static func iconTop(tileHeight: CGFloat = size.height, showsLabel: Bool = true) -> CGFloat {
        let stack = showsLabel ? arcIconSize + iconLabelGap + labelLine : arcIconSize
        return (tileHeight - stack) / 2 - (iconBox - arcIconSize) / 2
    }
    /// How far the label's line is under the tile's top.
    public static func labelTop(tileHeight: CGFloat = size.height) -> CGFloat {
        (tileHeight - arcIconSize - iconLabelGap - labelLine) / 2 + arcIconSize + iconLabelGap
    }

    /// Each page has a slot of up to 100 pt, and its tile is as tall as the slot, 80 pt at most. In a
    /// window too short for that the slots share what room there is; a slot of 64 pt or less drops the
    /// label, and the page's name shows as a tooltip instead (Arc's `.small` style, after 0.45 s).
    public static let slotHeight: CGFloat = 100
    public static let labelSlotFloor: CGFloat = 64
    public static let tooltipDelay = 0.45

    /// Where the rail's tiles go.
    public struct Column: Equatable, Sendable {
        /// The first tile's top, from the rail's top.
        public var top: CGFloat
        /// From one tile's top to the next.
        public var slot: CGFloat
        public var tileHeight: CGFloat
        public var showsLabel: Bool

        public init(top: CGFloat, slot: CGFloat, tileHeight: CGFloat, showsLabel: Bool) {
            self.top = top
            self.slot = slot
            self.tileHeight = tileHeight
            self.showsLabel = showsLabel
        }
    }

    /// The column of `count` tiles in a rail `height` tall that keeps `topInset` and `bottomInset` clear:
    /// centred above the bottom inset while there is room, from the top inset once there isn't.
    public static func column(count: Int, height: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> Column {
        let n = CGFloat(max(1, count))
        let room = max(0, height - topInset - bottomInset)
        // An icon alone needs its 28 pt and a little air.
        let slot = min(slotHeight, max(arcIconSize + 4, room / n))
        let tile = min(slot, size.height)
        let group = slot * (n - 1) + tile
        let top = max(topInset, (height - bottomInset - group) / 2)
        return Column(top: top, slot: slot, tileHeight: tile, showsLabel: slot > labelSlotFloor)
    }

    /// The sidebar's ink is the system's label colour: white on a dark theme and black on a light one,
    /// at this strength. The tile's wash and its label are shares of it.
    public static let inkStrength = 0.85
    /// While the tile is pressed its wash alone draws in by this much on every side, on a spring
    /// (response 0.18 s, damping 0.8); the icon and the label stay put.
    public static let pressedInset: CGFloat = 2
    public static let pressResponse = 0.18
    public static let pressDamping = 0.8

    /// How the tile looks: its wash and its label as a share of the ink, its icon's lines as the alpha
    /// of the theme's line colour, and whether the icon's insides are filled in.
    public struct Look: Equatable, Sendable {
        public var wash: Double
        public var label: Double
        public var lines: Double
        /// The page shown: the insides take the theme's second colour, whole.
        public var filled: Bool

        public init(wash: Double, label: Double, lines: Double, filled: Bool) {
            self.wash = wash
            self.label = label
            self.lines = lines
            self.filled = filled
        }
    }

    /// The pointer changes the wash and nothing else; being the page shown changes everything.
    public static func look(selected: Bool, hovered: Bool) -> Look {
        if selected { return Look(wash: 0.1, label: 1, lines: 1, filled: true) }
        return Look(wash: hovered ? 0.05 : 0, label: 0.7, lines: 0.7, filled: false)
    }

    /// The icon's two colours for a space's theme: its lines in the palette's `maxContrastColor` and
    /// its insides in `cutoutColor` (on a dark sidebar the theme's light tint over its darkest shade,
    /// on a light one the other way round).
    public static func iconColors(theme: SpaceTheme, dark: Bool) -> (lines: RGB, inside: RGB) {
        let slots = Dictionary(ArcThemeData.palette(theme: theme, dark: dark).map { ($0.0, $0.1.rgb) }, uniquingKeysWith: { a, _ in a })
        return (slots["maxContrastColor"] ?? (dark ? .white : .black), slots["cutoutColor"] ?? (dark ? .black : .white))
    }
}
