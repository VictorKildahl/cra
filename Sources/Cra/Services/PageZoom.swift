import CraCEF
import Foundation

extension CraBrowser {
    /// View ▸ Zoom to Actual Size (⌘0), as Chrome's reset does it (zoom::PageZoom::Zoom with PAGE_ZOOM_RESET): the
    /// zoom level back to 100 % and a trackpad pinch undone, so the page is at its actual size whichever way it was
    /// magnified. Setting only the zoom level left a pinched page magnified (GitHub #825). A WebKit page answers
    /// the reset with its magnification; an Easel has no pinch to undo.
    func resetZoom() {
        setZoomLevel(0)
        // Straight to the page's scale, as Chrome's WebContents::SetPageScale(1) does. Emulation.resetPageScaleFactor
        // only marks the scale for a reset at the next viewport change, which a desktop page doesn't get.
        sendDevToolsMethod("Emulation.setPageScaleFactor", params: #"{"pageScaleFactor":1}"#) { _, _ in }
    }
}
