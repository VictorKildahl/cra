import CoreGraphics
import CraCore
import Foundation
import Testing

/// A sidebar tab or a link dragged over the panes proposes a split where it would land (#419),
/// as Arc 1.173.1 does for tabs (measured with real drags).
@Suite struct SplitDropProposalTests {
    typealias Insert = SplitDropProposal.Insert
    typealias Target = SplitDropProposal.Target
    static let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    static let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    static let lone: [UUID: CGRect] = [a: area]
    /// Two panes side by side with the 10 pt gap between them.
    static let pair: [UUID: CGRect] = [a: CGRect(x: 0, y: 0, width: 495, height: 600), b: CGRect(x: 505, y: 0, width: 495, height: 600)]
    static let four: [UUID: CGRect] = [a: CGRect(x: 0, y: 0, width: 242, height: 600), b: CGRect(x: 252, y: 0, width: 242, height: 600),
                                       c: CGRect(x: 504, y: 0, width: 242, height: 600), d: CGRect(x: 756, y: 0, width: 244, height: 600)]
    static let stacked: [UUID: CGRect] = [a: CGRect(x: 0, y: 305, width: 1000, height: 295), b: CGRect(x: 0, y: 0, width: 1000, height: 295)]

    static func h(_ i: Int) -> Target { .insert(Insert(index: i, orientation: .horizontal)) }
    static func v(_ i: Int) -> Target { .insert(Insert(index: i, orientation: .vertical)) }
    static func r(_ i: Int) -> Target { .replace(index: i) }

    struct Case: Sendable {
        var name: String
        var point: CGPoint
        var ids: [UUID]
        var frames: [UUID: CGRect]
        var orientation: SplitOrientation = .horizontal
        var region: CGRect? = nil
        var current: Target? = nil
        var sidebarSide = true
        var link = false
        var expected: Target?
    }

