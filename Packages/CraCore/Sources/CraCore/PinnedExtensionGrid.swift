import CoreGraphics

/// Where pinned extensions go while the toolbar is hidden: Arc 1.171 takes them out of the URL
/// field (which keeps only Copy Link and Site Control Center on hover) and puts them in a grid
/// of their own over the favorites, the first section of `sidebarFavoritesCollectionView`, shown
/// all the time. Measured live on 4 Nov (AX frames, 11 pins at sidebar widths 200–347): cells
/// 28 pt tall, 8 pt apart both ways, spread over the grid's width (the sidebar less 8 pt each
/// side); like the favorites, as many columns as keep a cell at least `minCellWidth` wide, then
/// the fewest that need no more rows: 11 go 4 + 4 + 3 at 200 pt and 6 + 5 from 240 pt, 7 take
/// one row at 300 pt, 5 one row at 200 pt. The favorites start 8 pt under the last row.
public struct PinnedExtensionGrid: Equatable {
    public static let cellHeight: CGFloat = 28
    public static let gap: CGFloat = 8
    public static let minCellWidth: CGFloat = 28

    /// A pin's button in the URL field.
    public static let fieldButtonWidth: CGFloat = 28
    /// What the URL field keeps for the address and its Copy Link and Site Control Center buttons
    /// (Arc: in the field with 124 pt left, 4 pins at 252 pt; in the grid with 117, 4 at 245).
    public static let fieldReserve: CGFloat = 120

    /// Whether `count` pins go in the URL field `fieldWidth` wide (shown on hover, as before)
    /// rather than in the grid: they do while they leave the address its room.
    public static func fitsInURLField(count: Int, fieldWidth: CGFloat) -> Bool {
        fieldWidth - CGFloat(count) * fieldButtonWidth >= fieldReserve
    }

    public let count: Int
    public let width: CGFloat

    public init(count: Int, width: CGFloat) {
        self.count = count
        self.width = width
    }

    public var columns: Int {
        // n cells of at least minCellWidth with n − 1 gaps.
        let widest = max(1, Int((width + Self.gap) / (Self.minCellWidth + Self.gap)))
        guard count > 0 else { return widest }
        let rows = (count + widest - 1) / widest
        return (count + rows - 1) / rows
    }

    public var rows: Int { (count + columns - 1) / columns }

    public var cellWidth: CGFloat { (width - CGFloat(columns - 1) * Self.gap) / CGFloat(columns) }

    /// The grid's height, 0 with nothing pinned.
    public var height: CGFloat {
        rows == 0 ? 0 : CGFloat(rows) * Self.cellHeight + CGFloat(rows - 1) * Self.gap
    }

    /// How far the favorites sit below the grid's top: its height and the 8 pt under it, or
    /// nothing with nothing pinned.
    public var favoritesOffset: CGFloat { count == 0 ? 0 : height + Self.gap }

    public func frame(at index: Int) -> CGRect {
        let n = columns, cw = cellWidth
        let r = index / n, c = index % n
        return CGRect(x: CGFloat(c) * (cw + Self.gap), y: CGFloat(r) * (Self.cellHeight + Self.gap), width: cw, height: Self.cellHeight)
    }
}
