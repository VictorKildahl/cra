import CoreGraphics
import Foundation

/// The sheet behind the bar's up arrow (Arc Search calls it Tab Controls): an address capsule,
/// a row of square tiles, a group of rows, and a "Problems?" footer. Measured from Arc Search on
/// an iPhone 15 Pro (393 × 852 pt, screenshots at 3 px per point).
public enum MobilePageMenu {
    public enum Tile: String, CaseIterable {
        case reader, summarize, copyLink, share

        public var label: String {
            switch self {
            case .reader: return "Reader"
            case .summarize: return "Summarize"
            case .copyLink: return "Copy Link"
            case .share: return "Share"
            }
        }
    }

    public enum Row: String, CaseIterable {
        case findOnPage, pageZoom, requestDesktopSite, translate, siteSettings

        public var label: String {
            switch self {
            case .findOnPage: return "Find on Page"
            case .pageZoom: return "Page Zoom"
            case .requestDesktopSite: return "Request Desktop Site"
            case .translate: return "Translate"
            case .siteSettings: return "Site Settings"
            }
        }
    }

    /// The tiles on offer. Summarize needs the device's own model, and leaves when there is none.
    public static func tiles(canSummarize: Bool) -> [Tile] {
        Tile.allCases.filter { $0 != .summarize || canSummarize }
    }

    /// Arc Search's rows in its order. "Gift Arc", its referral row, has no counterpart.
    public static let rows = Row.allCases

    /// Sheet top to the address capsule, and the capsule's and rows' distance from each side.
    public static let inset: CGFloat = 16.3
    public static let capsuleHeight: CGFloat = 48
    /// Capsule to tiles.
    public static let tilesGap: CGFloat = 16.7
    public static let tileSize = CGSize(width: 68.3, height: 77.3)
    /// The outer tiles' distance from the sides, with four tiles.
    public static let tileSideInset: CGFloat = 21.3
    public static let tileCornerRadius: CGFloat = 22
    /// A tile's label is centred this far under it.
    public static let tileLabelDrop: CGFloat = 17.3
    /// Tiles to the first row.
    public static let rowsGap: CGFloat = 38.7
    public static let rowHeight: CGFloat = 48
    public static let rowCornerRadius: CGFloat = 12
    /// Last row to the footer's centre, and the footer's centre to the bottom safe area.
    public static let footerDrop: CGFloat = 28.5
    public static let footerRise: CGFloat = 19.5
    public static let cornerRadius: CGFloat = 38

    /// The sheet's height with `rows` rows over a bottom safe area of `safeBottom`.
    public static func height(rows: Int = MobilePageMenu.rows.count, safeBottom: CGFloat) -> CGFloat {
        inset + capsuleHeight + tilesGap + tileSize.height + rowsGap + CGFloat(rows) * rowHeight + footerDrop + footerRise + safeBottom
    }

    /// Where the tiles go in a sheet `width` wide: evenly spread between the side insets.
    public static func tileFrames(count: Int, width: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let top = inset + capsuleHeight + tilesGap
        guard count > 1 else { return [CGRect(x: (width - tileSize.width) / 2, y: top, width: tileSize.width, height: tileSize.height)] }
        let span = width - 2 * tileSideInset - tileSize.width
        // Fewer than four keep the four-tile spacing and stay centred.
        let step = min(span / 3, span / CGFloat(count - 1))
        let start = (width - (step * CGFloat(count - 1) + tileSize.width)) / 2
        return (0..<count).map { CGRect(x: start + CGFloat($0) * step, y: top, width: tileSize.width, height: tileSize.height) }
    }

    /// Page zoom steps: a tenth at a time, half to triple size.
    public static func zoom(_ current: Double, stepping up: Bool) -> Double {
        let next = (current * 10).rounded() / 10 + (up ? 0.1 : -0.1)
        return min(3, max(0.5, (next * 10).rounded() / 10))
    }

    /// "110%" beside the stepper once the page is not at its own size.
    public static func zoomLabel(_ zoom: Double) -> String? {
        let percent = Int((zoom * 100).rounded())
        return percent == 100 ? nil : "\(percent)%"
    }

    /// The footer's count of what the blockers stopped on this page.
    public static func blockedLabel(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "Scrubbed 1 ad or tracker" : "Scrubbed \(count) ads and trackers"
    }
}
