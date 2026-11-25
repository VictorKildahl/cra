import AppKit

extension NSView {
    /// Whether a pointer at `screenPoint` is on this view, and on it rather than on another view of its window drawn over
    /// it. The tracking areas of views under a list hung over them still see the pointer: resting it on Library's
    /// downloads brought up the names of the tabs under the list (#770). True when hit-testing there finds this
    /// view, a view inside it, or one it is inside (nothing of its own takes the click there).
    func isUncovered(atScreenPoint screenPoint: NSPoint) -> Bool {
        guard let window, let content = window.contentView else { return false }
        let inWindow = window.convertPoint(fromScreen: screenPoint)
        guard bounds.contains(convert(inWindow, from: nil)) else { return false }
        guard let hit = content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow) else { return false }
        return hit === self || hit.isDescendant(of: self) || isDescendant(of: hit)
    }
}
