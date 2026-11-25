import AppKit
import SwiftUI

/// The import window's skipped list (SkippedList) laid out off screen. An Arc archive of 10,000 tabs
/// leaves about 8,500 past its 1,500 limit: built all at once they held the main thread for 20 s
/// when the archive tile was clicked; built as they scroll in, the list opens in well under a second.
@main
enum SkippedListTests {
    private static var checks = 0

    static func expect(_ ok: Bool, _ message: String) {
        checks += 1
        if !ok { FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!); exit(1) }
    }

    /// The list for `count` archived tabs left out, laid out as the popover lays it out; how long that
    /// took and the list's scroll view.
    @MainActor static func layOut(_ count: Int) -> (seconds: Double, scroll: NSScrollView?) {
        let skips = (0..<count).map {
            ImportSkip(title: "Old \($0)", url: "https://example.com/old/\($0)", reason: .olderArchive(limit: 1500), kind: .archive)
        }
        let host = NSHostingView(rootView: SkippedList(report: ImportReport(.archive, copied: 1500, skipped: skips), c: ImportColors(dark: false)))
        // Borderless and never ordered in, as a popover's content is laid out before it shows.
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 340, height: 600), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let start = Date()
        // The rows' height reaches the frame on the pass after it is measured.
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        _ = host.fittingSize
        func scrolls(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrolls) }
        return (Date().timeIntervalSince(start), scrolls(host).first)
    }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        _ = layOut(1)  // SwiftUI's first layout loads its fonts

        for count in [1, 3] {
            let scroll = layOut(count).scroll
            let content = scroll?.documentView?.frame.height ?? 0
            expect(content > 0 && scroll?.frame.height == content && content < 280,
                   "\(count) row(s): the list is as tall as its rows (got \(scroll?.frame.height ?? -1) for \(content))")
        }

        let long = layOut(8500)
        expect(long.seconds < 2, "8,500 rows lay out in under 2 s, built as they scroll in (took \(String(format: "%.1f", long.seconds)) s)")
        expect(long.scroll?.frame.height == 280, "a long list stops at 280 pt (got \(long.scroll?.frame.height ?? -1))")
        expect((long.scroll?.documentView?.frame.height ?? 0) > 280, "and scrolls")

        print("Skipped list: \(checks) checks passed")
    }
}
