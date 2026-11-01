import Foundation

/// A clock that moves only when the test says so. `advance(by:)` runs every timer that falls
/// due on the way, in time order, with `now` set to the moment each one fires.
@MainActor
final class ManualScheduler: Scheduler {
    private struct Entry {
        let id: Int
        var due: Date
        let interval: TimeInterval?
        let handle: ScheduledWork
        let work: @MainActor () -> Void
    }

    private(set) var now: Date
    private var entries: [Entry] = []
    private var nextID = 0

    /// Starts at the real time: model factories (SidebarItem.tab) stamp createdAt with it.
    init(now: Date = Date()) { self.now = now }

    var pendingCount: Int { entries.filter { !$0.handle.isCancelled }.count }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        add(delay, repeats: false, work)
    }

    func every(_ interval: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        add(interval, repeats: true, work)
    }

    private func add(_ interval: TimeInterval, repeats: Bool, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        nextID += 1
        let id = nextID
        let handle = ScheduledWork { [weak self] in self?.entries.removeAll { $0.id == id } }
        entries.append(Entry(id: id, due: now.addingTimeInterval(interval), interval: repeats ? interval : nil, handle: handle, work: work))
        return handle
    }

    func advance(by seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let i = entries.indices.filter({ entries[$0].due <= end }).min(by: { (entries[$0].due, entries[$0].id) < (entries[$1].due, entries[$1].id) }) {
            let entry = entries[i]
            now = entry.due
            if let interval = entry.interval { entries[i].due = entry.due.addingTimeInterval(interval) } else { entries.remove(at: i) }
            entry.work()
        }
        now = end
    }
}
