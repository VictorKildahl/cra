import CoreGraphics
import CraCore
import Testing

/// The Library rail's icons play as Arc's do: once when their page is picked, on Arc 1.174's timeline
/// (60 a second; hover-start 1, selection-end 35, Boosts 45), in the theme's two colours, on a tile with
/// Arc's washes. The rules are read from Arc's code (`HomeButton/PageSidebarItem.swift`); the drawings
/// are Cra's own.
@Suite struct LibraryRailIconsTests {
    typealias I = LibraryRailIcons

    // MARK: Which frame shows when

    @Test(arguments: LibraryRailIcon.allCases) func restsOnHoverStartUntilPicked(_ icon: LibraryRailIcon) {
        let p = I.Player(icon)
        for t in [0.0, 0.1, 5, 1000] {
            #expect(p.frame(at: t) == 1)
            #expect(p.isSettled(at: t))
        }
    }

    /// Arc: `play(fromMarker: "hover-start", toMarker: "selection-end")`, once, at speed 1.
    @Test(arguments: LibraryRailIcon.allCases) func pickingPlaysHoverStartToSelectionEndOnce(_ icon: LibraryRailIcon) {
        var p = I.Player(icon)
        p.selected(at: 10)
        let end = icon == .boosts ? 45.0 : 35.0
        #expect(icon.selectionEnd == end)
        #expect(abs(p.duration - (end - 1) / 60) < 1e-9)
        #expect(p.frame(at: 10) == 1)
        #expect(!p.isSettled(at: 10.2))
        #expect(abs(p.frame(at: 10 + 12.0 / 60) - 13) < 1e-6)
        #expect(abs(p.frame(at: 10 + 0.5) - 31) < 1e-6)
        #expect(p.frame(at: 10 + p.duration + 1e-6) == end)
        #expect(p.isSettled(at: 10 + p.duration + 1e-6))
        // It stays there: no loop, and nothing more plays by itself.
        #expect(p.frame(at: 60) == end && p.frame(at: 6000) == end)
    }

    @Test func theSelectionTakesAboutHalfASecond() {
        #expect(abs(I.Player(.media).duration - 0.5667) < 0.001)
        #expect(abs(I.Player(.boosts).duration - 0.7333) < 0.001)
    }

    @Test func pickingAgainWhileItPlaysStartsItOver() {
        var p = I.Player(.spaces)
        p.selected(at: 0)
        p.selected(at: 0.3)
        #expect(p.frame(at: 0.3) == 1)
        #expect(abs(p.frame(at: 0.4) - 7) < 1e-6)
    }

    @Test func settlingPutsItAtRestAtOnce() {
        var p = I.Player(.downloads)
        p.selected(at: 0)
        p.settle()
        #expect(p.frame(at: 0.1) == 1 && p.isSettled(at: 0.1))
    }

    // MARK: The tile

    /// Arc's `PageSidebarItemButtonStyle`: `Color.primary` at 10 % behind the page shown, 5 % under the
    /// pointer, nothing otherwise; the label at 100 % or 70 %; the icon's lines at 100 % or 70 % and its
    /// insides only on the page shown. The pointer changes the wash and nothing else.
    @Test func looksAreArcs() {
        typealias T = LibraryRailTile
        #expect(T.look(selected: false, hovered: false) == T.Look(wash: 0, label: 0.7, lines: 0.7, filled: false))
        #expect(T.look(selected: false, hovered: true) == T.Look(wash: 0.05, label: 0.7, lines: 0.7, filled: false))
        #expect(T.look(selected: true, hovered: false) == T.Look(wash: 0.1, label: 1, lines: 1, filled: true))
        #expect(T.look(selected: true, hovered: true) == T.look(selected: true, hovered: false))
        #expect(T.inkStrength == 0.85)
    }

