import AppKit

// Unrelated sidebar/pop-up drawing dependencies. The card, overlay and their controls are production files.
enum SidebarSymbols {
    static func image(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
enum SidebarText { static let inset: CGFloat = 0 }
extension NSTextField {
    static func sidebarLabel(size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: size, weight: weight)
        return field
    }
}
enum ExtensionPopupWindow {
    static func closed(by event: NSEvent?) -> Bool { false }
}

enum CraMetrics { static let findBarSize = NSSize(width: 300, height: 38); static let findBarInset: CGFloat = 10 }
