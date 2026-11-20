import AppKit

/// `cra://debug?dropFile=<path>`: a file from the Finder let go in the middle of the shown page, through the page
/// view's own dragging methods (and Cra's PageDropRouter in front of them), as AppKit calls them for a real drag.
/// Scenarios can't move the pointer; this is the drop a page's drop handler sees (#593: a .crx on
/// chrome://extensions). Debug only.
@MainActor
enum DebugFileDrop {
    static func drop(_ path: String, on container: NSView) {
        guard let page = EmbeddedPages.webContentsView(in: container), let window = page.window else {
            CraLog.note("dropFile: no page view"); return
        }
        let pb = NSPasteboard(name: .init("dk.kildahl.cra.test-drop-file"))
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
        let centre = page.convert(NSPoint(x: page.bounds.midX, y: page.bounds.midY), to: nil)
        let info = Info(pasteboard: pb, location: centre, window: window)
        let entered = page.draggingEntered(info)
        let updated = page.draggingUpdated(info)
        // The renderer answers the drag over in its own time: let it decide before the drop, as a hand would.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let again = page.draggingUpdated(info)
            let prepared = page.prepareForDragOperation(info)
            let performed = prepared && page.performDragOperation(info)
            page.concludeDragOperation(info)
            CraLog.note("dropFile: entered=\(entered.rawValue) updated=\(again.rawValue) performed=\(performed)")
            pb.releaseGlobally()
        }
    }

    private final class Info: NSObject, NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingLocation: NSPoint
        let draggingDestinationWindow: NSWindow?
        init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow) {
            draggingPasteboard = pasteboard
            draggingLocation = location
            draggingDestinationWindow = window
        }
        var draggingSourceOperationMask: NSDragOperation { [.copy, .link, .generic] }
        var draggedImageLocation: NSPoint { draggingLocation }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        let draggingSequenceNumber = 593_000
        func slideDraggedImage(to screenPoint: NSPoint) {}
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                    classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func resetSpringLoading() {}
    }
}
