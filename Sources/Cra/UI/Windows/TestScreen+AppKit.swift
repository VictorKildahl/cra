import AppKit

/// CRA_TEST_SCREEN's AppKit side (the rule is CraCore's `TestScreen`): the display a test
/// instance's windows open on, read from the environment once.
extension TestScreen {
    /// The display CRA_TEST_SCREEN names, nil when it is unset or names no connected display.
    @MainActor static var screen: NSScreen? {
        let screens = NSScreen.screens
        return pick(ProcessInfo.processInfo.environment[environmentKey], among: screens.map(\.testDisplay)).map { screens[$0] }
    }

    /// `frame` moved onto the test display, or unchanged without one.
    @MainActor static func place(_ frame: NSRect) -> NSRect {
        guard let screen else { return frame }
        return place(frame, on: screen.testDisplay, among: NSScreen.screens.map(\.testDisplay))
    }
}

extension NSScreen {
    var testDisplay: TestScreen.Display { .init(name: localizedName, frame: frame, visibleFrame: visibleFrame) }
}

extension NSWindow {
    /// center(), on the CRA_TEST_SCREEN display when there is one.
    @MainActor func centerOnTestScreen() {
        guard let screen = TestScreen.screen else { return center() }
        setFrame(TestScreen.centre(frame.size, on: screen.testDisplay), display: false)
    }
}
