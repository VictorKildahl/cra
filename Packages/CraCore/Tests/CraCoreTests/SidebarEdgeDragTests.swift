import CoreGraphics
import CraCore
import Foundation
import Testing

/// A tab held at the sidebar's edge pages to the next or previous space, as Arc's
/// TablistEdgeDragController does (#499).
@Suite struct SidebarEdgeDragTests {
    typealias Edge = SidebarEdgeDrag
    /// A 260 pt sidebar on a window's left, the tab list from y 80 to 700.
    static let sidebar = CGRect(x: 0, y: 80, width: 260, height: 620)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/499"))
    func edges() {
        let s = Self.sidebar
        #expect(Edge.direction(at: CGPoint(x: 259, y: 300), sidebar: s) == .next)
        #expect(Edge.direction(at: CGPoint(x: 280, y: 300), sidebar: s) == .next, "over the page beside the sidebar")
        #expect(Edge.direction(at: CGPoint(x: 2, y: 300), sidebar: s) == .previous)
        #expect(Edge.direction(at: CGPoint(x: -20, y: 300), sidebar: s) == .previous, "past the window's edge")
        #expect(Edge.direction(at: CGPoint(x: 130, y: 300), sidebar: s) == nil, "the list's middle")
        #expect(Edge.direction(at: CGPoint(x: 250, y: 300), sidebar: s) == nil, "a row's trailing end")
        #expect(Edge.direction(at: CGPoint(x: 260 + Edge.outer + 1, y: 300), sidebar: s) == nil, "out on the page, where a split opens")
        #expect(Edge.direction(at: CGPoint(x: 259, y: 40), sidebar: s) == nil, "above the tab list")
        #expect(Edge.direction(at: CGPoint(x: 259, y: 300), sidebar: .zero) == nil)
        // A sidebar on the right pages the same way on screen: its right edge is the window's.
        let right = CGRect(x: 740, y: 80, width: 260, height: 620)
        #expect(Edge.direction(at: CGPoint(x: 735, y: 300), sidebar: right) == .previous)
        #expect(Edge.direction(at: CGPoint(x: 1004, y: 300), sidebar: right) == .next)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/499"))
    func pagesAfterTheDelayAndAgainWhileHeld() {
        var e = Edge()
        #expect(e.update(.next, at: 10) == nil)
        #expect(e.update(.next, at: 10 + Edge.delay - 0.01) == nil)
        #expect(e.update(.next, at: 10 + Edge.delay) == .next)
        #expect(e.update(.next, at: 10 + Edge.delay + 0.1) == nil, "once per wait")
        #expect(e.update(.next, at: 10 + 2 * Edge.delay) == .next, "held on: the space after that")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/499"))
    func leavingTheEdgeStartsOver() {
        var e = Edge()
        _ = e.update(.next, at: 0)
        #expect(e.update(nil, at: 0.3) == nil)
        #expect(e.update(.next, at: 0.6) == nil, "back at the edge: a new wait")
        #expect(e.update(.next, at: 0.6 + Edge.delay) == .next)
        // Crossing to the other edge waits again too.
        #expect(e.update(.previous, at: 2) == nil)
        #expect(e.update(.previous, at: 2 + Edge.delay) == .previous)
    }

    @Test func targetStopsAtTheEnds() {
        #expect(Edge.target(from: 0, count: 3, .next) == 1)
        #expect(Edge.target(from: 2, count: 3, .next) == nil)
        #expect(Edge.target(from: 0, count: 3, .previous) == nil)
        #expect(Edge.target(from: 2, count: 3, .previous) == 1)
        #expect(Edge.target(from: 0, count: 1, .next) == nil)
    }
}
