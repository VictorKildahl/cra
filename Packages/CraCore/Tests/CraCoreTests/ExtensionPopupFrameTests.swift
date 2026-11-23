import CraCore
import Testing

/// An extension popup's page inside Cra's frame window (GitHub #701).
struct ExtensionPopupFrameTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/701"))
    func thePageSitsInsideTheWindowsBorderAndCorners() {
        // macOS 26 rounds a titled window's corners by 16 pt: the page, 1 pt in, by 15.
        #expect(ExtensionPopupFrame.border == 1)
        #expect(ExtensionPopupFrame.pageCornerRadius(windowRadius: 16) == 15)
        #expect(ExtensionPopupFrame.pageCornerRadius(windowRadius: 0) == 0)
    }
}
