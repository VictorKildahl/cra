import Foundation

/// How many slept pages a window keeps (GitHub #616). Tab sleeping ends a page's renderer and keeps the
/// rest: its browser, its hidden window and its switcher thumbnail, for the whole session. Nothing bounded
/// them, so a long session with thousands of tabs kept gigabytes for pages that reload when shown anyway.
/// A window now keeps its 32 most recently hidden slept pages; older ones close, a few per pass, and
/// reload with their back/forward list and scroll, as a slept page does. Only slept pages are touched:
/// a page tab sleeping keeps awake (typed text, a call, sound, Picture in Picture) is never one.
public enum RetainedPageBudget {
    public struct Page: Equatable, Sendable {
        public let id: UUID
        /// Tab sleeping ended its renderer.
        public let discarded: Bool
        /// When it went off screen; nil while shown.
        public let hiddenAt: Date?
        public let visible: Bool
        /// Playing, in Picture in Picture, recording, loading or with DevTools open.
        public let busy: Bool

        public init(id: UUID, discarded: Bool, hiddenAt: Date?, visible: Bool, busy: Bool) {
            self.id = id; self.discarded = discarded; self.hiddenAt = hiddenAt; self.visible = visible; self.busy = busy
        }
    }

    /// Slept pages a window keeps.
    public static let perWindow = 32
    /// Pages closed in one pass: the first pass after a long session may find hundreds, and each close
    /// ends a browser and orders windows.
    public static let perPass = 8

    /// The pages to close now, oldest hidden first.
    public static func unloads(_ pages: [Page], budget: Int = perWindow, limit: Int = perPass) -> [UUID] {
        let slept = pages.filter { $0.discarded && !$0.visible && !$0.busy && $0.hiddenAt != nil }
        guard slept.count > budget, limit > 0 else { return [] }
        // Latest hidden first; equal times in id order, so a pass always picks the same pages.
        let ordered = slept.sorted { a, b in
            a.hiddenAt! != b.hiddenAt! ? a.hiddenAt! > b.hiddenAt! : a.id.uuidString < b.id.uuidString
        }
        return Array(ordered.dropFirst(budget).reversed().prefix(limit).map(\.id))
    }
}
