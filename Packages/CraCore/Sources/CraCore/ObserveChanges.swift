import Observation

/// Calls `apply` with what `read` returns now, then again whenever that value changes, for as
/// long as the app runs. Observation reports a change on every write to a stored property, and
/// SidebarStore.settings is one struct: an observer of `settings.httpsOnly` fires on any settings
/// write. Unchanged values stop here, so a side effect (a Chromium preference) runs only for a
/// real change, not on every write during onboarding or at quit (#36).
@MainActor
public func observeChanges<Value: Equatable>(of read: @escaping @MainActor () -> Value,
                                             apply: @escaping @MainActor (Value) -> Void) {
    var last: Value?
    func track() {
        let value = withObservationTracking(read) {
            Task { @MainActor in track() }
        }
        if value != last {
            last = value
            apply(value)
        }
    }
    track()
}
