import CoreGraphics
import CraCore
import Testing

/// A press on the Picture in Picture window: click, move or aspect-locked resize (issue #134).
struct PictureInPictureGestureTests {
    /// Arc's 16:9 window, 782×440.
    private let window = CGRect(x: 900, y: 600, width: 782, height: 440)
    private let minSize = CGSize(width: 284, height: 160)
    private let maxSize = CGSize(width: 1382, height: 867)

    /// A press at `x, y` in the window (from its bottom left) dragged by `dx, dy`.
    private func drag(at x: CGFloat, _ y: CGFloat, by dx: CGFloat, _ dy: CGFloat) -> (PictureInPictureGesture.Edge, CGRect?) {
        let start = CGPoint(x: window.minX + x, y: window.minY + y)
        var gesture = PictureInPictureGesture(mouse: start, frame: window)
        return (gesture.edge, gesture.frame(mouse: CGPoint(x: start.x + dx, y: start.y + dy), minSize: minSize, maxSize: maxSize))
    }

    @Test func edgesAndCorners() {
        let size = window.size
        let expected: [(CGFloat, CGFloat, PictureInPictureGesture.Edge)] = [
            (391, 220, .none), (100, 30, .none), (2, 220, .left), (780, 220, .right),
            (391, 438, .top), (391, 2, .bottom), (2, 438, .topLeft), (780, 438, .topRight),
            (2, 2, .bottomLeft), (780, 2, .bottomRight),
            // A corner reaches 16 pt along each edge.
            (12, 438, .topLeft), (2, 428, .topLeft), (770, 2, .bottomRight), (20, 438, .top),
        ]
        for (x, y, edge) in expected {
            #expect(PictureInPictureGesture.edge(at: CGPoint(x: x, y: y), in: size) == edge, "\(x), \(y)")
        }
    }

    /// A click carries a little drift; under 3 pt it moves and resizes nothing, from the middle
    /// or from an edge.
    @Test func aClickThatDriftsMovesNothing() {
        #expect(drag(at: 391, 220, by: 2, -2).1 == nil)
        #expect(drag(at: 780, 2, by: 2, -2).1 == nil)
        #expect(drag(at: 391, 220, by: 3, 0).1 == window.offsetBy(dx: 3, dy: 0))
    }

    /// Past the threshold the press stays a drag, even back near where it started.
    @Test func aDragStaysADrag() {
        let start = CGPoint(x: window.midX, y: window.midY)
        var gesture = PictureInPictureGesture(mouse: start, frame: window)
        #expect(gesture.frame(mouse: CGPoint(x: start.x + 1, y: start.y), minSize: minSize, maxSize: maxSize) == nil)
        #expect(gesture.frame(mouse: CGPoint(x: start.x + 10, y: start.y), minSize: minSize, maxSize: maxSize) != nil)
        #expect(gesture.isDragging)
        #expect(gesture.frame(mouse: CGPoint(x: start.x + 1, y: start.y), minSize: minSize, maxSize: maxSize) == window.offsetBy(dx: 1, dy: 0))
    }

    @Test func theMiddleMovesTheWindow() {
        #expect(drag(at: 391, 220, by: -40, 25).1 == window.offsetBy(dx: -40, dy: 25))
    }

    /// Each edge and corner grows the window toward the pointer and keeps the opposite one put,
    /// so the grabbed edge stays under the pointer.
    @Test func resizeKeepsTheOppositeSideFixed() throws {
        // 16:9, 782 → 960 wide is 540 high.
        let cases: [(CGFloat, CGFloat, CGFloat, CGFloat, (CGRect) -> Bool)] = [
            (780, 220, 178, 0, { $0.minX == window.minX && $0.maxY == window.maxY }),   // right
            (2, 220, -178, 0, { $0.maxX == window.maxX && $0.maxY == window.maxY }),    // left
            (391, 438, 0, 100, { $0.minY == window.minY && $0.minX == window.minX }),   // top
            (391, 2, 0, -100, { $0.maxY == window.maxY && $0.minX == window.minX }),    // bottom
            (780, 438, 178, 100, { $0.minX == window.minX && $0.minY == window.minY }), // top right
            (2, 438, -178, 100, { $0.maxX == window.maxX && $0.minY == window.minY }),  // top left
            (780, 2, 178, -100, { $0.minX == window.minX && $0.maxY == window.maxY }),  // bottom right
            (2, 2, -178, -100, { $0.maxX == window.maxX && $0.maxY == window.maxY }),   // bottom left
        ]
        for (x, y, dx, dy, anchored) in cases {
            let (edge, frame) = drag(at: x, y, by: dx, dy)
            let f = try #require(frame, "\(edge)")
            #expect(f.width == 960 && f.height == 540, "\(edge): \(f)")
            #expect(anchored(f), "\(edge): \(f)")
        }
    }

    @Test func aCornerFollowsTheLongerWay() throws {
        // Mostly down on the bottom-right corner: the height leads.
        let f = try #require(drag(at: 780, 2, by: 10, -100).1)
        #expect(f.height == 540 && f.width == 960)
    }

    @Test func resizeStaysWithinTheLimits() throws {
        let small = try #require(drag(at: 780, 220, by: -700, 0).1)
        #expect(small.width == 284 && small.height == 160)
        let big = try #require(drag(at: 780, 220, by: 2000, 0).1)
        #expect(big.width == 1382 && big.height == 778)
        #expect(big.maxY == window.maxY)
    }
}
