import CraCore
import Testing

/// #685: a double click on the toolbar's empty part does what macOS does for a title bar, as the sidebar's top does.
struct TitleBarDoubleClickTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/685"))
    func followsTheSystemSetting() {
        #expect(TitleBarDoubleClick(setting: nil) == .zoom)
        #expect(TitleBarDoubleClick(setting: "Maximize") == .zoom)
        #expect(TitleBarDoubleClick(setting: "Fill") == .zoom)
        #expect(TitleBarDoubleClick(setting: "Minimize") == .minimize)
        #expect(TitleBarDoubleClick(setting: "None") == .nothing)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/685"))
    func onlyTheSecondClickOfADoubleClick() {
        #expect(TitleBarDoubleClick.runs(clickCount: 2, dragged: false))
        #expect(!TitleBarDoubleClick.runs(clickCount: 1, dragged: false), "a single click focuses the pane")
        #expect(!TitleBarDoubleClick.runs(clickCount: 2, dragged: true), "a drag moves the window")
        #expect(!TitleBarDoubleClick.runs(clickCount: 3, dragged: false))
    }
}