    /// 97 x 80 pt tiles 100 pt apart with 12 pt corners; a 28 pt icon and an 11 pt label 4 pt apart,
    /// centred: the icon's middle 31.5 pt and the label's line 49.5 pt under the tile's top (a 2x capture
    /// of Arc has the icons' ink centred 31.5 pt down and the labels' baseline at 60).
    @Test func layoutIsArcs() {
        typealias T = LibraryRailTile
        #expect(T.size == CGSize(width: 97, height: 80))
        #expect(T.size.height + T.spacing == 100)
        #expect(T.cornerRadius == 12)
        #expect(T.labelSize == 11)
        #expect(T.iconTop() + T.iconBox / 2 == 31.5)
        #expect(T.labelTop() == 49.5)
        #expect(T.pressedInset == 2 && T.pressResponse == 0.18 && T.pressDamping == 0.8)
    }

    /// Arc's `HomePageView`: a slot of up to 100 pt for each page, shared out when the window is short;
    /// the tile as tall as its slot, 80 pt at most; and no label in a slot of 64 pt or less.
    @Test func aShortRailShrinksItsTilesThenDropsTheirLabels() {
        typealias T = LibraryRailTile
        // Room for all six at 100 pt: centred above the back arrow, 100 pt apart.
        let tall = T.column(count: 6, height: 1000, topInset: 44, bottomInset: 40)
        #expect(tall == T.Column(top: (960 - 580) / 2, slot: 100, tileHeight: 80, showsLabel: true))
        // Just enough: from the top inset.
        #expect(T.column(count: 6, height: 44 + 40 + 600, topInset: 44, bottomInset: 40) == T.Column(top: 44, slot: 100, tileHeight: 80, showsLabel: true))
        // Slots of 90: tiles still 80 with their labels, closer together.
        let closer = T.column(count: 6, height: 84 + 540, topInset: 44, bottomInset: 40)
        #expect(closer == T.Column(top: 44, slot: 90, tileHeight: 80, showsLabel: true))
        // Slots of 70: the tiles touch, 70 tall, labels still on.
        let touching = T.column(count: 6, height: 84 + 420, topInset: 44, bottomInset: 40)
        #expect(touching == T.Column(top: 44, slot: 70, tileHeight: 70, showsLabel: true))
        // 64 or less: the label goes.
        #expect(T.column(count: 6, height: 84 + 6 * 64.5, topInset: 44, bottomInset: 40).showsLabel)
        let small = T.column(count: 6, height: 84 + 6 * 64, topInset: 44, bottomInset: 40)
        #expect(small == T.Column(top: 44, slot: 64, tileHeight: 64, showsLabel: false))
        // The icon is then centred in its tile, and it never gets less than its own height and a little air.
        #expect(T.iconTop(tileHeight: 64, showsLabel: false) + T.iconBox / 2 == 32)
        #expect(T.iconTop(tileHeight: 70, showsLabel: true) + T.iconBox / 2 == 26.5)
        #expect(T.labelTop(tileHeight: 70) == 44.5)
        #expect(T.column(count: 6, height: 100, topInset: 44, bottomInset: 40).slot == 32)
        #expect(T.tooltipDelay == 0.45)
    }

