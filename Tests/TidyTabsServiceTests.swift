import Foundation

@main
@MainActor enum TidyTabsServiceTests {
    private static var checks = 0
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-tidy-tabs-service-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("CRA_DATA_DIR", root.path, 1)
        setenv("CRA_ARC_DIR", root.appendingPathComponent("NoArc").path, 1)
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        _ = TidyTabsService.fakeModel
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        switch CommandLine.arguments.dropFirst().first {
        case "failure": await failureRemainsRetryable()
        case "settings": await settingsOffOn()
        case "availability": await availabilityChanges()
        case "delete": await removedSpace()
        case "owner": await ownerLifetimes()
        default:
            await entryGuards()
            await failureRemainsRetryable()
            await emptyAndFittedSuccess()
            await settingsOffOn()
            await availabilityChanges()
            await removedSpace()
            await independentTargets()
            await cancelledTask()
            await ownerLifetimes()
            await fittedConvergence()
        }
        print("Tidy Tabs lifecycle: \(checks) checks passed")
    }

    private static func entryGuards() async {
        for kind in ["disabled", "small", "unavailable", "private"] {
            let f = Fixture(count: kind == "small" ? 5 : 6)
            var sid = f.sid
            if kind == "disabled" { f.store.settings.tidyTabs = false }
            if kind == "unavailable" { f.available.value = false }
            if kind == "private" {
                sid = f.store.addIncognitoWindow(frame: nil).focusedSpaceID!
                populate(f.store, sid: sid, count: 6)
            }
            let before = f.store.document
            expect(f.service.tidy(sid, store: f.store) == nil && f.store.tidyingSpaces.isEmpty && f.store.document == before,
                   "public tidy rejects \(kind) without starting animation or changing the sidebar")
            expect(f.generator.requests.isEmpty, "rejected \(kind) entry cannot reach the provider")
        }
        let f = Fixture(count: 7)
        let ids = f.store.looseTodayTabs(f.sid).map(\.id)
        f.store.applyTidy(TidyTabs.plan([.init(name: "Existing", tabs: Array(0..<6))], tabCount: 6, existingGroups: []),
                          tabIDs: Array(ids.prefix(6)), in: f.sid)
        let task = f.service.tidy(f.sid, store: f.store)
        expect(task != nil && f.store.looseTodayTabs(f.sid).count == 1,
               "six-total eligibility still allows a request with one loose tab beside grouped tabs")
        await f.generator.waitFor(1)
        f.generator.success(1, proposals: [.init(name: "Calendar", tabs: [0])])
        await task?.value
        f.clock.advance(by: TidyTabs.minimumRun)
        expect(f.store.tabGroups(in: f.sid).contains { $0.title == "Calendar" && $0.children == [ids.last!] },
               "a valid remaining singleton keeps the approved Calendar-style grouping behavior")
    }

    private static func failureRemainsRetryable() async {
        for kind in ["unavailable", "context", "generic", "cancelled"] {
            let f = Fixture()
            let original = f.store.document
            let task = f.service.tidy(f.sid, store: f.store)
            await f.generator.waitFor(1)
            let request = f.generator.requests[0]
            let error: Error
            switch kind {
            case "unavailable": error = TidyTabsModel.Failure.unavailable
            case "context": error = TidyTabsModel.Failure.contextLimit(request)
            case "cancelled": error = CancellationError()
            default: error = CocoaError(.coderInvalidValue)
            }
            f.generator.resolve(1, with: .failure(error))
            await task?.value
            if kind != "cancelled" {
                f.clock.advance(by: TidyTabs.minimumRun / 2)
                expect(f.store.tidyingSpaces.contains(f.sid) && f.store.tidiedTabs[f.sid] == nil,
                       "a fast \(kind) failure preserves the minimum broom interval without consuming IDs")
                f.clock.advance(by: TidyTabs.minimumRun / 2)
            }
            expect(f.store.canTidy(f.sid) && f.store.tidiedTabs[f.sid] == nil && !f.store.tidyingSpaces.contains(f.sid)
                   && f.store.document == original,
                   "\(kind) generation ends the broom without consuming retry, tree or considered IDs")
            let retry = f.service.tidy(f.sid, store: f.store)
            await f.generator.waitFor(2)
            f.generator.success(2, proposals: [.init(name: "Retry", tabs: [0, 1])])
            await retry?.value
            f.clock.advance(by: TidyTabs.minimumRun)
            expect(f.store.tabGroups(in: f.sid).first?.children == Array(request.tabIDs.prefix(2)),
                   "retry after \(kind) failure applies normally")
        }
    }

    private static func emptyAndFittedSuccess() async {
        let f = Fixture()
        let task = f.service.tidy(f.sid, store: f.store)
        await f.generator.waitFor(1)
        let fitted = f.generator.requests[0].reduced()!
        let arrival = f.store.createTab(url: "https://example.org/new", in: f.sid, select: false)
        let before = f.store.document
        f.generator.success(1, request: fitted)
        await task?.value
        f.clock.advance(by: TidyTabs.minimumRun / 2)
        expect(f.store.tidiedTabs[f.sid] == nil && f.store.tidyingSpaces.contains(f.sid),
               "successful empty output also waits for the measured minimum animation")
        f.clock.advance(by: TidyTabs.minimumRun / 2)
        expect(f.store.tidiedTabs[f.sid] == Set(fitted.tabIDs) && f.store.document == before && f.store.tabGroups(in: f.sid).isEmpty,
               "successful empty output consumes only actual fitted IDs without mutating the sidebar")
        expect(f.store.canTidy(f.sid) && f.store.item(arrival.id)?.parentID == f.store.space(f.sid)?.todayContainerID,
               "unfitted tabs and a new arrival remain loose and eligible after success")
        expect(f.store.integrityProblems().isEmpty, "fitted empty completion preserves sidebar integrity")
        let failed = f.service.tidy(f.sid, store: f.store)
        await f.generator.waitFor(2)
        f.generator.resolve(2, with: .failure(CocoaError(.coderInvalidValue)))
        await failed?.value
        f.clock.advance(by: TidyTabs.minimumRun)
        expect(f.store.tidiedTabs[f.sid] == Set(fitted.tabIDs) && f.store.canTidy(f.sid) && f.store.document == before,
               "failure preserves previously considered fitted IDs and the remaining retry action")

        let undo = Fixture()
        let original = undo.store.looseTodayTabs(undo.sid).map(\.id)
        undo.store.applyTidy(TidyTabs.plan([.init(name: "Before empty", tabs: [0, 1])], tabCount: 6, existingGroups: []),
                             tabIDs: original, in: undo.sid)
        let new = undo.store.createTab(url: "https://example.org/arrival", in: undo.sid, select: false)
        let empty = undo.service.tidy(undo.sid, store: undo.store)
        await undo.generator.waitFor(1)
        undo.generator.success(1)
        await empty?.value
        undo.clock.advance(by: TidyTabs.minimumRun)
        expect(undo.store.undoTidy() && undo.store.tabGroups(in: undo.sid).isEmpty
               && undo.store.looseTodayTabs(undo.sid).map(\.id) == [new.id] + original,
               "successful empty output preserves the previous grouping undo and exact loose order")

    }

    private static func settingsOffOn() async {
        for completed in [false, true] {
            let f = Fixture()
            let old = f.service.tidy(f.sid, store: f.store)
            await f.generator.waitFor(1)
            if completed { f.generator.success(1); await old?.value }
            // Actual settings property observer must invalidate in this actor turn.
            f.store.settings.tidyTabs = false
            f.store.settings.tidyTabs = true
            expect(!f.store.tidyingSpaces.contains(f.sid) && f.clock.pendingCount == 0 && (completed || old?.isCancelled == true),
                   "same-turn settings off/on synchronously invalidates pending or completed authority")
            let current = f.service.tidy(f.sid, store: f.store)
            expect(current != nil, "re-enabling permits fresh eligible work immediately")
            await f.generator.waitFor(2)
            if !completed { f.generator.success(1, proposals: [.init(name: "Stale", tabs: [0, 1])]); await old?.value }
            f.clock.fireCancelled()
            expect(f.store.tidyingSpaces.contains(f.sid) && f.store.tidiedTabs[f.sid] == nil && f.store.tabGroups(in: f.sid).isEmpty,
                   "an old provider or queued timer cannot apply or clear a newer request's broom")
            f.generator.success(2, proposals: [.init(name: "Current", tabs: [0, 1])])
            await current?.value
            f.clock.advance(by: TidyTabs.minimumRun)
            expect(f.store.tabGroups(in: f.sid).first?.title == "Current" && !f.store.tidyingSpaces.contains(f.sid),
                   "only the current token applies after settings re-enable")
        }
    }

    private static func availabilityChanges() async {
        for completed in [false, true] {
            let f = Fixture()
            let task = f.service.tidy(f.sid, store: f.store)
            await f.generator.waitFor(1)
            if completed { f.generator.success(1); await task?.value }
            f.available.value = false
            if !completed { f.generator.success(1); await task?.value }
            f.clock.advance(by: TidyTabs.minimumRun)
            expect(f.store.tidiedTabs[f.sid] == nil && f.store.tabGroups(in: f.sid).isEmpty && !f.store.tidyingSpaces.contains(f.sid),
                   "fresh model eligibility rejects \(completed ? "delayed" : "pending") application without a refresh notification")
        }
        for completed in [false, true] {
            setenv("CRA_TIDY_FAKE_MODEL", completed ? "1" : "off", 1)
            let f = Fixture() // First variant keeps cached status off while fresh eligibility returns.
            setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
            let task = f.service.tidy(f.sid, store: f.store)
            await f.generator.waitFor(1)
            if completed { f.generator.success(1); await task?.value }
            setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
            f.service.refresh()
            setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
            f.service.refresh()
            expect((completed || task?.isCancelled == true) && !f.store.tidyingSpaces.contains(f.sid) && f.clock.pendingCount == 0,
                   "real refresh synchronously invalidates same-turn unavailable/available, including cached-off status")
            if !completed { f.generator.success(1, proposals: [.init(name: "Stale", tabs: [0])]); await task?.value }
            f.clock.fireCancelled()
            f.clock.advance(by: TidyTabs.minimumRun)
            expect(f.store.tidiedTabs[f.sid] == nil && f.store.tabGroups(in: f.sid).isEmpty,
                   "observed off/on cannot revive an ignoring provider or scheduled outcome")
        }
        let f = Fixture(useFreshModel: true)
        let task = f.service.tidy(f.sid, store: f.store)
        await f.generator.waitFor(1)
        f.generator.success(1, proposals: [.init(name: "Unavailable", tabs: [0])])
        await task?.value
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        expect(f.service.modelAvailable && !f.service.currentModelAvailable, "actual fresh status can precede the cached available UI status")
        f.clock.advance(by: TidyTabs.minimumRun)
        expect(f.store.tidiedTabs[f.sid] == nil && f.store.tabGroups(in: f.sid).isEmpty
               && f.service.tidy(f.sid, store: f.store) == nil,
               "production default fresh eligibility guards both delayed apply and public entry")
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
    }

    private static func removedSpace() async {
        for kind in ["delete", "replace", "blank"] {
            let f = Fixture()
            var sid = f.sid
            if kind == "blank" { sid = f.store.addBlankWindow(frame: nil).focusedSpaceID!; populate(f.store, sid: sid, count: 6) }
            let task = f.service.tidy(sid, store: f.store)
            await f.generator.waitFor(1)
            let document = f.store.document
            if kind == "delete" { f.store.deleteSpace(sid) }
            else if kind == "replace" { f.store.replace(document: document) }
            else { f.store.removeWindow(f.store.prefs.windows.last!.id) }
            expect(task?.isCancelled == true && !f.store.tidyingSpaces.contains(sid),
                   "\(kind) space lifetime synchronously cancels authority and clears its running effect")
            let after = f.store.document
            f.generator.success(1, proposals: [.init(name: "Stale", tabs: [0, 1])])
            await task?.value
            f.clock.fireCancelled()
            f.clock.advance(by: TidyTabs.minimumRun)
            expect(f.store.document == after && f.store.tidiedTabs[sid] == nil && f.store.integrityProblems().isEmpty,
                   "\(kind) space completion cannot revive stale groups or considered IDs")
        }
        let f = Fixture()
        let task = f.service.tidy(f.sid, store: f.store)
        await f.generator.waitFor(1)
        let other = f.store.createSpace(title: "Other focus", emoji: "🪟")
        f.store.focusSpace(other.id)
        let extraWindow = f.store.addWindow(spaceID: f.sid, frame: nil)
        f.store.removeWindow(extraWindow.id)
        expect(f.store.tidyingSpaces.contains(f.sid) && task?.isCancelled == false,
               "closing one normal window leaves valid space-scoped work alive")
        f.generator.success(1, proposals: [.init(name: "Original", tabs: [0])])
        await task?.value
        f.clock.advance(by: TidyTabs.minimumRun)
        expect(f.store.tabGroups(in: f.sid).first?.title == "Original" && f.store.tabGroups(in: other.id).isEmpty,
               "switching focus alone preserves valid space-scoped work")
    }

    private static func independentTargets() async {
        let f = Fixture()
        let first = f.service.tidy(f.sid, store: f.store)
        expect(f.service.tidy(f.sid, store: f.store) == nil && f.store.tidyingSpaces.contains(f.sid), "duplicate clicks share the existing target request")
        await f.generator.waitFor(1)
        let secondClock = Clock(), second = SidebarStore(clock: secondClock)
        second.replace(document: f.store.document)
        wire(second, service: f.service)
        let independent = f.service.tidy(f.sid, store: second)
        expect(independent != nil, "identical space UUIDs in distinct stores have independent request authority")
        await f.generator.waitFor(2)
        f.generator.success(1, proposals: [.init(name: "First store", tabs: [0])])
        await first?.value
        f.clock.advance(by: TidyTabs.minimumRun)
        expect(f.store.tabGroups(in: f.sid).first?.title == "First store" && second.tabGroups(in: f.sid).isEmpty
               && second.tidyingSpaces.contains(f.sid), "one store's completion cannot mutate or clear another store")
        f.store.settings.tidyTabs = false
        f.store.settings.tidyTabs = true
        expect(second.tidyingSpaces.contains(f.sid) && independent?.isCancelled == false,
               "one store's settings invalidation does not cancel another store's request")
        f.generator.success(2, proposals: [.init(name: "Second store", tabs: [0])])
        await independent?.value
        secondClock.advance(by: TidyTabs.minimumRun)
        expect(second.tabGroups(in: f.sid).first?.title == "Second store", "the second store applies through its own clock and tree")
    }

    private static func cancelledTask() async {
        let f = Fixture()
        let task = f.service.tidy(f.sid, store: f.store)
        await f.generator.waitFor(1)
        task?.cancel()
        await idle(f.store, sid: f.sid)
        expect(f.store.canTidy(f.sid) && f.store.tidiedTabs[f.sid] == nil,
               "returned task cancellation clears animation and preserves retry before the provider cooperates")
        f.generator.success(1, proposals: [.init(name: "Cancelled", tabs: [0])])
        await task?.value
        f.clock.advance(by: TidyTabs.minimumRun)
        expect(f.store.tabGroups(in: f.sid).isEmpty && f.store.tidiedTabs[f.sid] == nil,
               "a cancellation-ignoring provider cannot apply after task cancellation")
    }

    private static func ownerLifetimes() async {
        let clock = Clock(), generator = Generator()
        var store: SidebarStore? = SidebarStore(clock: clock)
        let sid = store!.createSpace(title: "Weak owner", emoji: "🪶").id
        store!.settings.tidyTabs = true
        populate(store!, sid: sid, count: 6)
        let service = TidyTabsService(generate: { try await generator.next($0) }, modelAvailable: { true })
        let task = service.tidy(sid, store: store!)
        await generator.waitFor(1)
        weak var weakStore = store
        store = nil
        expect(weakStore == nil, "pending generation does not retain its store owner")
        generator.success(1, proposals: [.init(name: "Gone", tabs: [0])])
        await task?.value
        expect(clock.pendingCount == 0, "an ownerless result cannot schedule a presentation or retain a delay")

        let keptStore = SidebarStore(clock: clock)
        let keptSID = keptStore.createSpace(title: "Service teardown", emoji: "🪶").id
        keptStore.settings.tidyTabs = true
        populate(keptStore, sid: keptSID, count: 6)
        var transient: TidyTabsService? = TidyTabsService(generate: { try await generator.next($0) }, modelAvailable: { true })
        let pending = transient!.tidy(keptSID, store: keptStore)
        await generator.waitFor(2)
        weak var weakService = transient
        transient = nil
        await idle(keptStore, sid: keptSID)
        expect(weakService == nil && pending?.isCancelled == true && keptStore.canTidy(keptSID),
               "service teardown releases itself, cancels work and clears the real store's animation")
        generator.success(2, proposals: [.init(name: "Gone", tabs: [0])])
        await pending?.value
        expect(keptStore.tabGroups(in: keptSID).isEmpty && keptStore.tidiedTabs[keptSID] == nil,
               "late teardown delivery cannot mutate the surviving store")
    }

    private static func fittedConvergence() async {
        let f = Fixture(count: 75)
        let all = Set(f.store.looseTodayTabs(f.sid).map(\.id)), before = f.store.document
        var considered: Set<UUID> = [], index = 0
        while f.store.canTidy(f.sid), index < 80 {
            let task = f.service.tidy(f.sid, store: f.store)
            index += 1
            await f.generator.waitFor(index)
            let input = f.generator.requests[index - 1], fitted = input.reduced() ?? input
            expect(input.tabs.count <= TidyTabs.maximumTabs && !considered.contains(input.tabIDs[0]),
                   "every fitted service request preserves unseen-first capped priority")
            f.generator.success(index, request: fitted)
            await task?.value
            f.clock.advance(by: TidyTabs.minimumRun)
            considered.formUnion(fitted.tabIDs)
            expect(f.store.tidiedTabs[f.sid] == considered && f.store.document == before,
                   "service records the adapter's fitted IDs without consuming the original maximum prefix")
        }
        expect(considered == all && !f.store.canTidy(f.sid) && f.store.tidyingSpaces.isEmpty,
               "repeated fitted successful-empty runs converge across more than sixty tabs")
    }

    @MainActor private final class Availability { var value = true }
    @MainActor private final class Fixture {
        let clock = Clock()
        let store: SidebarStore
        let generator = Generator(), available = Availability()
        let service: TidyTabsService
        let sid: UUID
        init(count: Int = 6, useFreshModel: Bool = false) {
            store = SidebarStore(clock: clock)
            store.settings.tidyTabs = true
            sid = store.createSpace(title: "Tidy lifecycle", emoji: "🧹").id
            populate(store, sid: sid, count: count)
            let generator = self.generator, available = self.available
            let eligibility: (@MainActor () -> Bool)?
            if useFreshModel { eligibility = nil } else { eligibility = { available.value } }
            service = TidyTabsService(generate: { try await generator.next($0) }, modelAvailable: eligibility)
            wire(store, service: service)
        }
    }

    /// Wraps the real manual scheduler and can deliver an already-queued cancelled callback.
    @MainActor private final class Clock: Scheduler {
        private let manual = ManualScheduler(now: Date(timeIntervalSince1970: 1_700_000_000))
        private var callbacks: [(ScheduledWork, @MainActor () -> Void)] = []
        var now: Date { manual.now }
        var pendingCount: Int { manual.pendingCount }
        func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
            let handle = manual.after(delay, work)
            callbacks.append((handle, work))
            return handle
        }
        func every(_ interval: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork { manual.every(interval, work) }
        func advance(by amount: TimeInterval) { manual.advance(by: amount) }
        func fireCancelled() { for (handle, work) in callbacks where handle.isCancelled { work() } }
    }

    /// Deliberately ignores cancellation until a controlled reply is released.
    @MainActor private final class Generator {
        private(set) var requests: [TidyTabs.Request] = []
        private var replies: [Int: CheckedContinuation<TidyTabsModel.Answer, Error>] = [:]
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        func next(_ request: TidyTabs.Request) async throws -> TidyTabsModel.Answer {
            requests.append(request)
            let index = requests.count
            return try await withCheckedThrowingContinuation { reply in
                replies[index] = reply
                waiters.removeValue(forKey: index)?.resume()
            }
        }
        func waitFor(_ index: Int) async {
            if replies[index] != nil { return }
            await withCheckedContinuation { waiters[index] = $0 }
        }
        func success(_ index: Int, request: TidyTabs.Request? = nil, proposals: [TidyTabs.Proposal] = []) {
            resolve(index, with: .success(.init(request: request ?? requests[index - 1], proposals: proposals)))
        }
        func resolve(_ index: Int, with result: Result<TidyTabsModel.Answer, Error>) {
            guard let reply = replies.removeValue(forKey: index) else { fatalError("missing request") }
            reply.resume(with: result)
        }
    }

    private static func populate(_ store: SidebarStore, sid: UUID, count: Int) {
        for n in 0..<count { store.createTab(url: "https://example.org/\(n)", title: "Tab \(n)", in: sid, select: false) }
    }
    private static func wire(_ store: SidebarStore, service: TidyTabsService) {
        store.tidyTabsChanged = { [weak store, weak service] enabled in if !enabled, let store { service?.cancelAll(store: store) } }
        store.tidyTabsSpaceRemoved = { [weak store, weak service] sid in if let store { service?.cancel(sid, store: store) } }
    }
    private static func idle(_ store: SidebarStore, sid: UUID) async {
        await withCheckedContinuation { done in
            var continuation: CheckedContinuation<Void, Never>? = done
            observeChanges(of: { [weak store] in store?.tidyingSpaces.contains(sid) == true }) { running in
                if !running { let ready = continuation; continuation = nil; ready?.resume() }
            }
        }
    }
    private static func expect(_ value: Bool, _ message: String) {
        checks += 1
        guard value else { print("FAIL: \(message)"); exit(1) }
    }
}
