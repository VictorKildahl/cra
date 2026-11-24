import XCTest

final class WindowApplication: XCUIApplication {
    // app.frame is reported portrait-swapped on the open iPhone Duo.
    override var frame: CGRect { windows.firstMatch.frame }

    override func coordinate(withNormalizedOffset offset: CGVector) -> XCUICoordinate {
        windows.firstMatch.coordinate(withNormalizedOffset: offset)
    }
}
