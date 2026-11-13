import CoreGraphics
import Foundation

/// The iPhone app's chrome, in points, measured from Arc Search on an iPhone 15 Pro
/// (393 × 852 pt, 2.2545 px per point in the 886 × 1920 recording; docs/ios.md says how).
public enum MobileSearchSheet {
    /// Sheet top to the search field.
    public static let topInset: CGFloat = 16
    public static let fieldHeight: CGFloat = 48
    /// The field's distance from each side of the sheet.
    public static let fieldSideInset: CGFloat = 16
    /// Field bottom to the first suggestion row.
    public static let rowsTopGap: CGFloat = 6
    public static let rowHeight: CGFloat = 56
    /// Arc Search shows four suggestions, and keeps room for them while the field is empty.
    public static let visibleRows = 4
    /// More suggestions wait below the four: scrolling brings them up into the field one by one
    /// (60fps.design's "Arc Search Scroll Morph" clip lists ten).
    public static let listedRows = 10
    /// Last row to the keyboard.
    public static let bottomInset: CGFloat = 8
    /// The sheet's top corners.
    public static let cornerRadius: CGFloat = 38

    /// The sheet's height above the keyboard: 302 pt, whatever is typed.
    public static var height: CGFloat {
        topInset + fieldHeight + rowsTopGap + CGFloat(visibleRows) * rowHeight + bottomInset
    }

    /// Where the sheet's top edge sits in a screen `screenHeight` tall with the keyboard up.
    public static func top(screenHeight: CGFloat, keyboardHeight: CGFloat) -> CGFloat {
        screenHeight - keyboardHeight - height
    }

    /// The sheet with `rows` suggestion rows in view.
    public static func height(rows: Int) -> CGFloat {
        topInset + fieldHeight + rowsTopGap + CGFloat(rows) * rowHeight + bottomInset
    }

    /// How many suggestion rows fit between the keyboard and the top of the screen: four in
    /// portrait, fewer in landscape, where the keyboard leaves little room; the field always stays.
    public static func rowsInView(screenHeight: CGFloat, keyboardHeight: CGFloat, safeTop: CGFloat) -> Int {
        let room = screenHeight - keyboardHeight - safeTop - height(rows: 0)
        guard room > 0 else { return 0 }
        return min(visibleRows, Int(room / rowHeight))
    }

    /// The sheet's top edge with as many rows as fit.
    public static func top(screenHeight: CGFloat, keyboardHeight: CGFloat, safeTop: CGFloat) -> CGFloat {
        screenHeight - keyboardHeight - height(rows: rowsInView(screenHeight: screenHeight, keyboardHeight: keyboardHeight, safeTop: safeTop))
    }
}

/// The bar at the bottom of a page: tabs, the pill that opens search, and the menu.
public enum MobileBottomBar {
    /// The bar above the home indicator's safe area.
    public static let height: CGFloat = 42
    /// The controls' centre below the bar's top edge. They sit low: with a 34 pt safe area the
    /// centre is 44.5 pt above the screen's bottom edge.
    public static let controlsCenterY: CGFloat = 31.5
    public static let pillSize = CGSize(width: 76, height: 39)
    /// The round buttons either side of the pill.
    public static let sideButtonDiameter: CGFloat = 35
    /// A side button's centre from its edge of the screen.
    public static let sideButtonCenterInset: CGFloat = 41

    public struct Frames: Equatable {
        public var bar: CGRect
        public var tabs: CGRect
        public var pill: CGRect
        public var menu: CGRect
    }

    /// The bar and its three controls in a view of `size` whose bottom safe area is `safeBottom`.
    public static func frames(in size: CGSize, safeBottom: CGFloat) -> Frames {
        let barHeight = height + safeBottom
        let bar = CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight)
        let centerY = bar.minY + controlsCenterY
        func circle(_ centerX: CGFloat) -> CGRect {
            CGRect(x: centerX - sideButtonDiameter / 2, y: centerY - sideButtonDiameter / 2,
                   width: sideButtonDiameter, height: sideButtonDiameter)
        }
        let pill = CGRect(x: (size.width - pillSize.width) / 2, y: centerY - pillSize.height / 2,
                          width: pillSize.width, height: pillSize.height)
        return Frames(bar: bar, tabs: circle(sideButtonCenterInset), pill: pill,
                      menu: circle(size.width - sideButtonCenterInset))
    }
}
