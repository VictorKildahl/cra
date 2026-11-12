import AppKit

/// Real service, store, models and clock; only generation and native layout lookup are controlled.
@main
enum TidyTitlesServiceTests {
    private static var checks = 0

    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("cra-tidy-titles-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: data) }
        setenv("CRA_DATA_DIR", data.path, 1)
        setenv("CRA_ARC_DIR", data.appendingPathComponent("NoArcProfile").path, 1)
        if CommandLine.arguments.dropFirst().first == "owner" {
            await staleCompletionCannotRemoveNewRequest()
        } else {
            await cancelledBeforeGeneration()
            await offOnRejectsLateCompletion()
            await staleCompletionCannotRemoveNewRequest()
            await scheduledRevealAndExpiry()
            await cancelledExpiryCannotClearNewEffect()
            await completionGuards()
            await currentOriginMetrics()
            await teardown()
        }
        print("Tidy titles service: \(checks) checks passed")
    }

    @MainActor
    private static func cancelledBeforeGeneration() async {
        let f = Fixture()
        f.store.pinTab(f.id)
        f.store.settings.tidyTabTitles = false
        await turn()
        f.clock.advance(by: 10)
        expect(f.generator.count == 0 && f.store.item(f.id)?.title == nil && f.service!.effects.isEmpty,
               "a request cancelled before its task starts cannot begin generation or rename")
    }

    @MainActor
    private static func offOnRejectsLateCompletion() async {
        let f = Fixture()
        f.store.pinTab(f.id)
        await f.generator.waitFor(1)
        f.store.settings.tidyTabTitles = false
        f.store.settings.tidyTabTitles = true
        f.generator.resolve(1, with: "Stale Name")
        await turn()
        f.clock.advance(by: 10)
        await turn()
        expect(f.store.item(f.id)?.title == nil && f.service!.effects.isEmpty,
               "disabling then re-enabling must invalidate an uncooperative model's old answer")
    }

    @MainActor
    private static func staleCompletionCannotRemoveNewRequest() async {
        let f = Fixture()
        f.store.pinTab(f.id)
        await f.generator.waitFor(1)
        f.store.settings.tidyTabTitles = false
        f.store.settings.tidyTabTitles = true
        f.store.unpinTab(f.id)
        f.store.pinTab(f.id)
        await f.generator.waitFor(2)
        f.service!.tabPinned(f.id, store: f.store)
        f.generator.resolve(1, with: "Old Name")
        await turn()
        f.service!.tabPinned(f.id, store: f.store)
        f.generator.resolve(2, with: "New Name")
        await turn()
        f.clock.advance(by: 1)
        await turn()
        expect(f.store.item(f.id)?.title == "New Name" && f.service!.effects[f.id] != nil,
               "old cancellation/cleanup cannot remove or apply over the newer request")
        expect(f.generator.count == 2 && f.store.item(f.id)?.title == "New Name",
               "duplicate pin notifications share the same request and produce one current name")
        f.service!.cancelAll()
    }

    @MainActor
    private static func scheduledRevealAndExpiry() async {
        let f = Fixture()
        f.store.pinTab(f.id)
        await f.generator.waitFor(1)
        f.generator.resolve(1, with: "First Name")
        await turn()
        f.clock.advance(by: 0.99)
        expect(f.store.item(f.id)?.title == nil && f.service!.effects.isEmpty,
               "a quick answer waits for the measured minimum reveal delay")
        f.store.settings.tidyTabTitles = false
        f.clock.advance(by: 1)
        expect(f.store.item(f.id)?.title == nil && f.service!.effects.isEmpty,
               "opt-out cancels a scheduled reveal before it can rename")

        f.store.settings.tidyTabTitles = true
        f.store.unpinTab(f.id)
        f.store.pinTab(f.id)
        await f.generator.waitFor(2)
        f.generator.resolve(2, with: "Second Name")
        await turn()
        f.clock.advance(by: 1)
        let firstEffect = f.service!.effects[f.id]
        expect(f.store.item(f.id)?.title == "Second Name" && firstEffect?.start == f.clock.now,
               "the new request applies on the injected clock and starts its own effect")
        f.clock.advance(by: TidyTitlesService.subtitleShown - 0.01)
        expect(f.service!.effects[f.id] == firstEffect, "the subtitle remains until its expiry boundary")
        f.clock.advance(by: 0.01)
        expect(f.service!.effects[f.id] == nil && f.store.item(f.id)?.title == "Second Name",
               "expiry clears the effect but preserves the persisted custom name")

        f.store.rename(f.id, to: nil)
        f.store.unpinTab(f.id)
        f.store.pinTab(f.id)
        await f.generator.waitFor(3)
        f.generator.resolve(3, with: "Third Name")
        await turn()
        f.clock.advance(by: 1)
        f.store.settings.tidyTabTitles = false
        expect(f.service!.effects.isEmpty && f.store.item(f.id)?.title == "Third Name",
               "disabling clears active hints without undoing an already applied name")
    }

    @MainActor
    private static func cancelledExpiryCannotClearNewEffect() async {
        let f = Fixture()
        f.store.pinTab(f.id)
        await f.generator.waitFor(1)
        f.generator.resolve(1, with: "First Name")
        await turn()
        f.clock.advance(by: 1)
        f.store.settings.tidyTabTitles = false
        f.store.settings.tidyTabTitles = true
        f.store.rename(f.id, to: nil)
        f.store.unpinTab(f.id)
        f.store.pinTab(f.id)
        await f.generator.waitFor(2)
        f.generator.resolve(2, with: "Second Name")
        await turn()
        f.clock.advance(by: 1)
        let effect = f.service!.effects[f.id]
        f.clock.advance(by: TidyTitlesService.subtitleShown - 1)
        expect(f.store.item(f.id)?.title == "Second Name" && effect != nil && f.service!.effects[f.id] == effect,
               "the cancelled older expiry cannot clear a newer request's effect")
        f.clock.advance(by: 1)
        expect(f.service!.effects[f.id] == nil, "the newer effect expires on its own clock boundary")
    }

