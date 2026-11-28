import CraCEF
import Foundation

extension CraBrowser {
    /// View ▸ Zoom In or Zoom Out (⌘+ ⌘−), as Arc does it: Chrome's next preset step (PageZoomSteps: 100 → 110 →
    /// 125 %), and what Arc's toast then says ("125%"), also at the last step, where the zoom stays (#856). An
    /// Easel zooms its canvas by its own steps and shows no toast (nil).
    func zoomStep(in zoomIn: Bool) -> String? {
        if self is EaselBrowser {
            setZoomLevel(zoomLevel() + (zoomIn ? 0.5 : -0.5))
            return nil
        }
        let level = PageZoomSteps.next(from: zoomLevel(), zoomIn: zoomIn) ?? zoomLevel()
        setZoomLevel(level)
        return PageZoomSteps.label(level: level)
    }

    /// Zoom to Actual Size with what Arc's toast says ("100%"); nil for an Easel.
    func resetZoomShowing() -> String? {
        resetZoom()
        return self is EaselBrowser ? nil : PageZoomSteps.label(level: 0)
    }

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
