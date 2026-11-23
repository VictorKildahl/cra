import CoreGraphics
import CraCore
import Foundation
import Testing

/// Google Meet's Picture in Picture is a Document Picture in Picture window, Chromium's own. Dragged
/// half past the screen's edge it stayed there, while a video's springs back into a corner (#702).
struct DocumentPictureInPictureDragTests {
    let builtIn = PictureInPictureLayout.Display(id: "BUILTIN", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                                 visible: CGRect(x: 0, y: 0, width: 1728, height: 1084))
    /// Meet's call window as it opens, about 400 × 240 (its own size; Cra doesn't resize it).
    let size = CGSize(width: 400, height: 240)

    func dragged(to origin: CGPoint) -> CGRect? {
        var drag = DocumentPictureInPictureDrag()
        drag.moved(buttonDown: true)
        return drag.released(frame: CGRect(origin: origin, size: size), displays: [builtIn])
    }

    /// Let go half past an edge it slides back the shortest way, 10 pt in from that edge, at its own size
    /// and keeping the other axis: Arc 1.173's Document PiP, a 400 × 240 window dragged by its top bar
    /// half past the left edge at 691 pt from the bottom, came back to x = 10 at the same height (live,
    /// 23 Nov 2026). Wholly on screen it stays.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/702"))
    func draggedPastTheEdgeSlidesBackOnScreen() {
        #expect(dragged(to: CGPoint(x: -200, y: 691)) == CGRect(x: 10, y: 691, width: 400, height: 240))
        #expect(dragged(to: CGPoint(x: 600, y: -120)) == CGRect(x: 600, y: 10, width: 400, height: 240))
        #expect(dragged(to: CGPoint(x: 1528, y: 300)) == CGRect(x: 1728 - 10 - 400, y: 300, width: 400, height: 240))
        // Past a corner, both axes come in.
        #expect(dragged(to: CGPoint(x: -150, y: -100)) == CGRect(x: 10, y: 10, width: 400, height: 240))
        #expect(dragged(to: CGPoint(x: 600, y: 400)) == nil)
        // On screen but under the menu bar: it stays, as a video's does.
        #expect(dragged(to: CGPoint(x: 600, y: 1117 - 240 - 5)) == nil)
    }

    /// Moved without the button held (the site, a window manager, Cra's own slide), it is left where it is.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/702"))
    func onlyAMouseDragSlidesIt() {
        var drag = DocumentPictureInPictureDrag()
        drag.moved(buttonDown: false)
        #expect(drag.released(frame: CGRect(origin: CGPoint(x: -200, y: 100), size: size), displays: [builtIn]) == nil)
        // A drag counts once; the next release without a new drag doesn't spring it again.
        drag.moved(buttonDown: true)
        #expect(drag.released(frame: CGRect(origin: CGPoint(x: -200, y: 100), size: size), displays: [builtIn]) != nil)
        #expect(drag.released(frame: CGRect(origin: CGPoint(x: -200, y: 100), size: size), displays: [builtIn]) == nil)
    }

    /// Chromium's floating top-level window that isn't the video's; not its bubbles, not Cra's windows.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/702"))
    func whichWindowsAreDocumentPictureInPicture() {
        #expect(DocumentPictureInPictureDrag.isDocumentWindow(className: "NativeWidgetMacNSWindow", floating: true, hasParent: false, isVideo: false))
        #expect(!DocumentPictureInPictureDrag.isDocumentWindow(className: "NativeWidgetMacNSWindow", floating: true, hasParent: false, isVideo: true))
        #expect(!DocumentPictureInPictureDrag.isDocumentWindow(className: "NativeWidgetMacNSWindow", floating: true, hasParent: true, isVideo: false))
        #expect(!DocumentPictureInPictureDrag.isDocumentWindow(className: "NativeWidgetMacNSWindow", floating: false, hasParent: false, isVideo: false))
        #expect(!DocumentPictureInPictureDrag.isDocumentWindow(className: "Cra.ExtensionPopupWindow", floating: true, hasParent: false, isVideo: false))
    }
}
