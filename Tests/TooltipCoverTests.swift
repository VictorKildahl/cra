import AppKit

/// A tab's tip shows only while the pointer is on the tab itself, not on a list hung over it (GitHub #770):
/// Library's downloads lie over the tab list in the same window, and the tabs' tracking areas kept seeing the
/// pointer under them. Real views in a window that is never ordered in; hit-testing needs no screen.
@main
enum TooltipCoverTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        aListOverTheTabsHidesThemFromThePointer()
        print("Tooltip cover: \(checks) checks passed")
    }

    // promise: #770
    @MainActor
    private static func aListOverTheTabsHidesThemFromThePointer() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        window.contentView = content
        // The tab list: one row from y 0 to 200 with its title in it, as the sidebar's rows have.
        let list = NSView(frame: content.bounds)
        content.addSubview(list)
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        list.addSubview(row)
        let title = NSView(frame: NSRect(x: 10, y: 10, width: 200, height: 180))
        row.addSubview(title)
        // Library's downloads over the lower half of that row, later in the same window.
        let tray = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        content.addSubview(tray)
        let download = NSView(frame: NSRect(x: 10, y: 10, width: 280, height: 40))
        tray.addSubview(download)

        func screen(_ x: CGFloat, _ y: CGFloat) -> NSPoint { window.convertPoint(toScreen: NSPoint(x: x, y: y)) }
        expect(!row.isUncovered(atScreenPoint: screen(50, 30)), "a tab under a download isn't under the pointer")
        expect(!row.isUncovered(atScreenPoint: screen(50, 80)), "nor under the downloads list's own background")
        expect(row.isUncovered(atScreenPoint: screen(50, 150)), "the tab's title above the list is")
        expect(row.isUncovered(atScreenPoint: screen(250, 195)), "and its edge, past the title")
        expect(download.isUncovered(atScreenPoint: screen(50, 30)), "the download is under the pointer")
        expect(!row.isUncovered(atScreenPoint: screen(50, 300)), "a spot past the tab is not the tab")
        expect(list.isUncovered(atScreenPoint: screen(50, 300)), "the list holding the tabs is uncovered there")
        tray.removeFromSuperview()
        expect(row.isUncovered(atScreenPoint: screen(50, 30)), "with the list gone, the tab is under the pointer again")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
