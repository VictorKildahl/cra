import AppKit

/// Geometry captured at presentation, after Chromium has finished creating the popup.
/// The owner keeps a popup tied to the browser window, including a floating sidebar.
@MainActor
struct ExtensionPopupAnchor {
    let point: NSPoint
    weak var owner: NSWindow?
}

enum ExtensionPopupGeometry {
    /// Keep the right edge under its button as the extension grows. At display edges,
    /// visibility takes precedence; an oversized popup keeps its top-left reachable.
    static func frame(size: NSSize, anchor: NSPoint, offset: NSPoint = .zero, visibleFrame: NSRect?) -> NSRect {
        let size = NSSize(width: max(1, size.width), height: max(1, size.height))
        var topLeft = NSPoint(x: anchor.x - size.width + offset.x, y: anchor.y + offset.y)
        if let screen = visibleFrame {
            let minX = screen.minX + 4
            let maxX = max(minX, screen.maxX - size.width - 4)
            let maxY = screen.maxY
            let minY = min(maxY, screen.minY + size.height + 4)
            topLeft.x = min(max(topLeft.x, minX), maxX)
            topLeft.y = min(max(topLeft.y, minY), maxY)
        }
        return NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }
}
