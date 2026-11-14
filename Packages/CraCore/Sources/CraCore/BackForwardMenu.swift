import CoreGraphics
import Foundation

/// A right-click (or a press held on) Back or Forward: Arc's BackForwardList menu (GitHub #416).
/// Arc 1.172 hangs its ArcMenu under the button, tail up, one row per page of the tab's history in
/// that direction, the nearest first: the page's favicon and its title. Picking a row goes straight
/// to that page.
///
/// The history is Chromium's (DevTools `Page.getNavigationHistory`, which WebKit pages answer from
/// their `backForwardList`), so the rows are built from its reply.
public enum BackForwardMenu {
    public enum Direction: Sendable { case back, forward }

    public struct Row: Equatable, Sendable {
        /// The entry's id, for `Page.navigateToHistoryEntry`.
        public var entryID: Int
        public var title: String
        public var url: String

        public init(entryID: Int, title: String, url: String) {
            (self.entryID, self.title, self.url) = (entryID, title, url)
        }
    }

    /// Chromium's back and forward menus show 12 pages at most (kMaxBackForwardMenuItems).
    public static let maxRows = 12

    /// The rows for `direction` from a `Page.getNavigationHistory` reply
    /// (`{"currentIndex": n, "entries": [{"id", "url", "title"}, …]}`); none for anything else.
    public static func rows(history json: String, direction: Direction) -> [Row] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["currentIndex"] as? Int,
              let entries = object["entries"] as? [[String: Any]] else { return [] }
        let list = entries.map { e in
            Row(entryID: e["id"] as? Int ?? -1, title: e["title"] as? String ?? "", url: e["url"] as? String ?? "")
        }
        return rows(entries: list, currentIndex: current, direction: direction)
    }

    /// The entries behind (`.back`) or ahead of (`.forward`) `currentIndex`, nearest first, at most
    /// `maxRows`. A page without a title shows its address, as Chromium's menu does.
    public static func rows(entries: [Row], currentIndex: Int, direction: Direction) -> [Row] {
        guard entries.indices.contains(currentIndex) else { return [] }
        let side = direction == .back ? Array(entries[..<currentIndex].reversed()) : Array(entries[(currentIndex + 1)...])
        return side.filter { $0.entryID >= 0 && !$0.url.isEmpty }.prefix(maxRows).map { entry in
            var row = entry
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            row.title = title.isEmpty ? displayURL(entry.url) : title
            return row
        }
    }

    /// An address as a row shows it: no scheme, no trailing slash.
    public static func displayURL(_ url: String) -> String {
        var s = url
        for scheme in ["https://", "http://"] where s.lowercased().hasPrefix(scheme) {
            s.removeFirst(scheme.count)
            break
        }
        if s.hasSuffix("/"), s.dropLast().contains("/") == false { s.removeLast() }
        return s
    }

    /// The menu's geometry in points, top-left origin, measured from Arc 1.172 (the 2x capture in
    /// #416, then Victor's Arc live, 13 Nov 2026): a 220 pt fill with 12 pt corners, 40 pt rows with
    /// 8 pt above the first and below the last, a 16 pt favicon 16 pt in (a page without one: a
    /// 14 pt rounded square) and the title 40 pt in (13 pt medium, white), the row's hover 8 pt in
    /// from each side with 7 pt corners, and a 12 pt wide, 7 pt tall tail whose tip sits 10 pt under
    /// the button, centred on it. The fill is centred under the button too. Arc's window is 6 pt
    /// larger all round (232 × 74 pt for one row): the menu draws its own soft shadow there.
    public enum Layout {
        public static let width: CGFloat = 220
        public static let rowHeight: CGFloat = 40
        public static let padding: CGFloat = 8
        public static let cornerRadius: CGFloat = 12
        public static let rowInset: CGFloat = 8
        public static let rowCornerRadius: CGFloat = 7
        public static let faviconX: CGFloat = 16
        public static let faviconSize: CGFloat = 16
        /// Arc's stand-in for a page with no favicon.
        public static let placeholderSize: CGFloat = 14
        public static let titleX: CGFloat = 40
        /// The title is cut with an ellipsis this far from the fill's right edge.
        public static let titleTrailing: CGFloat = 20
        public static let tailHeight: CGFloat = 7
        public static let tailHalfWidth: CGFloat = 6
        /// From the button's bottom edge to the tail's tip.
        public static let gap: CGFloat = 10
        /// Room for the shadow round the menu, inside the window.
        public static let margin: CGFloat = 6
        /// The fill starts a point above the tail's base, so the two join without a seam.
        public static let fillTop: CGFloat = margin + tailHeight - 1
        /// Keeps the tail off the fill's rounded corners.
        public static let tailMargin: CGFloat = 18
        /// Off the screen's edges.
        public static let screenMargin: CGFloat = 4

        public static func fillHeight(rows: Int) -> CGFloat { 2 * padding + rowHeight * CGFloat(rows) }

        /// The whole window: margin, tail and fill.
        public static func size(rows: Int) -> CGSize {
            CGSize(width: width + 2 * margin, height: fillTop + fillHeight(rows: rows) + margin)
        }

        public static func fillRect(rows: Int) -> CGRect { CGRect(x: margin, y: fillTop, width: width, height: fillHeight(rows: rows)) }

        /// Row `index`'s hover fill, which is also where it takes clicks.
        public static func rowRect(_ index: Int) -> CGRect {
            CGRect(x: margin + rowInset, y: fillTop + padding + rowHeight * CGFloat(index), width: width - 2 * rowInset, height: rowHeight)
        }

        public static func faviconRect(_ index: Int) -> CGRect {
            let row = rowRect(index)
            return CGRect(x: margin + faviconX, y: row.midY - faviconSize / 2, width: faviconSize, height: faviconSize)
        }

        public static var titleWidth: CGFloat { width - titleX - titleTrailing }

        /// Where the menu window goes for a button at `button` on a screen whose usable part is
        /// `screen`, both in screen coordinates (origin bottom left, as AppKit's), and the tail's x
        /// in the window. The fill is centred under the button and kept on the screen; the tail
        /// stays on the button's centre unless that would put it on a corner.
        public static func placement(button: CGRect, screen: CGRect, rows: Int) -> (frame: CGRect, tailX: CGFloat) {
            let size = size(rows: rows)
            let fillX = min(max(button.midX - width / 2, screen.minX + screenMargin), screen.maxX - width - screenMargin)
            let top = button.minY - gap + margin
            let y = max(top - size.height, screen.minY + screenMargin - margin)
            let tailX = min(max(button.midX - fillX, tailMargin), width - tailMargin) + margin
            return (CGRect(x: fillX - margin, y: y, width: size.width, height: size.height), tailX)
        }
    }
}