    /// The icon's lines are the palette's maxContrastColor and its insides the cutoutColor: on a dark
    /// sidebar the theme's light tint over its darkest shade, on a light one the other way round.
    @Test func iconColoursAreTheThemesTwo() {
        let theme = SpaceTheme(colors: ["#5B5FC7"], intensity: 0.6, noise: 0.2, appearance: "dark")
        let dark = LibraryRailTile.iconColors(theme: theme, dark: true), light = LibraryRailTile.iconColors(theme: theme, dark: false)
        #expect(dark.lines == theme.tintedLight && dark.inside == theme.shadedDark)
        #expect(light.lines == theme.shadedDark && light.inside == theme.tintedLight)
        func luma(_ c: RGB) -> Double { 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
        #expect(luma(dark.lines) > luma(dark.inside) + 0.3)
    }

    // MARK: The drawings over the timeline

    @Test func aTrackHoldsOutsideItsKeysAndEasesBetweenThem() {
        let t = I.Track([(11, 0), (21, 10), (31, 4)])
        #expect(t.value(at: 0) == 0 && t.value(at: 11) == 0)
        #expect(t.value(at: 16) == 5)
        #expect(t.value(at: 13) < 3 && t.value(at: 19) > 7)
        #expect(t.value(at: 21) == 10)
        #expect(t.value(at: 26) == 7)
        #expect(t.value(at: 31) == 4 && t.value(at: 90) == 4)
        var last = 0.0
        for i in 0...100 {
            let v = t.value(at: 11 + Double(i) / 10)
            #expect(v >= last)
            last = v
        }
    }

    /// Selection-end is the resting drawing again, so a picked icon looks like the others at rest.
    @Test(arguments: LibraryRailIcon.allCases) func everyPieceEndsWhereItRests(_ icon: LibraryRailIcon) {
        let parts = I.parts(icon)
        #expect(!parts.isEmpty)
        for i in parts.indices {
            let rest = I.transform(of: i, in: parts, at: 1), end = I.transform(of: i, in: parts, at: icon.selectionEnd)
            for (a, b) in zip([rest.a, rest.b, rest.c, rest.d, rest.tx, rest.ty], [end.a, end.b, end.c, end.d, end.tx, end.ty]) {
                #expect(abs(a - b) < 1e-9, "piece \(i)")
            }
            #expect(I.transform(of: i, in: parts, at: 0) == rest)
        }
    }

    /// Something moves in the wind-up (to frame 11) and something more after it, in every icon.
    @Test(arguments: LibraryRailIcon.allCases) func theWindUpAndTheReleaseBothMoveSomething(_ icon: LibraryRailIcon) {
        let parts = I.parts(icon)
        func moved(_ a: Double, _ b: Double) -> Bool {
            parts.indices.contains { I.transform(of: $0, in: parts, at: a) != I.transform(of: $0, in: parts, at: b) }
        }
        #expect(moved(1, 11))
        #expect(moved(11, (11 + icon.selectionEnd) / 2))
    }

    @Test func aPieceRidesOnItsParent() {
        // The easel's squiggle tips with its canvas.
        let parts = I.parts(.easels)
        #expect(parts[1].parent == 0)
        let alone = parts[1].transform(at: 11), carried = I.transform(of: 1, in: parts, at: 11)
        #expect(alone.b == 0)
        #expect(carried.b != 0)
    }

    // MARK: What is drawn

    struct Bitmap {
        let ctx: CGContext
        let scale: Int
        init(scale: Int = 4) {
            self.scale = scale
            let n = 36 * scale
            ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // y down, in points.
            ctx.translateBy(x: 0, y: CGFloat(n))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        }

        /// Red, green, blue (premultiplied) and alpha at a point, 0...255.
        func pixel(_ x: Double, _ y: Double) -> [Int] {
            let n = 36 * scale
            let px = min(n - 1, max(0, Int(x * Double(scale)))), py = min(n - 1, max(0, Int(y * Double(scale))))
            let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
            let i = (py * n + px) * 4
            return [Int(p[i]), Int(p[i + 1]), Int(p[i + 2]), Int(p[i + 3])]
        }

        /// The rectangle holding every pixel with any ink, in points.
        var inkBounds: CGRect {
            let n = 36 * scale
            var x0 = n, y0 = n, x1 = -1, y1 = -1
            for y in 0..<n { for x in 0..<n where pixel(Double(x) / Double(scale), Double(y) / Double(scale))[3] > 24 {
                x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
            } }
            guard x1 >= 0 else { return .null }
            let s = CGFloat(scale)
            return CGRect(x: CGFloat(x0) / s, y: CGFloat(y0) / s, width: CGFloat(x1 - x0 + 1) / s, height: CGFloat(y1 - y0 + 1) / s)
        }
    }

    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let navy = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    /// How big each icon is at rest, as Arc 1.174's are at 2x (width, height in points), within 1.5 pt,
    /// and centred in its box.
    @Test(arguments: [(LibraryRailIcon.media, 26.0, 21.0), (.downloads, 21, 21), (.easels, 20, 19), (.spaces, 23.5, 25),
                      (.boosts, 25, 25), (.archive, 20, 18.5)])
    func isTheSizeOfArcs(_ icon: LibraryRailIcon, _ width: Double, _ height: Double) {
        let b = Bitmap()
        I.draw(icon, frame: 1, in: b.ctx, primary: Self.white, secondary: nil)
        let ink = b.inkBounds
        #expect(abs(ink.width - width) <= 1.5, "\(icon) is \(ink.width) wide")
        #expect(abs(ink.height - height) <= 1.5, "\(icon) is \(ink.height) tall")
        #expect(abs(ink.midX - 18) <= 1.25 && abs(ink.midY - 18) <= 1.25, "\(icon) sits at \(ink.midX), \(ink.midY)")
        // What CraCore says the ink's box is, is where the ink is.
        let said = I.restBounds(icon)
        #expect(abs(said.minX - ink.minX) < 0.8 && abs(said.maxX - ink.maxX) < 0.8 && abs(said.minY - ink.minY) < 0.8 && abs(said.maxY - ink.maxY) < 0.8)
    }

    /// No frame of any icon reaches the edge of its box, so nothing is cut off while it moves.
    @Test(arguments: LibraryRailIcon.allCases) func staysInsideItsBoxThroughout(_ icon: LibraryRailIcon) {
        var frame = 0.0
        while frame <= icon.selectionEnd {
            let b = Bitmap(scale: 2)
            I.draw(icon, frame: frame, in: b.ctx, primary: Self.white, secondary: Self.navy)
            let ink = b.inkBounds
            #expect(ink.minX >= 0.5 && ink.minY >= 0.5 && ink.maxX <= 35.5 && ink.maxY <= 35.5, "\(icon) at frame \(frame): \(ink)")
            frame += 1
        }
    }

    /// The front card hides the back card's line under it, with nothing filling it; picked, it is
    /// filled with the second colour there.
    @Test func aPieceInFrontHidesTheLinesBehindIt() {
        // The back card's right edge runs through here, well inside the front card.
        let under = (22.3, 16.6)
        let b = Bitmap()
        I.draw(.spaces, frame: 1, in: b.ctx, primary: Self.white, secondary: nil)
        #expect(b.pixel(under.0, under.1)[3] == 0)
        // The back card's top edge, clear of the front card, is drawn.
        #expect(b.pixel(13.9, 7.55)[3] > 200)
        let picked = Bitmap()
        I.draw(.spaces, frame: 1, in: picked.ctx, primary: Self.white, secondary: Self.navy)
        #expect(picked.pixel(under.0, under.1) == [0, 0, 255, 255])
    }

    @Test func linesTakeThePrimaryAndInsidesTheSecondary() {
        let b = Bitmap()
        I.draw(.downloads, frame: 1, in: b.ctx, primary: Self.white, secondary: Self.navy)
        #expect(b.pixel(18, 8.4) == [255, 255, 255, 255])   // the ring
        #expect(b.pixel(18, 17) == [255, 255, 255, 255])    // the arrow's shaft
        #expect(b.pixel(12.5, 14) == [0, 0, 255, 255])      // inside the ring
        #expect(b.pixel(3, 3)[3] == 0)                      // outside it
    }

    /// At 60 % the lines are 60 % everywhere: no stronger where the arrow's head meets its shaft.
    @Test func aFaintPrimaryIsEvenWhereLinesMeet() {
        let b = Bitmap()
        I.draw(.downloads, frame: 1, in: b.ctx, primary: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6), secondary: nil)
        for p in [(18.0, 8.4), (18.0, 17.0), (18.0, 22.2)] {
            #expect(abs(b.pixel(p.0, p.1)[3] - 153) <= 2, "at \(p)")
        }
    }