    @MainActor
    private static func completionGuards() async {
        for mutation in ["manual", "unpin", "delete", "title", "home", "navigate", "other-setting", "failure"] {
            let f = Fixture()
            f.store.pinTab(f.id)
            await f.generator.waitFor(1)
            switch mutation {
            case "manual": f.store.rename(f.id, to: "Mine")
            case "unpin": f.store.unpinTab(f.id)
            case "delete": f.store.archiveTab(f.id, reason: .manual)
            case "title": f.store.updateTab(f.id, title: "Another page")
            case "home":
                f.store.updateTab(f.id, url: "https://example.org/new-home")
                f.store.setPinnedHomeToCurrent(f.id)
            case "navigate": f.store.updateTab(f.id, url: "https://example.org/away")
            case "other-setting": f.store.settings.tidyDownloads.toggle()
            default: break
            }
            f.generator.resolve(1, with: mutation == "failure" ? nil : "Generated Name")
            await turn()
            f.clock.advance(by: 1)
            await turn()
            let applies = mutation == "navigate" || mutation == "other-setting"
            let expected = applies ? "Generated Name" : mutation == "manual" ? "Mine" : nil
            expect(f.store.item(f.id)?.title == expected,
                   "completion respects \(mutation) while ordinary same-home navigation remains valid")
            expect((f.service!.effects[f.id] != nil) == applies,
                   "suppressed \(mutation) completion cannot create an effect")
            f.service!.cancelAll()
        }
    }

    @MainActor
    private static func currentOriginMetrics() async {
        let f = Fixture()
        f.label.frame.size.width = 30
        f.store.pinTab(f.id)
        await f.generator.waitFor(1)
        f.store.activeWindowID = UUID()
        f.label.frame.size.width = 500
        f.generator.resolve(1, answer: .init(filtered: "Specific informative title", rewritten: "Short"))
        await turn()
        f.clock.advance(by: 1)
        await turn()
        expect(f.store.item(f.id)?.title == "Specific informative title",
               "completion uses the resized originating row, not an early width or the later active window")
        f.service!.cancelAll()
    }

    @MainActor
    private static func teardown() async {
        let f = Fixture()
        f.store.pinTab(f.id)
        await f.generator.waitFor(1)
        weak var service = f.service
        f.service = nil
        await turn()
        expect(service == nil, "in-flight generation must not keep the service alive")
        f.generator.resolve(1, with: "Too Late")
        await turn()
        f.clock.advance(by: 10)
        expect(f.store.item(f.id)?.title == nil, "a destroyed service cannot apply a late answer")

        let scheduled = Fixture()
        scheduled.store.pinTab(scheduled.id)
        await scheduled.generator.waitFor(1)
        scheduled.generator.resolve(1, with: "Pending Reveal")
        await turn()
        scheduled.service = nil
        await turn()
        scheduled.clock.advance(by: 10)
        expect(scheduled.store.item(scheduled.id)?.title == nil,
               "destroying the service cancels its scheduled reveal")
    }

    @MainActor
    private final class Fixture {
        let clock = ManualScheduler(now: Date(timeIntervalSince1970: 1_700_000_000))
        let store: SidebarStore
        let generator = Generator()
        let label = NSTextField(labelWithString: "")
        var service: TidyTitlesService?
        let id: UUID

        init() {
            store = SidebarStore(clock: clock)
            store.settings.tidyTabTitles = true
            let space = store.createSpace(title: "Title test", emoji: "📌")
            id = store.createTab(url: "https://example.org/article", in: space.id, select: false).id
            store.updateTab(id, title: "Original article - Example")
            let origin = store.activeWindowID
            let label = self.label, id = self.id, generator = self.generator
            label.font = .systemFont(ofSize: 14)
            label.frame.size.width = 500
            service = TidyTitlesService(titleLayout: { item, window in
                item == id && window == origin ? TidyTitleLayout(label: label, inset: 2) : nil
            }, generate: { _, _ in await generator.next() }, modelAvailable: { true })
            store.tabPinned = { [weak service, weak store] id in
                if let store { service?.tabPinned(id, store: store) }
            }
            store.tidyTabTitlesChanged = { [weak service] enabled in if !enabled { service?.cancelAll() } }
        }
    }

    /// Deliberately ignores cancellation, as a model already returning an answer can do.
    @MainActor
    private final class Generator {
        private(set) var count = 0
        private var replies: [Int: CheckedContinuation<TidyTitles.Answer?, Never>] = [:]
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

        func next() async -> TidyTitles.Answer? {
            count += 1
            let index = count
            return await withCheckedContinuation { reply in
                replies[index] = reply
                waiters.removeValue(forKey: index)?.resume()
            }
        }

        func waitFor(_ index: Int) async {
            if replies[index] != nil { return }
            await withCheckedContinuation { waiters[index] = $0 }
        }

        func resolve(_ index: Int, with title: String?) {
            resolve(index, answer: title.map { .init(filtered: $0, rewritten: $0) })
        }

        func resolve(_ index: Int, answer: TidyTitles.Answer?) {
            guard let reply = replies.removeValue(forKey: index) else { fatalError("missing model request \(index)") }
            reply.resume(returning: answer)
        }
    }

    @MainActor
    private static func turn() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }
}
