import CoreGraphics
import Foundation

/// Whether a browser window that macOS calls not visible is really out of sight, for Arc's automatic
/// Picture in Picture of an occluded window (#117). On macOS 27.2.1 a window left on a second display,
/// with nothing in front of it, sent its video to Picture in Picture as soon as another app became
/// active on the first display (#533); on 26 its occlusion state stayed visible. So the windows in front
/// decide: other windows that are drawn (alpha above 0) must cover all of it between them. The window's
/// own parts never count: its child windows and Chrome's page host windows, which lay over all of it
/// with alpha 0 in 0.1.48 and are a 1 pt strip along its top since #346. A window that isn't on screen (minimised, the app hidden, another desktop)
/// is out of sight. Frames are in one coordinate space (CGWindowList's).
public enum WindowCoverage {
    public struct Above: Sendable, Equatable {
        public var frame: CGRect
        public var alpha: Double
        public var isOwnPart: Bool

        public init(frame: CGRect, alpha: Double, isOwnPart: Bool) {
            self.frame = frame
            self.alpha = alpha
            self.isOwnPart = isOwnPart
        }
    }

    /// Strips narrower than this are left out: a window's shadow or a rounding of its frame, not
    /// something the user watches.
    static let sliver: CGFloat = 2

    public static func isCovered(frame: CGRect, onScreen: Bool, above: [Above]) -> Bool {
        guard onScreen else { return true }
        var left = [frame.standardized]
        for w in above where !w.isOwnPart && w.alpha > 0 {
            left = left.flatMap { subtract(w.frame.standardized, from: $0) }
            if left.isEmpty { return true }
        }
        return left.isEmpty
    }

    /// What is left of `r` with `cut` taken out: up to four rectangles, without slivers.
    static func subtract(_ cut: CGRect, from r: CGRect) -> [CGRect] {
        let i = r.intersection(cut)
        guard !i.isNull, i.width > 0, i.height > 0 else { return [r] }
        let parts = [
            CGRect(x: r.minX, y: r.minY, width: r.width, height: i.minY - r.minY),          // above the cut
            CGRect(x: r.minX, y: i.maxY, width: r.width, height: r.maxY - i.maxY),          // below it
            CGRect(x: r.minX, y: i.minY, width: i.minX - r.minX, height: i.height),         // beside it, left
            CGRect(x: i.maxX, y: i.minY, width: r.maxX - i.maxX, height: i.height),         // and right
        ]
        return parts.filter { $0.width >= sliver && $0.height >= sliver }
    }

    // MARK: The window server's list

    /// One window as `CGWindowListCopyWindowInfo` describes it (keys `kCGWindowNumber`,
    /// `kCGWindowOwnerPID`, `kCGWindowBounds`, `kCGWindowAlpha`, `kCGWindowIsOnscreen`). The list leaves
    /// out `kCGWindowIsOnscreen` for a window that isn't on screen, and the alpha of none is 1.
    public struct Listed: Sendable, Equatable {
        public var number: Int
        public var ownerPID: Int32
        public var frame: CGRect
        public var alpha: Double
        public var onScreen: Bool

        public init(number: Int, ownerPID: Int32, frame: CGRect, alpha: Double, onScreen: Bool) {
            self.number = number
            self.ownerPID = ownerPID
            self.frame = frame
            self.alpha = alpha
            self.onScreen = onScreen
        }

        public init?(_ info: [String: Any]) {
            guard let number = Self.int(info["kCGWindowNumber"]), let pid = Self.int(info["kCGWindowOwnerPID"]),
                  let b = info["kCGWindowBounds"] as? [String: Any],
                  let x = Self.double(b["X"]), let y = Self.double(b["Y"]),
                  let w = Self.double(b["Width"]), let h = Self.double(b["Height"]) else { return nil }
            self.number = number
            ownerPID = Int32(truncatingIfNeeded: pid)
            frame = CGRect(x: x, y: y, width: w, height: h)
            alpha = Self.double(info["kCGWindowAlpha"]) ?? 1
            onScreen = info["kCGWindowIsOnscreen"] as? Bool ?? false
        }

        private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? Int) }
        private static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? Double) }
    }

    /// What the window server says about a window, for the decision and `cra://debug?windowCoverage=1`.
    public struct Reading: Sendable, Equatable {
        public var covered: Bool
        public var onScreen: Bool
        /// Windows in front of it on screen, its own parts among them, and those drawn with alpha 0.
        public var inFront: Int
        public var ownParts: Int
        public var seeThrough: Int

        public init(covered: Bool, onScreen: Bool, inFront: Int, ownParts: Int, seeThrough: Int) {
            self.covered = covered
            self.onScreen = onScreen
            self.inFront = inFront
            self.ownParts = ownParts
            self.seeThrough = seeThrough
        }

        public var summary: String {
            guard onScreen else { return "not on screen, covered" }
            return "on screen, \(inFront) in front (\(ownParts) own parts, \(seeThrough) see-through), \(covered ? "covered" : "not covered")"
        }
    }

    /// `window`: the window's own entry, nil when the window server has none (then it counts as out of
    /// sight, as macOS said). `inFront`: the on-screen windows above it. `isOwnPart` is asked only for
    /// this process's windows, by window number.
    public static func read(window: [String: Any]?, inFront: [[String: Any]], pid: Int32,
                            isOwnPart: (Int) -> Bool) -> Reading {
        guard let own = window.flatMap(Listed.init) else {
            return Reading(covered: true, onScreen: false, inFront: 0, ownParts: 0, seeThrough: 0)
        }
        let above = inFront.compactMap(Listed.init).map { w in
            Above(frame: w.frame, alpha: w.alpha, isOwnPart: w.ownerPID == pid && isOwnPart(w.number))
        }
        return Reading(covered: isCovered(frame: own.frame, onScreen: own.onScreen, above: above), onScreen: own.onScreen,
                       inFront: above.count, ownParts: above.filter(\.isOwnPart).count,
                       seeThrough: above.filter { $0.alpha <= 0 }.count)
    }
}
