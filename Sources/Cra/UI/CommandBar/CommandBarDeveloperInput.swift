import AppKit

/// Where the developer bar draws its glyph and address, so the panel Arc's ⌘L opens over the bar types in the same
/// place, glyph and font (#663 follow-up). Points from the panel's left edge.
struct CommandBarDeveloperInput {
    var glyphCenterX: CGFloat
    var textX: CGFloat
    var glyph: NSImage?
    var glyphTint: NSColor?
    /// The card's corner radius: the panel's top corners are the card's.
    var topRadius: CGFloat
}