    /// Drawing an icon leaves what is under it alone: only the icon's own pieces hide each other.
    @Test func neverCutsAHoleInWhatIsUnderIt() {
        let b = Bitmap()
        b.ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        b.ctx.fill(CGRect(x: 0, y: 0, width: 36, height: 36))
        I.draw(.spaces, frame: 1, in: b.ctx, primary: Self.white, secondary: nil)
        #expect(b.pixel(22.3, 16.6) == [255, 0, 0, 255])
        #expect(b.pixel(22, 22)[3] == 255)
    }

    // MARK: Arc's motion, key for key

    /// The curve between two keys is the first key's cubic: even handles are a straight line, the usual
    /// ones ease in and out, and handles outside 0...1 take the value past where it is headed.
    @Test func easingFollowsTheKeysHandles() {
        typealias P = CGPoint
        for t in [0.0, 0.25, 0.5, 0.8, 1] {
            #expect(abs(I.Track.ease(t, P(x: 0.17, y: 0.17), P(x: 0.83, y: 0.83)) - t) < 1e-6)
        }
        let usual = { (t: Double) in I.Track.ease(t, P(x: 0.33, y: 0), P(x: 0.67, y: 1)) }
        #expect(abs(usual(0.5) - 0.5) < 1e-6)
        #expect(usual(0.2) < 0.15 && usual(0.8) > 0.85)
        // Arc's back photograph, frames 22 to 35: it starts by going on the way it was going.
        let back = { (t: Double) in I.Track.ease(t, P(x: 0.3, y: -0.73), P(x: 0.7, y: 1.4)) }
        #expect(back(0.1) < -0.05)
        #expect(back(0.9) > 1.02)
        #expect(back(0) == 0 && back(1) == 1)
    }

