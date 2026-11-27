/// The trackpad tick while a row is dragged in the sidebar (issue #883).
///
/// Arc keeps the haptic in its sidebar outline's data source (`dropHapticSubject`,
/// `tabReorderingHapticsDisabled`, `draggedItemIndexes` beside `outlineView` in Arc 1.174.3), which
/// takes tabs, folders and splits alike: a tick each time the drag is offered a new place, the same
/// for every kind of row. Cra ticked only when a tab started offering to combine into a split, so a
/// dragged folder was silent until the drop, after the finger had left the trackpad.
///
/// `Place` is where the row would land (a slot, a folder to go into, a tab to combine with); nil
/// is nowhere, such as the row's own place.
public struct SidebarReorderHaptics<Place: Equatable> {
    public private(set) var place: Place?

    public init(place: Place? = nil) { self.place = place }

    /// The drag is now offered `next`. True when that calls for a tick: a place, and not the one
    /// already offered. Leaving for nowhere is silent; coming back to a place ticks again.
    public mutating func offer(_ next: Place?) -> Bool {
        defer { place = next }
        guard let next else { return false }
        return next != place
    }
}
