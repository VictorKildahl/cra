import AppKit

@objc(NativeWidgetMacNSWindow)
private final class ChromiumBubble: NSWindow {}

@main
enum ExtensionPopupCandidateTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let rect = NSRect(x: -10000, y: -10000, width: 39, height: 39)
        func make(_ type: NSWindow.Type = NSWindow.self) -> NSWindow {
            let window = type.init(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            return window
        }
        let owner = make(), host = make(), otherHost = make(), otherOwner = make()
        let bubble = make(ChromiumBubble.self), badge = make(), tooltip = make(ChromiumBubble.self)
        owner.addChildWindow(host, ordered: .above)
        owner.addChildWindow(otherHost, ordered: .above)
        host.addChildWindow(bubble, ordered: .above)
        host.addChildWindow(badge, ordered: .above)
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        func matches(_ candidate: NSWindow, _ expectedOwner: NSWindow? = nil, _ source: NSWindow? = nil) -> Bool {
            ExtensionPopupCandidate.matches(candidate, owner: expectedOwner ?? owner, sourceHost: source,
                                             isPageHost: { $0 === host || $0 === otherHost })
        }
        check(matches(bubble, owner, host), "the source page's minimum-size popup is accepted")
        check(matches(bubble), "shortcut placement accepts the resolved owner's page host")
        check(!matches(badge), "a non-Chromium sharing badge cannot be reparented")
        check(!matches(tooltip), "an unowned Chromium tooltip is rejected")
        check(!matches(bubble, otherOwner), "another browser window cannot own this popup")
        check(!matches(bubble, owner, otherHost), "a different source page cannot claim this popup")
        check(!ExtensionPopupCandidate.matches(bubble, owner: nil, sourceHost: host, isPageHost: { _ in true }),
              "missing browser ownership fails closed")
        check(!ExtensionPopupCandidate.matches(bubble, owner: owner, sourceHost: host, isPageHost: { _ in false }),
              "a non-page parent is rejected")
        bubble.orderOut(nil)
        check(!matches(bubble), "a hidden popup is not ready for placement")
        bubble.orderFront(nil)
        bubble.styleMask.insert(.titled)
        check(!matches(bubble), "a separate titled extension window is not an action bubble")
        bubble.styleMask = .borderless
        owner.orderOut(nil)
        check(!matches(bubble), "a hidden browser cannot acquire a popup")
        for window in [bubble, badge, tooltip, host, otherHost, owner, otherOwner] {
            window.parent?.removeChildWindow(window)
            window.close()
        }
        print("Extension popup native ownership: \(checks) checks passed")
    }
}
