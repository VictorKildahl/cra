import AppKit
import SwiftUI

@main
struct FilterListGroupCardTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        // Ask SwiftUI to materialize the accessibility tree for this test process.
        let application = AXUIElementCreateApplication(getpid())
        _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let view = FilterListGroupCard(title: "Cookie notices", selected: 1, total: 2, isExpanded: false) {
            Button("Cookie list") {}
        }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        window.displayIfNeeded()
        func button(named name: String) -> AnyObject? {
            func find(_ element: AnyObject) -> AnyObject? {
                if element.accessibilityRole?() == .button && element.accessibilityLabel?() == name { return element }
                for child in element.accessibilityChildren?() ?? [] {
                    if let match = find(child as AnyObject) { return match }
                }
                return nil
            }
            host.layoutSubtreeIfNeeded()
            return find(host)
        }
        func check(expanded: Bool) {
            guard let header = button(named: "Cookie notices") else { fatalError("Missing group header") }
            let expected = expanded ? "Expanded" : "Collapsed"
            precondition((header as? NSObject)?.value(forKey: "accessibilityValue") as? String == expected + ", 1 of 2 selected")
            precondition((button(named: "Cookie list") != nil) == expanded)
        }
        check(expanded: false)
        precondition(button(named: "Cookie notices")?.accessibilityPerformPress?() == true)
        check(expanded: true)
        precondition(button(named: "Cookie notices")?.accessibilityPerformPress?() == true)
        check(expanded: false)
        print("Filter group disclosure: expand, collapse, rows and selection count passed")
    }
}
