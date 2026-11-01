import Foundation
import Observation

/// One sidebar item's change counter. A view that read the item depends on this, not on
/// every item.
@MainActor @Observable
public final class ItemSignal {
    public var version = 0

    public init() {}
}

/// The sidebar's items, observed one by one. As a single `[UUID: SidebarItem]` property, any
/// write (a tab switch marks the tab active, a page reports its title) re-rendered every list
/// and row in every space. Now a view re-renders when an item it read changed; a walk over
/// all items (`all`, `values`) still depends on every change.
@MainActor @Observable
public final class ItemTable {
    @ObservationIgnored private var storage: [UUID: SidebarItem] = [:]
    @ObservationIgnored private var signals: [UUID: ItemSignal] = [:]
    /// Bumped on every change: what a walk over all items observes.
    private var version = 0

    public init() {}

    public subscript(id: UUID) -> SidebarItem? {
        get {
            observe(id)
            return storage[id]
        }
        set {
            guard storage[id] != newValue else { return }
            storage[id] = newValue
            notify(id)
        }
    }

    public var all: [UUID: SidebarItem] {
        _ = version
        return storage
    }

    public var values: Dictionary<UUID, SidebarItem>.Values { all.values }

    /// Depend on `id` without reading it (state kept elsewhere, keyed by the item: expansion,
    /// selection).
    public func observe(_ id: UUID) { _ = signal(id).version }

    /// What reads `id` is out of date.
    public func notify(_ id: UUID) {
        signal(id).version &+= 1
        version &+= 1
    }

    private func signal(_ id: UUID) -> ItemSignal {
        if let s = signals[id] { return s }
        let s = ItemSignal()
        signals[id] = s
        return s
    }
}
