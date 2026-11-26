import AppKit
import SwiftUI
@main struct DNSProviderMenuTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var selected = SecureDNSChoice.automatic
        let menu = DNSProviderMenu(choice: Binding(get: { selected }, set: { selected = $0 }))
        let host = NSHostingView(rootView: menu.disabled(false))
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 320,height: 55), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func popup(_ view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton { return button }
            return view.subviews.lazy.compactMap(popup).first
        }
        let button = popup(host)!
        precondition(button.titleOfSelectedItem == "Use System DNS (Default)")
        precondition(button.isEnabled && button.itemArray.filter { !$0.isSeparatorItem }.count == SecureDNSProvider.all.count + 3)
        for item in button.itemArray where !item.isSeparatorItem {
            let choice = item.representedObject as! SecureDNSChoice
            button.select(item)
            precondition(button.sendAction(button.action!, to: button.target))
            precondition(selected == choice)
            switch choice {
            case .provider(let provider):
                let tip = item.toolTip!
                precondition(tip == provider.template)
                precondition(SecureDNSPrefs(choice)!.choice == choice)
            case .off: precondition(item.toolTip?.contains("plain text") == true)
            default: break
            }
            print("PASS", item.title)
        }
        selected = .off
        host.rootView = menu.disabled(true)
        host.layoutSubtreeIfNeeded()
        guard let locked = popup(host) else { fatalError("Missing managed DNS control") }
        precondition(!locked.isEnabled && locked.titleOfSelectedItem == "Off")
        precondition(locked.toolTip == locked.selectedItem?.toolTip)
    }
}
