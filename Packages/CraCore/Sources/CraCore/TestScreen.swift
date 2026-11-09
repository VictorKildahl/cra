import CoreGraphics
import Foundation

/// CRA_TEST_SCREEN=<display>: every window a test instance opens lands on that display, not on
/// the one in use (macOS centres a new window on the screen with the pointer or the key window,
/// so agents' test runs used to pop up wherever Victor was working). Export it once in
/// ~/.zshenv and every launcher that runs the binary directly passes it on (scenario.sh,
/// smoke-launch.sh, clip.sh, dev.sh). Unset, or naming no connected display, nothing changes.
///
/// The value is `left`, `right` or `main` (the menu bar's display), or a display's name as
/// macOS shows it (`HP Z24nf G2`); a part of a name is enough when only one display has it.
/// Two displays of the same model get a "(1)"/"(2)" that macOS can swap: pick those by side.
public enum TestScreen {
    public static let environmentKey = "CRA_TEST_SCREEN"

    public struct Display: Equatable, Sendable {
        public var name: String
        /// The whole display, in global coordinates.
        public var frame: CGRect
        /// The part a window may cover (no menu bar, no Dock).
        public var visibleFrame: CGRect

        public init(name: String, frame: CGRect, visibleFrame: CGRect) {
            self.name = name
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// The index in `displays` (macOS's order: the menu bar's display first) that `spec` names.
    public static func pick(_ spec: String?, among displays: [Display]) -> Int? {
        guard let spec = spec?.trimmingCharacters(in: .whitespaces), !spec.isEmpty, !displays.isEmpty else { return nil }
        let indices = Array(displays.indices)
        switch spec.lowercased() {
        case "main": return 0
        case "left": return indices.min { displays[$0].frame.minX < displays[$1].frame.minX }
        case "right": return indices.max { displays[$0].frame.maxX < displays[$1].frame.maxX }
        default: break
        }
        if let exact = indices.first(where: { displays[$0].name.caseInsensitiveCompare(spec) == .orderedSame }) { return exact }
        let partial = indices.filter { displays[$0].name.range(of: spec, options: .caseInsensitive) != nil }
        return partial.count == 1 ? partial[0] : nil
    }

    /// `frame` moved onto `target`: kept at the same place relative to the display it was saved
    /// on (so new windows still cascade off the last one), centred when it was on no display,
    /// and shrunk and pulled in until it fits the target's visible frame.
    public static func place(_ frame: CGRect, on target: Display, among displays: [Display]) -> CGRect {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        var f = frame
        f.size.width = min(f.width, target.visibleFrame.width)
        f.size.height = min(f.height, target.visibleFrame.height)
        if let source = displays.first(where: { $0.frame.contains(centre) }) {
            // Top-left relative to the visible frame, as AppKit cascades.
            f.origin.x = target.visibleFrame.minX + (frame.minX - source.visibleFrame.minX)
            f.origin.y = target.visibleFrame.maxY - (source.visibleFrame.maxY - frame.maxY) - f.height
        } else {
            f.origin = CGPoint(x: target.visibleFrame.midX - f.width / 2, y: target.visibleFrame.midY - f.height / 2)
        }
        f.origin.x = min(max(target.visibleFrame.minX, f.origin.x), target.visibleFrame.maxX - f.width)
        f.origin.y = min(max(target.visibleFrame.minY, f.origin.y), target.visibleFrame.maxY - f.height)
        return f
    }

    /// Centred on `target`'s visible frame, shrunk to fit: NSWindow.center() on the test display.
    public static func centre(_ size: CGSize, on target: Display) -> CGRect {
        let w = min(size.width, target.visibleFrame.width), h = min(size.height, target.visibleFrame.height)
        return CGRect(x: target.visibleFrame.midX - w / 2, y: target.visibleFrame.midY - h / 2, width: w, height: h)
    }
}
