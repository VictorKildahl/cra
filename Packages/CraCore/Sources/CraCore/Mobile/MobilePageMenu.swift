import CoreGraphics
import Foundation

/// The sheet behind the bar's up arrow (Arc Search calls it Tab Controls), in Arc Search 1.49's
/// design as Victor's recording shows it (13 Nov 2026, iPhone 16 Pro Max, 440 × 956 pt at 3 px per
/// point): an address capsule (back, forward, the page, copy link, reload), four tiles (Find on
/// Page, Summarize, Pin, Share), "Display Options" that opens in place to Translate, Reader Mode,
/// Page Zoom and Request Desktop Site, "Site Settings", and a footer card that counts what was
/// scrubbed and restores the page without blockers.
public enum MobilePageMenu {
    public enum Tile: String, CaseIterable {
        case findOnPage, summarize, pin, share

        public var label: String {
            switch self {
            case .findOnPage: return "Find on Page"
            case .summarize: return "Summarize"
            case .pin: return "Pin"
            case .share: return "Share"
            }
        }
    }

    public enum Row: String, CaseIterable {
        case displayOptions, translate, readerMode, pageZoom, requestDesktopSite, siteSettings

        public var label: String {
            switch self {
            case .displayOptions: return "Display Options"
            case .translate: return "Translate"
            case .readerMode: return "Reader Mode"
            case .pageZoom: return "Page Zoom"
            case .requestDesktopSite: return "Request Desktop Site"
            case .siteSettings: return "Site Settings"
            }
        }
    }

    /// What "Display Options" opens to, in its order.
    public static let displayOptions: [Row] = [.translate, .readerMode, .pageZoom, .requestDesktopSite]

    /// The tiles on offer. Summarize needs the device's own model, and leaves when there is none.
    public static func tiles(canSummarize: Bool) -> [Tile] {
        Tile.allCases.filter { $0 != .summarize || canSummarize }
    }

    /// Sheet top to the address capsule, and the capsule's and rows' distance from each side.
    public static let inset: CGFloat = 16.3
    public static let capsuleHeight: CGFloat = 47.3
    /// Capsule to tiles.
    public static let tilesGap: CGFloat = 17.3
    /// Four tiles fill the width: 18.33 pt in from each side, 20.33 pt apart (85.6 pt wide on a
    /// 440 pt phone: tiles start at 55, 373, 691 and 1008 px), 88.7 pt tall.
    public static let tileSideInset: CGFloat = 18.33
    public static let tileSpacing: CGFloat = 20.33
    public static let tileHeight: CGFloat = 88.7
    public static let tileCornerRadius: CGFloat = 22
    /// A tile's label is centred this far under it.
    public static let tileLabelDrop: CGFloat = 15
    /// Tiles to the first row.
    public static let rowsGap: CGFloat = 39
    public static let rowHeight: CGFloat = 48
    public static let rowCornerRadius: CGFloat = 14
    /// Between the Display Options group, Site Settings and the footer card.
    public static let groupGap: CGFloat = 16
    public static let footerHeight: CGFloat = 55.7
    /// The footer card's bottom to the bottom safe area.
    public static let footerBottom: CGFloat = 22.3
    public static let cornerRadius: CGFloat = 38

    /// The sheet's height, with Display Options closed or open, over a bottom safe area of `safeBottom`.
    public static func height(displayOptionsOpen: Bool = false, safeBottom: CGFloat) -> CGFloat {
        let group = CGFloat(displayOptionsOpen ? 1 + displayOptions.count : 1) * rowHeight
        return inset + capsuleHeight + tilesGap + tileHeight + rowsGap + group + groupGap + rowHeight + groupGap
            + footerHeight + footerBottom + safeBottom
    }

    /// A tile's width in a sheet `width` wide.
    public static func tileWidth(in width: CGFloat) -> CGFloat {
        (width - 2 * tileSideInset - 3 * tileSpacing) / 4
    }

    /// Where the tiles go in a sheet `width` wide: four fill it; fewer keep the same spacing, centred.
    public static func tileFrames(count: Int, width: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let top = inset + capsuleHeight + tilesGap
        let tile = tileWidth(in: width)
        let span = CGFloat(count) * tile + CGFloat(count - 1) * tileSpacing
        let start = (width - span) / 2
        return (0..<count).map { CGRect(x: start + CGFloat($0) * (tile + tileSpacing), y: top, width: tile, height: tileHeight) }
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

    /// The footer card's first line, "Cra scrubbed 22 trackers" (the number in bold), or nil
    /// when nothing was blocked.
    public static func scrubbedLabel(_ count: Int) -> (text: String, number: String)? {
        guard count > 0 else { return nil }
        return ("Cra scrubbed \(count) tracker\(count == 1 ? "" : "s")", "\(count)")
    }

    /// The footer card's second line: a tap reloads the page without blockers.
    public static let restoreHint = "Problems? Tap to restore original page"
}
