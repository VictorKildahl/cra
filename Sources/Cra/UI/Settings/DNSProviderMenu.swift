import AppKit
import SwiftUI

/// AppKit exposes a tooltip on each open menu item, including the provider's actual DoH endpoint.
struct DNSProviderMenu: NSViewRepresentable {
    @Binding var choice: SecureDNSChoice

    func makeCoordinator() -> Coordinator { Coordinator($choice) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.setAccessibilityLabel("DNS over HTTPS")
        func add(_ title: String, _ value: SecureDNSChoice, _ help: String) {
            button.addItem(withTitle: title)
            button.lastItem?.representedObject = value
            button.lastItem?.toolTip = help
        }
        add("Use System DNS (Default)", .automatic, "Use your current DNS provider over HTTPS when available.")
        add("Off", .off, SecureDNS(mode: "off", templates: "").summary)
        button.menu?.addItem(.separator())
        for provider in SecureDNSProvider.all {
            add(provider.name, .provider(provider),
                provider.template)
        }
        button.menu?.addItem(.separator())
        add("Custom…", .custom, "Enter your provider’s DNS-over-HTTPS URL.")
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectProvider(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $choice
        button.isEnabled = context.environment.isEnabled
        if let item = button.itemArray.first(where: { ($0.representedObject as? SecureDNSChoice) == choice }) {
            button.select(item)
            button.toolTip = item.toolTip
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<SecureDNSChoice>
        init(_ selection: Binding<SecureDNSChoice>) { self.selection = selection }

        @objc func selectProvider(_ sender: NSPopUpButton) {
            if let value = sender.selectedItem?.representedObject as? SecureDNSChoice {
                selection.wrappedValue = value
            }
        }
    }
}
