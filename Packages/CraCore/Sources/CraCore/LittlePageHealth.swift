import CoreGraphics
import Foundation

/// Whether a Little Window's page is drawing, and what to do when it isn't (GitHub #848).
///
/// A link from another app opened a Little Window whose page stayed white (macOS 27.2.1) until the window was
/// resized or the page reloaded. Chromium draws a page only while it thinks its view is shown, at the size it
/// laid it out for; the window's arrival from another app (activation, the grow-in, a panel joining the
/// app in front) can leave either behind. So after the window comes up, and again each time it becomes key,
/// Cra looks at the page the way it looks at a tab's (PageProbe): a page in a window on screen with nothing over
/// it must say "visible", have its frames ticking and be laid out at its view's size. When it isn't, Cra shows
/// the page's view again and gives it one resize (what the reporter's resize did), then looks once more.
public enum LittlePageHealth {
    /// What Cra saw of the window and its page.
    public struct Look: Sendable, Equatable {
        /// The window is ordered in on the active Space, not minimised, and nothing covers it on screen.
        public var windowShown: Bool
        /// The card, a parked Peek or a Peek still opening: the page is meant to be out of sight.
        public var pageMeantHidden: Bool
        /// The page's view, or a view it sits in inside the window, is hidden.
        public var viewHidden: Bool
        /// From the page: `document.visibilityState`, animation frames a second, its viewport in points.
        /// Nil when the page didn't answer (no page yet, a renderer busy or gone).
        public var visibility: String?
        public var frameRate: Int?
        public var viewport: CGSize?
        /// The page's view in the window, in points.
        public var viewSize: CGSize
        /// The page is loading: a renderer busy with a load may not answer in time, which says nothing.
        public var loading: Bool

        public init(windowShown: Bool, pageMeantHidden: Bool, viewHidden: Bool, visibility: String?, frameRate: Int?,
                    viewport: CGSize?, viewSize: CGSize, loading: Bool = false) {
            self.windowShown = windowShown
            self.pageMeantHidden = pageMeantHidden
            self.viewHidden = viewHidden
            self.visibility = visibility
            self.frameRate = frameRate
            self.viewport = viewport
            self.viewSize = viewSize
            self.loading = loading
        }
    }

    public enum Verdict: Sendable, Equatable {
        /// Drawing as it should.
        case drawing
        /// Nothing to judge: the window isn't in sight, the page is meant to be hidden, or the page didn't answer.
        case notJudged
        /// In sight and not drawing, for these reasons (said in the log).
        case stuck([String])
    }

    /// A viewport this far off the view's size, in points, is a page laid out for another size (scrollbars and
    /// rounding stay under it).
    public static let sizeTolerance: CGFloat = 24

    public static func judge(_ look: Look) -> Verdict {
        guard look.windowShown, !look.pageMeantHidden else { return .notJudged }
        var reasons: [String] = []
        if look.viewHidden { reasons.append("its view is hidden") }
        guard let visibility = look.visibility, let frameRate = look.frameRate else {
            // A loaded page in sight that doesn't answer in 3 s: one Chromium hid ran no frames for the probe to count
            // (the white window, a few minutes on). A busy load says nothing.
            if !look.loading { reasons.append("it didn't answer") }
            return reasons.isEmpty ? .notJudged : .stuck(reasons)
        }
        if visibility != "visible" { reasons.append("it says \(visibility)") }
        if frameRate == 0 { reasons.append("no frames") }
        if let viewport = look.viewport, look.viewSize.width > 0, look.viewSize.height > 0,
           abs(viewport.width - look.viewSize.width) > sizeTolerance || abs(viewport.height - look.viewSize.height) > sizeTolerance {
            reasons.append("laid out at \(Int(viewport.width))x\(Int(viewport.height)) in a \(Int(look.viewSize.width))x\(Int(look.viewSize.height)) view")
        }
        return reasons.isEmpty ? .drawing : .stuck(reasons)
    }

    /// PageProbe's viewport (`"1120x688@2.5"`: CSS pixels at a device pixel ratio) in the window's points. A page
    /// zoomed to 125 % on a 2x display has a ratio of 2.5 and 1.25 times fewer CSS pixels, the same points.
    public static func viewport(_ text: String, backingScale: CGFloat) -> CGSize? {
        let halves = text.split(separator: "@")
        let parts = (halves.first ?? "").split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, backingScale > 0 else { return nil }
        let ratio = halves.count == 2 ? Double(halves[1]) ?? Double(backingScale) : Double(backingScale)
        let factor = ratio / Double(backingScale)
        return CGSize(width: (parts[0] * factor).rounded(), height: (parts[1] * factor).rounded())
    }

    /// How often one showing of a window tries to bring its page back: a page that stays stuck after that is
    /// left alone (and said in the log), so a page that never draws can't keep Cra resizing it.
    public struct Tries: Sendable, Equatable {
        public static let limit = 2
        public private(set) var used = 0

        public init() {}

        /// Whether to try again, counting this try.
        public mutating func take() -> Bool {
            guard used < Self.limit else { return false }
            used += 1
            return true
        }

        /// The window came up again (shown, or a new page in it): it may try again.
        public mutating func reset() { used = 0 }
    }
}