    func place(_ icon: LibraryRailIcon, _ part: Int, _ frame: Double) -> (dx: Double, dy: Double, turn: Double, size: Double) {
        let parts = I.parts(icon), p = parts[part]
        return (p.dx?.value(at: frame) ?? 0, p.dy?.value(at: frame) ?? 0, p.rotation?.value(at: frame) ?? 0, p.scale?.value(at: frame) ?? 1)
    }
    /// Arc's canvas units as points: its 128-unit animations show 28 pt wide.
    func pt(_ units: Double) -> Double { units * 28 / 128 }
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

    /// Spaces: the back card rests 17.5° to the left (Arc draws it 8° over and turns its layer 9.5°),
    /// leans to +6° and 10.5 units down by frame 13, rocks to −27.8° by 23; the front card dips, then is
    /// 20.2 units up and 29° round at frame 19.
    @Test func spacesMovesAsArcs() {
        #expect(near(place(.spaces, 0, 1).turn, -17.5))
        #expect(near(place(.spaces, 0, 13).turn, 6) && near(place(.spaces, 0, 13).dy, pt(10.5)) && near(place(.spaces, 0, 13).dx, pt(5)))
        #expect(near(place(.spaces, 0, 23).turn, -27.83) && near(place(.spaces, 0, 23).dy, pt(55.22 - 61.39)))
        #expect(near(place(.spaces, 1, 11).turn, -5) && near(place(.spaces, 1, 11).dy, pt(2.25)))
        #expect(near(place(.spaces, 1, 19).turn, 28.96) && near(place(.spaces, 1, 19).dy, pt(55.76 - 75.98)))
        #expect(near(place(.spaces, 1, 35).turn, 0) && near(place(.spaces, 1, 35).dy, 0))
    }

