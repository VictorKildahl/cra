import XCTest

/// Pull to refresh. The simulator plays no haptics, so `-CraCountHaptics YES` keeps a running
/// total in the hidden `haptic-count` element (PressHaptics), and `-CraTracePull YES` keeps the
/// last pull's distance, band height and page top in `pull-trace` after the page springs back.
/// The exact sequence of detents is pinned by CraCore's MobilePullHapticsTests; here the page's
/// wiring is: a short pull is silent, and one past the line ticks, moves the page and grows the
/// band behind it.
final class PullHapticsTests: BrowserTestCase {
    /// A page taller than the screen, so a downward drag at the top has a page to move.
    private static let tall = BrowserTestCase.page("Tall")
        + String(repeating: "<p/style=font-family:-apple-system;font-size:20px;margin:24px>Row</p>", count: 40)

    func testAShortPullIsSilentAndOnePastTheLineTicksAndMovesThePage() {
        launch(["-CraOpenURL", Self.tall, "-CraSearch", "NO", "-CraCountHaptics", "YES", "-CraTracePull", "YES"])
        waitForPage("Tall")
        let counter = app.descendants(matching: .any)["haptic-count"]
        let trace = app.descendants(matching: .any)["pull-trace"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertTrue(trace.waitForExistence(timeout: 5))

        let top = app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        func pull(_ points: CGFloat) {
            top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: points)),
                      withVelocity: .slow, thenHoldForDuration: 0.3)
            sleep(1)
        }
        func ticks() -> Int {
            Int(counter.value as? String ?? "") ?? 0
        }
        /// "pull N band N page N" as the test's trace wrote it.
        func traced() -> [Int] {
            (trace.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
        }

        // Nowhere near the 24 pt where the ticks begin.
        pull(20)
        XCTAssertEqual(ticks(), 0, "a short pull is silent")

        // Well past the 128 pt line: the detents play, then the reload's own tick as the finger lifts.
        pull(300)
        XCTAssertGreaterThan(ticks(), 0, "a pull past the line ticks (trace \(trace.value ?? "nil"))")

        let seen = traced()
        XCTAssertEqual(seen.count, 3)
        guard seen.count == 3 else { return }
        XCTAssertGreaterThanOrEqual(seen[0], 128, "the page was pulled past the line")
        XCTAssertGreaterThan(seen[2], 0, "the page moved down")
        XCTAssertLessThanOrEqual(abs(seen[1] - seen[2]), 1, "the band's bottom meets the page's top")
        keep("pulled past the line")
    }
}