    static let cases: [Case] = [
        // A lone page: the nearest edge opens the region on that side (y grows upward).
        .init(name: "left edge", point: CGPoint(x: 60, y: 300), ids: [a], frames: lone, expected: h(0)),
        .init(name: "right edge", point: CGPoint(x: 985, y: 300), ids: [a], frames: lone, expected: h(1)),
        .init(name: "top edge", point: CGPoint(x: 500, y: 590), ids: [a], frames: lone, expected: v(0)),
        .init(name: "bottom edge", point: CGPoint(x: 500, y: 10), ids: [a], frames: lone, expected: v(1)),
        .init(name: "right of middle", point: CGPoint(x: 700, y: 300), ids: [a], frames: lone, expected: h(1)),
        // Next to the sidebar the drag is still the sidebar's: Arc shows nothing over the first 25 pt.
        .init(name: "by the sidebar", point: CGPoint(x: 20, y: 300), ids: [a], frames: lone, expected: nil),
        .init(name: "past the band", point: CGPoint(x: 45, y: 300), ids: [a], frames: lone, expected: h(0)),
        .init(name: "no sidebar there", point: CGPoint(x: 20, y: 300), ids: [a], frames: lone, sidebarSide: false, expected: h(0)),
        // The open region keeps the drag while the pointer is on it, even past the page's middle.
        .init(name: "stays on the region", point: CGPoint(x: 400, y: 300), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 495, height: 600), current: h(0), expected: h(0)),
        .init(name: "region's gap edge", point: CGPoint(x: 498, y: 300), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 495, height: 600), current: h(0), expected: h(0)),
        .init(name: "leaves the region", point: CGPoint(x: 980, y: 300), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 495, height: 600), current: h(0), expected: h(1)),
        // A drag from the sidebar crosses the middle, where the bottom is nearest, on its way to the
        // right edge: the bottom region it opened reaches the middle line, so the far right edge at
        // mid-height was still "on the region" and the drop stacked (0.1.43 release clip). Reaching
        // another edge's band, a fifth of the page, wins over the region; elsewhere it still holds.
        .init(name: "right edge over the bottom region", point: CGPoint(x: 975, y: 290), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 1000, height: 295), current: v(1), expected: h(1)),
        .init(name: "bottom region's own edge", point: CGPoint(x: 150, y: 50), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 1000, height: 295), current: v(1), expected: v(1)),
        .init(name: "middle of the bottom region", point: CGPoint(x: 500, y: 250), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 1000, height: 295), current: v(1), expected: v(1)),
        .init(name: "top edge over the left region", point: CGPoint(x: 300, y: 590), ids: [a], frames: lone,
              region: CGRect(x: 0, y: 0, width: 495, height: 600), current: h(0), expected: v(0)),
        // In a split a pane's sides, a fifth of it each, open the region before or after it, and so
        // does the gap; the rest of it, top and bottom too, is replaced.
        .init(name: "first pane's left side", point: CGPoint(x: 60, y: 300), ids: [a, b], frames: pair, expected: h(0)),
        .init(name: "first pane's right side", point: CGPoint(x: 475, y: 300), ids: [a, b], frames: pair, expected: h(1)),
        .init(name: "the gap", point: CGPoint(x: 500, y: 300), ids: [a, b], frames: pair, expected: h(1)),
        .init(name: "second pane's left side", point: CGPoint(x: 525, y: 300), ids: [a, b], frames: pair, expected: h(1)),
        .init(name: "second pane's right side", point: CGPoint(x: 975, y: 300), ids: [a, b], frames: pair, expected: h(2)),
        .init(name: "second pane's middle", point: CGPoint(x: 750, y: 300), ids: [a, b], frames: pair, expected: r(1)),
        .init(name: "a quarter in", point: CGPoint(x: 505 + 124, y: 300), ids: [a, b], frames: pair, expected: r(1)),
        .init(name: "split keeps its direction", point: CGPoint(x: 750, y: 590), ids: [a, b], frames: pair, expected: r(1)),
        .init(name: "first pane's top", point: CGPoint(x: 250, y: 575), ids: [a, b], frames: pair, expected: r(0)),
        .init(name: "stacked, top pane's top", point: CGPoint(x: 500, y: 580), ids: [a, b], frames: stacked, orientation: .vertical, expected: v(0)),
        .init(name: "stacked, bottom pane's bottom", point: CGPoint(x: 500, y: 20), ids: [a, b], frames: stacked, orientation: .vertical, expected: v(2)),
        .init(name: "stacked, a pane's left", point: CGPoint(x: 20, y: 150), ids: [a, b], frames: stacked, orientation: .vertical,
              sidebarSide: false, expected: r(1)),
        // The region keeps the drag in a split too, until the pointer leaves it.
        .init(name: "split region holds", point: CGPoint(x: 400, y: 300), ids: [a, b], frames: pair,
              region: CGRect(x: 330, y: 0, width: 330, height: 600), current: h(1), expected: h(1)),
        // Four panes is Arc's most: no region, but a pane can still be replaced.
        .init(name: "full split's side", point: CGPoint(x: 990, y: 300), ids: [a, b, c, d], frames: four, expected: nil),
        .init(name: "full split's middle", point: CGPoint(x: 875, y: 300), ids: [a, b, c, d], frames: four, expected: r(3)),
        // A link: only a pane's edges, never its middle, so the page keeps drops into its fields.
        .init(name: "link at a lone page's edge", point: CGPoint(x: 950, y: 300), ids: [a], frames: lone, link: true, expected: h(1)),
        .init(name: "link at a lone page's top", point: CGPoint(x: 500, y: 560), ids: [a], frames: lone, link: true, expected: v(0)),
        .init(name: "link inside a lone page", point: CGPoint(x: 700, y: 300), ids: [a], frames: lone, link: true, expected: nil),
        .init(name: "link at a pane's side", point: CGPoint(x: 545, y: 300), ids: [a, b], frames: pair, link: true, expected: h(1)),
        .init(name: "link past the band", point: CGPoint(x: 580, y: 300), ids: [a, b], frames: pair, link: true, expected: nil),
        .init(name: "link on a pane's middle", point: CGPoint(x: 750, y: 300), ids: [a, b], frames: pair, link: true, expected: nil),
        .init(name: "outside the panes", point: CGPoint(x: 1200, y: 300), ids: [a], frames: lone, expected: nil),
        .init(name: "no panes", point: CGPoint(x: 500, y: 300), ids: [], frames: [:], expected: nil),
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/419"), arguments: cases.indices)
    func whereADropGoes(_ i: Int) {
        let t = Self.cases[i]
        let got = SplitDropProposal.propose(at: t.point, ids: t.ids, frames: t.frames, orientation: t.orientation, area: Self.area,
                                            region: t.region, current: t.current, sidebarSide: t.sidebarSide, link: t.link)
        #expect(got == t.expected, "\(t.name)")
    }

    /// The region takes an even share and the others keep their proportions in the rest, so the
    /// split looks after the drop as the region showed it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/419"))
    func regionTakesAnEvenShare() {
        let r = UUID()
        let lone = SplitDropProposal.panes([.init(id: Self.a, factor: 1)], inserting: r, at: Insert(index: 0, orientation: .horizontal))
        #expect(lone.map(\.id) == [r, Self.a])
        #expect(lone.map(\.factor) == [0.5, 0.5])
        let pair = SplitDropProposal.panes([.init(id: Self.a, factor: 0.25), .init(id: Self.b, factor: 0.75)], inserting: r, at: Insert(index: 1, orientation: .horizontal))
        #expect(pair.map(\.id) == [Self.a, r, Self.b])
        #expect(pair.map { ($0.factor * 1000).rounded() } == [167, 333, 500])
        let past = SplitDropProposal.panes([.init(id: Self.a, factor: 1)], inserting: r, at: Insert(index: 7, orientation: .horizontal))
        #expect(past.map(\.id) == [Self.a, r])
    }
}
