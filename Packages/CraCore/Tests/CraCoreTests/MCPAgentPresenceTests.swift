import CraCore
import Foundation
import Testing

struct MCPAgentPresenceTests {
    @Test func toastSaysWhatTheAgentDoes() {
        func say(_ tool: String, _ arguments: [String: Any] = [:], target: String? = nil, site: String? = "grindnotes.com") -> String {
            MCPAgentPresence.activity(agent: "Claude Code", tool: tool, arguments: arguments, target: target, site: site)
        }
        #expect(say("page_click", target: "See review") == "Claude Code is clicking “See review”")
        #expect(say("page_click") == "Claude Code is clicking on grindnotes.com")
        #expect(say("page_click", site: nil) == "Claude Code is clicking")
        #expect(say("page_fill", target: "Search") == "Claude Code is typing in “Search”")
        #expect(say("page_type") == "Claude Code is typing on grindnotes.com")
        #expect(say("page_press", ["key": "Enter"]) == "Claude Code is pressing Enter")
        #expect(say("page_press", ["key": "k", "modifiers": "Meta + Shift"]) == "Claude Code is pressing ⇧⌘K")
        #expect(say("page_press", ["key": "Tab", "modifiers": "Control+Alt"]) == "Claude Code is pressing ⌃⌥Tab")
        #expect(say("page_hover") == "Claude Code is moving the pointer on grindnotes.com")
        #expect(say("page_hover", target: "Menu") == "Claude Code is pointing at “Menu”")
        #expect(say("page_scroll") == "Claude Code is scrolling grindnotes.com")
        #expect(say("page_navigate", ["url": "https://www.example.com/a?b"]) == "Claude Code is opening example.com")
        #expect(say("tab_open", ["url": "javascript:alert(1)"]) == "Claude Code is opening a page")
        #expect(say("page_history", ["action": "back"]) == "Claude Code is going back")
        #expect(say("page_history", ["action": "reload"]) == "Claude Code is reloading grindnotes.com")
        // Upload paths are the user's files: never in the toast.
        #expect(say("page_upload", ["paths": ["/Users/me/secret.pdf"]]) == "Claude Code is uploading a file to grindnotes.com")
        #expect(say("something_new") == "Claude Code is using Cra")
    }

