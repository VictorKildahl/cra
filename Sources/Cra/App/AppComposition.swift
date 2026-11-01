import Foundation

/// What a running Cra is made of, built once: the clock, the feature flags and the store on
/// the data folder's files (CRA_DATA_DIR for a test instance). AppDelegate builds it at launch;
/// a test host builds the same graph with a manual clock (Tests/StoreTests.swift), so timed
/// work is tried on the code that ships rather than on a copy of it.
@MainActor
final class AppComposition {
    let clock: Scheduler
    let flags: FeatureFlags
    let store: SidebarStore
    private var periodic: [ScheduledWork] = []

    init(clock: Scheduler? = nil, flags: FeatureFlags = .current) {
        self.clock = clock ?? LiveScheduler.shared
        self.flags = flags
        store = SidebarStore(clock: self.clock)
    }

    /// Arc archives on a 30-minute pass; tab sleeping looks every minute. `sleepTabs` reaches
    /// the windows' browser managers, which the composition does not own.
    static let autoArchiveInterval: TimeInterval = 1800
    static let tabSleepInterval: TimeInterval = 60

    func startPeriodicWork(sleepTabs: @escaping @MainActor () -> Void) {
        periodic.forEach { $0.cancel() }
        store.runAutoArchive()
        periodic = [
            clock.every(Self.autoArchiveInterval) { [weak self] in self?.store.runAutoArchive() },
            clock.every(Self.tabSleepInterval) { [weak self] in
                guard let self, self.store.settings.tabSleepEnabled else { return }
                sleepTabs()
            },
        ]
    }
}