    /// Media: both photographs press down in the wind-up (the back one 7.5 units and to +3°), the front
    /// one jumps 15 units and nods 9.3° at frame 20, the sun jumps 15.9, and the back one swings to
    /// −18.6° at 22.
    @Test func mediaMovesAsArcs() {
        #expect(near(place(.media, 0, 1).turn, -7) && near(place(.media, 0, 11).turn, 3))
        #expect(near(place(.media, 0, 11).dy, pt(7.5)) && near(place(.media, 0, 11).dx, pt(2.5)))
        #expect(near(place(.media, 0, 22).turn, -18.58) && near(place(.media, 0, 22).dy, pt(47.8 - 57.74)))
        #expect(near(place(.media, 1, 11).dy, pt(3)) && near(place(.media, 1, 11).turn, 0))
        #expect(near(place(.media, 1, 20).dy, pt(62.61 - 77.74)) && near(place(.media, 1, 20).turn, 9.32) && near(place(.media, 1, 20).dx, pt(-3)))
        #expect(near(place(.media, 1, 31).dy, 0))
        // The sun is a piece of its own: it goes further than its photograph and comes back later.
        #expect(I.parts(.media)[2].parent == nil)
        #expect(near(place(.media, 2, 20).dy, pt(51.97 - 67.89)))
        #expect(place(.media, 2, 31).dy < -0.05 && near(place(.media, 2, 35).dy, 0))
    }

    /// Downloads: the ring gives 2.5 units and jumps 11.5 by frame 19; the arrow goes 10 down, losing 12
    /// of its 47.3 units of length from the top, then 10.8 up by 21; both come back past their rest.
    @Test func downloadsMovesAsArcs() {
        #expect(near(place(.downloads, 0, 11).dy, pt(2.5)) && near(place(.downloads, 0, 19).dy, pt(52.35 - 63.81)))
        #expect(place(.downloads, 0, 30).dy > 0 && near(place(.downloads, 0, 35).dy, 0))
        #expect(near(place(.downloads, 1, 11).dy, pt(10)) && near(place(.downloads, 1, 21).dy, pt(52.77 - 63.6)))
        #expect(place(.downloads, 1, 30).dy > 0 && near(place(.downloads, 1, 35).dy, 0))
        func shaft(_ frame: Double) -> Double { Double(I.parts(.downloads)[1].lines(at: frame)!.boundingBoxOfPath.height) }
        #expect(near(shaft(1) - shaft(11), pt(12)))
        #expect(near(shaft(1) - shaft(21), pt(1.9)))
        #expect(near(shaft(35), shaft(1)))
    }

    /// Easels: the canvas tips 6.07° and sinks 5 units as its squiggle shrinks to 70/90, then is 6 units
    /// up at −3.46° by frame 18.
    @Test func easelsMovesAsArcs() {
        #expect(near(place(.easels, 0, 11).turn, 6.07) && near(place(.easels, 0, 11).dy, pt(5)))
        #expect(near(place(.easels, 0, 18).turn, -3.46) && near(place(.easels, 0, 18).dy, pt(60.27 - 66.23)))
        #expect(near(place(.easels, 1, 11).size, 70.0 / 90) && near(place(.easels, 1, 18).size, 1))
    }

    /// Boosts: the tile rocks −15° to −23° to −5.4° and back; the brush swings 11.95° then −16.56° about
    /// its handle's end, its bristles 10° behind at frame 27; each spark sinks, is gone for five frames
    /// and comes back from above, the small one ten frames after the big one.
    @Test func boostsMovesAsArcs() {
        #expect(near(place(.boosts, 0, 1).turn, -15) && near(place(.boosts, 0, 17).turn, -23) && near(place(.boosts, 0, 29).turn, -5.4))
        #expect(near(place(.boosts, 0, 17).dy, pt(5)) && near(place(.boosts, 0, 45).turn, -15))
        #expect(near(place(.boosts, 1, 14).turn, 11.95) && near(place(.boosts, 1, 25).turn, -16.56) && near(place(.boosts, 1, 39).turn, 0))
        #expect(near(place(.boosts, 1, 22).dy, pt(97.96 - 109.5)))
        #expect(I.parts(.boosts)[2].parent == 1 && near(place(.boosts, 2, 27).turn, -10) && near(place(.boosts, 2, 43).turn, 0))
        for (spark, gone) in [(3, 19.0), (4, 29.0)] {
            #expect(near(place(.boosts, spark, gone - 4).size, 1))
            #expect(place(.boosts, spark, gone).size == 0 && place(.boosts, spark, gone + 5).size == 0)
            #expect(near(place(.boosts, spark, gone + 9).size, 1))
        }
        #expect(near(place(.boosts, 3, 17.191).dy, pt(61.23 - 50.17)) && near(place(.boosts, 3, 28).dy, pt(33.34 - 50.17)) && near(place(.boosts, 3, 40).dy, 0))
        #expect(near(place(.boosts, 4, 20.191).dy, pt(44.63 - 37.08)) && near(place(.boosts, 4, 31).dy, pt(20.25 - 37.08)) && near(place(.boosts, 4, 42).dy, 0))
    }

