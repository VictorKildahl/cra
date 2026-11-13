import AppKit

/// The space's menu tones (CraCore ArcMenuTones), for the + menu and the back and forward list. Kept
/// apart from SidebarCreationMenu.swift so its harness compiles without the theme code.
extension SidebarCreationMenuColors {
    init(_ tones: ArcMenuTones) {
        func ink(_ c: RGB) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
        self.init(fill: ink(tones.fill), hover: ink(tones.hover), separator: ink(tones.separator),
                  shortcut: ink(tones.shortcut), disabled: ink(tones.disabled))
    }
}
