import AppKit
import ObjectiveC

/// Chromium shows download progress on the Dock tile (chrome/browser/ui/cocoa/dock_icon.mm): the
/// first download makes its DockTileView the tile's content view for the rest of the session,
/// and that view draws `+[NSImage imageNamed:NSImageNameApplicationIcon]`, the bundle's icon,
/// under its badge. The ⌘-Tab switcher shows the tile too, so from the first download on it
/// showed Segments instead of the icon picked in Settings (GitHub #319), until picking the
/// icon again put AppKit's own image view back (and lost Chromium's badge). While that view
/// draws, the application icon it asks for is the running app's, the picked one; the badge
/// stays Chromium's.
enum ChromiumDockTile {
    /// Set on the main thread only, around DockTileView's drawRect:.
    nonisolated(unsafe) private static var drawingTile = false

    private typealias DrawIMP = @convention(c) (AnyObject, Selector, NSRect) -> Void
    private typealias NamedIMP = @convention(c) (AnyObject, Selector, NSString?) -> AnyObject?

    /// Chromium's download view, which a picked icon must not take off the tile.
    @MainActor static func isChromiumView(_ view: NSView) -> Bool {
        NSClassFromString("DockTileView").map { view.isKind(of: $0) } ?? false
    }

    /// After Chromium is loaded (DockTileView is in its framework).
    static func install() {
        guard let view = NSClassFromString("DockTileView"),
              let draw = class_getInstanceMethod(view, #selector(NSView.draw(_:))), let drawTypes = method_getTypeEncoding(draw),
              let named = class_getClassMethod(NSImage.self, NSSelectorFromString("imageNamed:")) else {
            CraLog.note("dock tile: Chromium's DockTileView not found, the picked icon isn't drawn under its download badge")
            return
        }
        let namedSel = method_getName(named)
        let originalNamed = unsafeBitCast(method_getImplementation(named), to: NamedIMP.self)
        let namedBlock: @convention(block) (AnyObject, NSString?) -> AnyObject? = { cls, name in
            // NSApp.applicationIconImage no longer says what was picked once another view is on
            // the tile, so the picked icon comes from AppIconManager (nil for Segments).
            if Thread.isMainThread, drawingTile, name as String? == NSImage.applicationIconName,
               let picked = MainActor.assumeIsolated({ AppIconManager.shared.dockImage }) {
                return picked
            }
            return originalNamed(cls, namedSel, name)
        }
        method_setImplementation(named, imp_implementationWithBlock(namedBlock))

        let drawSel = method_getName(draw)
        let originalDraw = unsafeBitCast(method_getImplementation(draw), to: DrawIMP.self)
        let drawBlock: @convention(block) (AnyObject, NSRect) -> Void = { obj, rect in
            drawingTile = true
            defer { drawingTile = false }
            originalDraw(obj, drawSel, rect)
        }
        // Add on DockTileView when it only inherits drawRect:, else replace its own.
        let imp = imp_implementationWithBlock(drawBlock)
        if !class_addMethod(view, drawSel, imp, drawTypes) { method_setImplementation(draw, imp) }
    }
}