    @Test func pageTextIsQuotedOnOneShortLine() {
        func click(_ target: String) -> String {
            MCPAgentPresence.activity(agent: "A", tool: "page_click", arguments: [:], target: target, site: "x.com")
        }
        #expect(click("  Sign\n  in  ") == "A is clicking “Sign in”")
        // Direction overrides can't flip Cra's own words around the page's.
        #expect(click("\u{202E}nimda\u{202C}") == "A is clicking “nimda”")
        let long = click(String(repeating: "word ", count: 20))
        #expect(long.hasSuffix("…”"))
        #expect(long.count <= "A is clicking “”".count + MCPAgentPresence.targetLimit)
        // A name with nothing to show falls back to the site.
        #expect(click(" \n\t ") == "A is clicking on x.com")
        #expect(MCPAgentPresence.activity(agent: "A", tool: "page_press", arguments: ["key": String(repeating: "x", count: 40)], target: nil, site: nil)
                == "A is pressing a key")
    }

    @Test func commandPeriodTakesOver() {
        #expect(MCPAgentPresence.isTakeOverKey(keyCode: 47, characters: ".", command: true, shift: false, option: false, control: false))
        // A layout with "." elsewhere still has ⌘. by the character.
        #expect(MCPAgentPresence.isTakeOverKey(keyCode: 12, characters: ".", command: true, shift: false, option: false, control: false))
        #expect(!MCPAgentPresence.isTakeOverKey(keyCode: 47, characters: ".", command: false, shift: false, option: false, control: false))
        #expect(!MCPAgentPresence.isTakeOverKey(keyCode: 47, characters: ".", command: true, shift: true, option: false, control: false))
        #expect(!MCPAgentPresence.isTakeOverKey(keyCode: 47, characters: ".", command: true, shift: false, option: true, control: false))
        #expect(!MCPAgentPresence.isTakeOverKey(keyCode: 37, characters: "l", command: true, shift: false, option: false, control: false))
    }

    @Test func sites() {
        #expect(MCPAgentPresence.site("https://WWW.Example.com/path") == "example.com")
        #expect(MCPAgentPresence.site("http://localhost:8080/") == "localhost")
        #expect(MCPAgentPresence.site("file:///etc/passwd") == nil)
        #expect(MCPAgentPresence.site("chrome://settings") == nil)
        #expect(MCPAgentPresence.site("not a url") == nil)
    }

    @Test func aWatchedPointerGlidesSlowEnoughToFollow() throws {
        for end in [CGPoint(x: 30, y: 0), CGPoint(x: 400, y: 300), CGPoint(x: 3000, y: 2000)] {
            let glide = MCPAgentPresence.watchedGlide(from: .zero, to: end, variation: 0.3)
            let total = glide.reduce(0) { $0 + $1.delay }
            #expect(total >= 0.29 && total <= 0.61)
            #expect(try #require(glide.last).point == end)
            // Slower than the unwatched path to the same place.
            #expect(total > MCPInputPlan.movement(from: .zero, to: end, variation: 0.3).reduce(0) { $0 + $1.delay })
        }
        // Farther takes longer, up to the cap.
        #expect(MCPAgentPresence.glideDuration(distance: 100) < MCPAgentPresence.glideDuration(distance: 800))
        #expect(MCPAgentPresence.glideDuration(distance: 100_000) == 0.6)
        // Already there: one step, no wait.
        let still = MCPAgentPresence.watchedGlide(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 6, y: 5), variation: 0.5)
        #expect(still.count == 1 && still[0].delay == 0 && still[0].point == CGPoint(x: 6, y: 5))
    }

    @Test func quickStepsDontPileUpInThePill() {
        // Each step's words land before the next slide starts (it outlasts the 0.07 + 0.32 s slide in).
        #expect(MCPAgentPresence.pillHold >= 0.4 && MCPAgentPresence.pillHold <= 1)
        #expect(MCPAgentPresence.pillWait(shownFor: 0.001) > 0.69)
        #expect(MCPAgentPresence.pillWait(shownFor: 0.3) == MCPAgentPresence.pillHold - 0.3)
        #expect(MCPAgentPresence.pillWait(shownFor: 5) == 0)
        #expect(MCPAgentPresence.pillWait(shownFor: -1) == MCPAgentPresence.pillHold)
    }

    @Test func theCursorStaysWhileTheAgentThinks() {
        // Agents take seconds between steps: the cursor lasts as long as the tab's face does.
        #expect(MCPAgentPresence.cursorLingers == MCPAgentPresence.lingers)
        #expect(MCPAgentPresence.cursorLingers >= 8)
        #expect(MCPAgentPresence.revealLimit > 0.5 && MCPAgentPresence.revealLimit < 2)
    }

    @Test func aWatchedPageScrollsOnlyToWhatIsOutOfView() throws {
        let view = CGSize(width: 1000, height: 800)
        // In view: nothing moves.
        #expect(MCPAgentPresence.revealDirection(element: CGRect(x: 100, y: 100, width: 80, height: 30), viewport: view) == nil)
        #expect(MCPAgentPresence.revealDirection(element: CGRect(x: 0, y: 770, width: 1000, height: 30), viewport: view) == nil)
        // A box taller than the view that covers it is in view; one that starts below isn't.
        #expect(MCPAgentPresence.revealDirection(element: CGRect(x: 0, y: -200, width: 500, height: 2000), viewport: view) == nil)
        // Below the fold: the page scrolls down, toward it.
        let below = try #require(MCPAgentPresence.revealDirection(element: CGRect(x: 100, y: 2400, width: 80, height: 30), viewport: view))
        #expect(below.dx == 0 && below.dy > 0)
        // Partly cut off at the top: up.
        let above = try #require(MCPAgentPresence.revealDirection(element: CGRect(x: 100, y: -10, width: 80, height: 30), viewport: view))
        #expect(above.dx == 0 && above.dy < 0)
        // Off to the right and below: both.
        let corner = try #require(MCPAgentPresence.revealDirection(element: CGRect(x: 1400, y: 900, width: 50, height: 20), viewport: view))
        #expect(corner.dx > 0 && corner.dy > 0)
        // Nothing to measure: no scroll.
        #expect(MCPAgentPresence.revealDirection(element: .zero, viewport: view) == nil)
        #expect(MCPAgentPresence.revealDirection(element: CGRect(x: 0, y: 2000, width: 10, height: 10), viewport: .zero) == nil)
    }

    @Test func aWatchedWheelScrollIsPacedToFollow() {
        // Unwatched: at most 8 notches at once, as before.
        func unwatched(_ dx: Int, _ dy: Int) -> [Double] {
            let plan = MCPAgentPresence.wheel(dx: dx, dy: dy, watched: false)
            return [Double(plan.steps), plan.gap]
        }
        #expect(unwatched(0, 12) == [1, 0])
        #expect(unwatched(0, 600) == [8, 0])
        #expect(unwatched(-5000, 0) == [8, 0])
        // Watched: finer notches spread over a quarter to six tenths of a second.
        for (dx, dy) in [(0, 12), (0, 300), (0, -800), (2000, 0), (0, 100_000)] {
            let plan = MCPAgentPresence.wheel(dx: dx, dy: dy, watched: true)
            let total = Double(plan.steps) * plan.gap
            #expect(plan.steps >= 1 && plan.steps <= 16)
            #expect(total >= 0.249 && total <= 0.601)
            #expect(plan.steps >= MCPAgentPresence.wheel(dx: dx, dy: dy, watched: false).steps)
        }
        #expect(MCPAgentPresence.wheel(dx: 0, dy: 600, watched: true).steps == 15)
    }

    @Test func eyesLookWhereTheFaceGoes() {
        let right = MCPAgentPresence.gaze(dx: 50, dy: 0, reach: 2)
        #expect(right.dx == 2 && right.dy == 0)
        let downLeft = MCPAgentPresence.gaze(dx: -30, dy: 40, reach: 2.5)
        #expect(abs(downLeft.dx + 1.5) < 0.0001 && abs(downLeft.dy - 2) < 0.0001)
        #expect(MCPAgentPresence.gaze(dx: 0.1, dy: 0.2, reach: 2) == CGVector(dx: 0, dy: 0))
        #expect(MCPAgentPresence.gaze(dx: 10, dy: 10, reach: 0) == CGVector(dx: 0, dy: 0))
    }
}