    /// Archive: the lid presses 8.3 units down as the slot sinks and sags 2.5 units, then flies 20 units
    /// up tipping −5.57°; the box jumps 15.8 units after it, and its rim shows from frame 17 to 33.
    @Test func archiveMovesAsArcs() {
        #expect(near(place(.archive, 3, 11).dy, pt(45.44 - 37.15)) && near(place(.archive, 3, 11).turn, 0))
        #expect(near(place(.archive, 3, 22).dy, pt(17.08 - 37.15)) && near(place(.archive, 3, 22).turn, -5.57) && near(place(.archive, 3, 29).turn, 3))
        #expect(near(place(.archive, 0, 11).dy, 0) && near(place(.archive, 0, 21).dy, pt(63.25 - 79.05)) && near(place(.archive, 0, 27).dy, 0))
        let parts = I.parts(.archive)
        #expect(parts[1].parent == 0)
        #expect(near(parts[1].opacity!.value(at: 1), 0.07) && parts[1].opacity!.value(at: 17) == 1 && parts[1].opacity!.value(at: 33) == 1)
        #expect(parts[1].opacity!.value(at: 35) == 0)
        #expect(near(place(.archive, 2, 11).dy, pt(74.04 - 65)))
        func sag(_ frame: Double) -> Double { Double(parts[2].lines(at: frame)!.boundingBoxOfPath.height) }
        #expect(sag(1) == 0 && sag(11) > 0.5 && sag(21) == 0)
    }

    /// The rim under a lifted lid is drawn, and not while the lid is on.
    @Test func theBoxShowsItsRimWhileItsLidIsOff() {
        let lifted = Bitmap()
        I.draw(.archive, frame: 24, in: lifted.ctx, primary: Self.white, secondary: Self.navy)
        let parts = I.parts(.archive)
        let rim = CGPoint(x: 18, y: 15.5).applying(I.transform(of: 1, in: parts, at: 24))
        #expect(lifted.pixel(rim.x, rim.y) == [255, 255, 255, 255])
        // The gap between the lid and the box shows what is under the icon.
        let lidBottom = CGPoint(x: 18, y: 14.0 + 0.875).applying(I.transform(of: 3, in: parts, at: 24))
        #expect(rim.y - lidBottom.y > 1.5)
        #expect(lifted.pixel(18, (rim.y - 0.875 + lidBottom.y) / 2)[3] == 0)
    }

    /// A piece in front leaves a gap in the lines it crosses and none in what fills them: the brush cuts
    /// the tile's outline, and the tile stays filled right up to the brush.
    @Test func aGapIsCutInLinesAndNotInInsides() {
        let b = Bitmap()
        I.draw(.boosts, frame: 1, in: b.ctx, primary: Self.white, secondary: Self.navy)
        var clear = 0, total = 0
        for y in stride(from: 6.0, through: 30, by: 0.25) { for x in stride(from: 6.0, through: 30, by: 0.25) {
            // Inside the tile's silhouette at rest, well away from its edge.
            let p = CGPoint(x: x, y: y).applying(I.transform(of: 0, in: I.parts(.boosts), at: 1).inverted())
            guard CGRect(x: 7.3, y: 7.4, width: 20.6, height: 20.6).insetBy(dx: 2.5, dy: 2.5).contains(p) else { continue }
            total += 1
            if b.pixel(x, y)[3] < 250 { clear += 1 }
        } }
        #expect(total > 500)
        #expect(clear == 0)
    }
}
