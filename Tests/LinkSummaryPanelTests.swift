import AppKit

/// 5-Second Previews' card window (LinkSummaryPanel) off screen: Arc's loading card, the answer
/// growing in with the card's top edge kept under the link, the small card, closing. The answer
/// growing in used to crash: an NSWindow setFrame override ran on the animator proxy.
@main
enum LinkSummaryPanelTests {
    private static var checks = 0

    static func expect(_ ok: Bool, _ message: String) {
        checks += 1
        if !ok { FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!); exit(1) }
    }

    @MainActor static func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // Borderless and never ordered in: a titled window ordered front is pulled onto the screen.
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let theme = SpaceTheme.presets[0]
        let link = NSRect(x: -9800, y: -9450, width: 240, height: 16)
        let p = LinkSummaryPanel()
        p.anchor = link

        p.cardView.show(.loading, theme: theme)
        p.open(over: parent)
        pump(0.35)
        expect(p.cardFrame.size == NSSize(width: 300, height: 52), "the loading card is Arc's 300 × 52 (got \(p.cardFrame.size))")
        expect(p.cardFrame.maxY == link.minY - 6, "the card hangs 6 pt under the link (got \(link.minY - p.cardFrame.maxY))")
        expect(p.cardFrame.minX == link.minX - 7, "the card starts 7 pt left of the link")
        expect(p.frame.maxY - p.cardFrame.maxY <= 2, "the window doesn't reach over the link (it would take the hover)")
        expect(!p.canBecomeKey && !p.canBecomeMain, "the card never takes focus")
        let top = p.cardFrame.maxY

        var card = LinkSummaryService.Card(title: "T", host: "example.com")
        card.result = LinkSummaryResult(url: "https://example.com/", title: "T", host: "example.com", quickSummary: "A quick summary",
                                        details: [.init(label: "One", icon: "star", info: "The first point")])
        p.cardView.show(.summary(card), theme: theme)
        p.fit()
        pump(0.05)
        card.result?.details.append(.init(label: "Two", icon: "no.such.symbol", info: "A second point long enough to wrap onto another line"))
        card.finished = true
        p.cardView.show(.summary(card), theme: theme)
        p.fit()
        pump(0.5)
        expect(p.cardFrame.height > 52 + 40, "the answer grows the card (got \(p.cardFrame.height))")
        expect(p.cardFrame.maxY == top, "the card grows down: its top edge stays under the link")
        expect(p.cardFrame.width == 300, "the answer card stays 300 pt wide")

        p.closeCard()
        pump(0.4)
        expect(!p.isVisible, "a closed card leaves the screen")

        // No room under the link: the small card goes above it. (A window on no screen keeps its
        // card within 2000 pt of itself.)
        let low = NSRect(x: -9800, y: -11980, width: 240, height: 16)
        p.anchor = low
        p.cardView.show(.link(title: "A page title that is long enough to take two lines in the small card", address: "example.com/page"), theme: theme)
        p.open(over: parent)
        pump(0.35)
        expect(p.cardFrame.minY == low.maxY + 6, "with no room below, the card hangs 6 pt above the link")
        expect(abs(p.cardFrame.height - 86) <= 2, "a two-line small card is Arc's 86 pt (got \(p.cardFrame.height))")
        expect(p.cardFrame.minY - p.frame.minY <= 2, "above its link, the window doesn't reach down over it")
        p.closeCard()
        pump(0.4)
        expect(!p.isVisible, "the small card closes")
        print("Link summary panel: \(checks) checks passed")
    }
}
