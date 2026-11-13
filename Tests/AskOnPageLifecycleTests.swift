import AppKit
import Observation

@main
@MainActor
enum AskOnPageLifecycleTests {
    private static var checks = 0
    private static let page = AskOnPagePrompt.Page(url: "https://example.test/article", title: "Synthetic article",
        text: "The synthetic observatory opens at 09:30 and closes at 18:00. Its entrance is on Elm Street.")
    private static let answer = AskOnPage.Draft(excerpts: ["The synthetic observatory opens at 09:30 and closes at 18:00."],
        answer: "It opens at 09:30.", keyAnswer: "09:30")

    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("cra-ask-lifecycle-\(UUID().uuidString)")
        setenv("CRA_DATA_DIR", data.path, 1)
        setenv("CRA_ARC_DIR", data.appendingPathComponent("NoArc").path, 1)
        let original = ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"]
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1) // Process-local resolver/adapter seam; no real inference.
        _ = TidyTabsService.fakeModel
        TidyTabsService.shared.refresh()
        defer {
            if let original { setenv("CRA_TIDY_FAKE_MODEL", original, 1) } else { unsetenv("CRA_TIDY_FAKE_MODEL") }
            try? FileManager.default.removeItem(at: data)
        }
        if let edge = CommandLine.arguments.first(where: { $0.hasPrefix("--profile-edge=") }) {
            await profileMutationPaths(only: String(edge.dropFirst("--profile-edge=".count)))
            print("Ask profile ownership: \(checks) checks passed")
            return
        }
        await profileMutationPaths()
        await quotesRespectRealEdges()
        await realStoreOffOn()
        await streamsAndStoreIdentity()
        await completedAndMasterReplacement()
        await realProfileOffOn()
        await actualAvailabilityEdges()
        await freshAvailabilityAtDelivery()
        await teardown()
        print("Ask real-store lifecycle: \(checks) checks passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    private static func store() -> SidebarStore {
        let store = SidebarStore(clock: ManualScheduler())
        store.settings.askOnPage = true
        return store
    }

    // promise: #393
    private static func profileMutationPaths(only: String? = nil) async {
        for edge in only.map({ [$0] }) ?? ["document", "favorite", "move", "subtree", "split", "update", "sharing", "delete"] {
            let store = store()
            let source = store.createSpace(title: "Profile source", emoji: "A")
            let destination = store.createSpace(title: "Profile target", emoji: "B")
            let profile = store.createProfile(name: "Synthetic profile B")
            store.setProfile(profile.id, forSpace: destination.id)
            let first = Window(store, space: source.id), neighbor = Window(store, space: source.id)
            let foreign = Window(store, space: destination.id)
            let tab = first.browsers.context!.tabID
            var moved = tab
            if edge == "favorite" || edge == "sharing" || edge == "delete" {
                store.setFavoritesShared(true)
                store.moveItem(tab, to: store.space(source.id)!.favoritesContainerID, index: nil)
            }
            if edge == "subtree" {
                let folder = store.createFolder(named: "Moving subtree", in: store.space(source.id)!.pinnedContainerID, index: nil)
                store.moveItem(tab, to: folder.id, index: nil)
                moved = folder.id
            }
            if edge == "delete" {
                // An old-profile favorite can remain open after no space uses that profile.
                store.setProfile(nil, forSpace: destination.id)
                store.moveFavorite(tab, toProfile: profile.id)
            }
            let originalParent = store.item(moved)!.parentID!
            let original = store.document
            await first.start("Old \(edge)"); await neighbor.start("Neighbor \(edge)"); await foreign.start("Foreign \(edge)")
            let neighborID = neighbor.service.current?.id, foreignID = foreign.service.current?.id
            switch edge {
            case "document":
                var changed = original
                changed.spaces[changed.spaces.firstIndex(where: { $0.id == source.id })!].profileID = profile.id
                store.replace(document: changed)
                store.replace(document: original)
            case "favorite":
                store.moveFavorite(tab, toProfile: profile.id)
                expect(store.profileID(item: tab) == profile.id, "favorite must actually enter profile B")
                store.moveFavorite(tab, toProfile: nil)
            case "move", "subtree":
                store.moveItem(moved, to: store.space(destination.id)!.todayContainerID, index: nil)
                expect(store.profileID(item: tab) == profile.id, "moved subtree must actually enter profile B")
                store.moveItem(tab, to: originalParent, index: nil)
            case "split":
                _ = store.createSplit(with: [foreign.browsers.context!.tabID, tab], at: foreign.browsers.context!.tabID)
                expect(store.profileID(item: tab) == profile.id, "split composition must actually enter profile B")
                store.moveItem(tab, to: originalParent, index: nil)
            case "update":
                var changed = store.space(source.id)!
                changed.profileID = profile.id
                store.updateSpace(changed)
                store.updateSpace(original.spaces.first(where: { $0.id == source.id })!)
            case "sharing":
                store.setFavoritesShared(false)
                store.setFavoritesShared(true)
            default:
                store.deleteProfile(profile.id)
            }
            if edge == "sharing" {
                expect(first.service.current != nil, "same-profile favorites sharing must preserve the current owner")
                first.service.clear()
            } else {
                expect(first.service.current == nil && first.service.messages.isEmpty,
                    "actual \(edge) profile A/B/A must revoke old authority before UI refresh")
            }
            let wholeSpace = edge == "document" || edge == "update"
            expect(wholeSpace ? neighbor.service.current == nil : neighbor.service.current?.id == neighborID,
                "\(edge) must invalidate only owners whose tab or space profile actually changed")
            expect(foreign.service.current?.id == foreignID,
                "\(edge) must preserve an unaffected window/space of the same store")
            first.provider.emit(1, answer)
            first.provider.finish(1, draft: answer)
            if edge != "delete" {
                await first.start("Current \(edge)")
                first.provider.finish(2, draft: answer); await settled(first.service)
                expect(first.service.messages.map(\.question) == ["Current \(edge)"],
                    "late old \(edge) output cannot return after a fresh request")
            }
            neighbor.service.clear(); neighbor.provider.finish(1, draft: answer)
            foreign.service.clear(); foreign.provider.finish(1, draft: answer)
        }
    }

    // promise: #393
    private static func quotesRespectRealEdges() async {
        let shared = store(), other = store()
        let first = Window(shared), second = Window(shared), foreign = Window(other)
        for window in [first, second, foreign] {
            await window.start("Completed quote")
            window.provider.finish(1, draft: answer); await settled(window.service)
            window.service.findQuote(messageID: window.service.messages[0].id, index: 0)
            expect(window.service.quoteNavigation?.status == .loading, "a real completed owner begins its specific quote operation")
        }
        let oldFirst = first.browsers.quotePending!, oldSecond = second.browsers.quotePending!
        let foreignID = foreign.service.quoteNavigation?.request.id
        shared.settings.askOnPage = false; shared.settings.askOnPage = true
        expect(first.service.quoteNavigation == nil && second.service.quoteNavigation == nil && first.service.messages.isEmpty,
            "actual same-turn store off/on synchronously revokes both pending quote statuses and source authority")
        oldFirst(true); oldSecond(true)
        expect(first.service.quoteNavigation == nil && second.service.quoteNavigation == nil,
            "cancellation-ignoring old DOM effects cannot return found status after off/on")
        expect(foreign.service.quoteNavigation?.request.id == foreignID, "another store's quote operation keeps its owner")
        foreign.browsers.quotePending?(true)
        expect(foreign.service.quoteNavigation?.status == .found, "the unaffected exact operation can complete")
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1); TidyTabsService.shared.refresh()
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1); TidyTabsService.shared.refresh()
        expect(foreign.service.quoteNavigation == nil && foreign.service.messages.isEmpty,
            "actual model unavailability revokes completed quote status before availability returns")
    }

    // promise: #393
    private static func realStoreOffOn() async {
        let store = store(), first = Window(store), second = Window(store)
        first.service.ask("First pending read", language: "English")
        second.service.ask("Second pending read", language: "English")
        let oldFirstRead = first.browsers.pending!, oldSecondRead = second.browsers.pending!
        store.settings.askOnPage = false
        store.settings.askOnPage = true
        expect(first.service.current == nil && second.service.current == nil,
            "real store same-turn off/on must synchronously clear both window owners before any actor hop")
        oldFirstRead(page); oldSecondRead(page)
        expect(first.service.phase == .idle && second.service.phase == .idle,
            "late old extraction cannot restart either window after off/on")
    }

    // promise: #393
    private static func streamsAndStoreIdentity() async {
        let shared = store(), other = store()
        let first = Window(shared), second = Window(shared), foreign = Window(other)
        await first.start("Old first"); await second.start("Old second"); await foreign.start("Other store")
        first.provider.emit(1, answer)
        let foreignID = foreign.service.current?.id
        first.provider.onCancel = { [weak service = first.service] in
            expect(service?.current == nil && service?.messages.isEmpty == true,
                "request and source authority must be gone before cancellation handlers run")
        }
        first.browsers.prepareQuote("A quote")
        shared.settings.askOnPage = false
        expect(first.service.current == nil && second.service.current == nil && first.browsers.selectionFindState.request == nil,
            "disable clears both owners and quote-purpose authority inline")
        expect(foreign.service.current?.id == foreignID,
            "disable notifications are filtered by the exact store object")
        shared.settings.askOnPage = true
        first.provider.emit(1, .init(answer: "Obsolete partial"))
        first.provider.finish(1, error: .refused)
        second.provider.finish(1, draft: answer)
        await first.start("Current first")
        first.provider.finish(2, draft: answer)
        await settled(first.service)
        expect(first.service.messages.map(\.question) == ["Current first"] && first.service.current == nil,
            "late old partial/error/final cannot replace new request history")
        expect(second.service.current == nil && second.service.messages.isEmpty,
            "a cancellation-ignoring old final cannot repopulate the second window")
        foreign.service.clear(); foreign.provider.finish(1, draft: answer)
    }

    // promise: #393
    private static func completedAndMasterReplacement() async {
        let store = store(), first = Window(store), second = Window(store)
        await first.start("Completed history")
        first.provider.finish(1, draft: answer)
        await settled(first.service)
        expect(first.service.messages.first?.answer?.hasVerifiedQuote == true && first.service.messages.first?.source.isEmpty == false,
            "the completed owner holds actual native citation and fitted source before invalidation")
        second.service.ask("Pending beside history", language: "English")
        store.settings = AppSettings()
        expect(first.service.messages.isEmpty && first.service.current == nil && second.service.current == nil,
            "whole-settings replacement clears completed source/history and pending work inline")
        applyProductionMaxSwitch(store, true)
        first.service.ask("Master switch pending", language: "English")
        applyProductionMaxSwitch(store, false)
        applyProductionMaxSwitch(store, true)
        expect(first.service.current == nil && first.service.messages.isEmpty,
            "the actual six-feature master switch write sequence cannot revive an old request")
        expect(store.settings.tidyTabs && store.settings.tidyTabTitles && store.settings.askOnPage && store.settings.instantLinks,
            "Ask invalidation preserves the master switch's other feature values")
    }

    // promise: #393
    private static func realProfileOffOn() async {
        let store = store()
        let changed = store.createSpace(title: "Changed profile", emoji: "A")
        let unchanged = store.createSpace(title: "Other profile", emoji: "B")
        let first = Window(store, space: changed.id), second = Window(store, space: changed.id)
        let foreign = Window(store, space: unchanged.id)
        await first.start("Old profile first"); await second.start("Old profile second"); await foreign.start("Unaffected space")
        let foreignID = foreign.service.current?.id
        let profile = store.createProfile(name: "Synthetic Ask profile")
        store.setProfile(profile.id, forSpace: changed.id)
        store.setProfile(nil, forSpace: changed.id)
        expect(first.service.current == nil && second.service.current == nil,
            "actual same-turn profile A/B/A revokes both affected window owners before UI refresh")
        expect(foreign.service.current?.id == foreignID,
            "profile ownership notifications preserve another space of the same store")
        first.provider.emit(1, answer); first.provider.finish(1, draft: answer)
        second.provider.finish(1, error: .refused)
        await first.start("Current profile")
        first.provider.finish(2, draft: answer); await settled(first.service)
        expect(first.service.messages.map(\.question) == ["Current profile"] && second.service.messages.isEmpty,
            "old cancellation-ignoring profile deliveries cannot return after the profile is restored")
        foreign.service.clear(); foreign.provider.finish(1, draft: answer)
    }

    // promise: #393
    private static func actualAvailabilityEdges() async {
        let store = store(), first = Window(store), second = Window(store)
        await first.start("Availability first"); await second.start("Availability second")
        first.provider.finish(1, draft: answer); await settled(first.service)
        let model = TidyTabsService.shared
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        model.refresh()
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        model.refresh()
        expect(first.service.messages.isEmpty && second.service.current == nil,
            "actual model off/on refresh clears completed and running owners synchronously")
        second.provider.emit(1, answer); second.provider.finish(1, draft: answer)
        expect(first.service.current == nil && second.service.messages.isEmpty,
            "available again does not restore old model-generation authority")
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1); model.refresh()
        // Deliberately independent provider flag proves repeated cached-off refresh still emits the edge.
        let injected = Window(store, available: { true })
        await injected.start("Pending while UI cache is off")
        model.refresh()
        expect(injected.service.current == nil && injected.service.messages.isEmpty,
            "repeated cached-unavailable refresh synchronously clears every owner")
        injected.provider.finish(1, draft: answer)
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1); model.refresh()
    }

    // promise: #393
    private static func freshAvailabilityAtDelivery() async {
        let store = store(), window = Window(store)
        await window.start("Fresh availability")
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1) // No refresh or notification.
        expect(TidyTabsService.shared.modelAvailable && !TidyTabsService.shared.currentModelAvailable,
            "fresh resolver can observe model loss before the cached UI status changes")
        window.provider.emit(1, answer)
        expect(window.service.current == nil && window.service.messages.isEmpty,
            "an unavailable partial delivery clears old source authority instead of merely dropping text")
        expect(!window.service.ask("Unavailable request", language: "English"),
            "fresh production availability prevents extraction while the cached status still says available")
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        window.provider.finish(1, draft: answer)
        await window.start("Fresh new request")
        window.provider.finish(2, draft: answer); await settled(window.service)
        expect(window.service.messages.map(\.question) == ["Fresh new request"],
            "an unrefreshed availability recovery cannot accept the old final")
    }

    private static func teardown() async {
        let store = store()
        var window: Window? = Window(store)
        await window!.start("Closing window")
        let provider = window!.provider
        weak var service: AskOnPageService?
        service = window!.service
        window = nil
        expect(service == nil, "notification callbacks do not retain the per-window service")
        store.settings.askOnPage = false
        TidyTabsService.shared.refresh()
        provider.emit(1, answer); provider.finish(1, draft: answer)
    }

    private static func settled(_ service: AskOnPageService) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            @MainActor func track() {
                if !service.isLoading { done.resume(); return }
                withObservationTracking { _ = service.isLoading } onChange: { Task { @MainActor in track() } }
            }
            track()
        }
    }

    @MainActor
    private final class Window {
        let browsers = BrowserManager()
        let provider = Provider()
        let service: AskOnPageService
        init(_ store: SidebarStore, space: UUID? = nil, available: (@MainActor () -> Bool)? = nil) {
            let space = space ?? store.focusedSpaceID(window: nil)
            let tab = store.createTab(url: "https://example.test/article", in: space, select: false)
            browsers.context = AskOnPageContext(tabID: tab.id, spaceID: space)
            let provider = self.provider
            if let available {
                service = AskOnPageService(browsers: browsers, settingsStore: store, enabled: { store.settings.askOnPage }, available: available,
                    clock: ManualScheduler(), countTokens: { ($0.utf8.count + $1.utf8.count + 3) / 4 }, generate: provider.stream)
            } else {
                service = AskOnPageService(browsers: browsers, settingsStore: store, enabled: { store.settings.askOnPage },
                    clock: ManualScheduler(), countTokens: { ($0.utf8.count + $1.utf8.count + 3) / 4 }, generate: provider.stream)
            }
        }
        func start(_ question: String) async {
            let number = provider.count + 1
            expect(service.ask(question, language: "English"), "the current eligible owner accepts \(question)")
            browsers.reply(page)
            await provider.started(number)
        }
    }

    @MainActor
    private final class Provider {
        private(set) var count = 0
        var onCancel: (@MainActor () -> Void)?
        private var updates: [Int: @MainActor (AskOnPage.Draft) -> Void] = [:]
        private var replies: [Int: CheckedContinuation<AskOnPage.Draft, Error>] = [:]
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        func stream(_ fitted: AskOnPagePrompt.Fitted, update: @escaping @MainActor (AskOnPage.Draft) -> Void) async throws -> AskOnPage.Draft {
            count += 1
            let number = count
            updates[number] = update
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { done in
                    replies[number] = done
                    waiters.removeValue(forKey: number)?.resume()
                }
            } onCancel: {
                MainActor.assumeIsolated { self.onCancel?() }
            }
        }
        func started(_ number: Int) async {
            if replies[number] != nil { return }
            await withCheckedContinuation { waiters[number] = $0 }
        }
        func emit(_ number: Int, _ draft: AskOnPage.Draft) { updates[number]?(draft) }
        func finish(_ number: Int, draft: AskOnPage.Draft? = nil, error: AskOnPageService.Failure? = nil) {
            guard let done = replies.removeValue(forKey: number) else { fatalError("missing provider result") }
            if let error { done.resume(throwing: error) } else { done.resume(returning: draft!) }
        }
    }
}
