import AppKit

@MainActor private final class PreviewGate<Value> {
    private var value: Value?
    private var waiting: CheckedContinuation<Value, Never>?
    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { waiting = $0 }
    }
    func resolve(_ value: Value) { self.value = value; waiting?.resume(returning: value); waiting = nil }
}

@MainActor private final class PreviewProvider {
    let entered = PreviewGate<Void>(), release = PreviewGate<LinkSummaryPrompt.Answer?>(), returned = PreviewGate<Void>()
    func answer(_ url: URL, _ content: LinkSummaryContent.Extracted, _ query: String?, _ language: String,
                _ partial: @escaping (LinkSummaryPrompt.Answer?) -> Void) async -> LinkSummaryPrompt.Answer? {
        entered.resolve(())
        let value = await release.wait() // Intentionally ignores task cancellation.
        returned.resolve(())
        return value
    }
}

@MainActor private final class PreviewHooksFixture {
    let clock = ManualScheduler()
    let store: SidebarStore
    let provider = PreviewProvider()
    let service: LinkSummaryService
    let controller: LinkSummaryPreviewController
    let parent: NSWindow
    let runtime = NSObject()
    let request = LinkSummaryRequest(link: URL(string: "https://example.com/story")!, profilePath: nil,
                                     httpsOnly: false, searchQuery: nil, language: "English")
    init(refresh: Bool = true) {
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        if refresh { TidyTabsService.shared.refresh() }
        store = SidebarStore(clock: clock)
        store.settings.fiveSecondPreviews = true
        let provider = provider
        service = LinkSummaryService(fetch: { .init(html: "<head><title>Synthetic</title></head><body>First meaningful paragraph. Second meaningful paragraph.</body>", url: $0.fetchURL) }, image: { _ in nil }, answer: provider.answer)
        controller = LinkSummaryPreviewController(clock: clock, service: service)
        controller.bindEligibility(to: store) // Actual production binding also called by AppDelegate.
        parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
    }
    func start() {
        let store = store, service = service
        controller.linkHoverChanged(.init(context: .init(request: request, page: URL(string: "https://news.ycombinator.com/"),
                                                         windowID: store.activeWindowID, tabID: UUID(), runtimeID: ObjectIdentifier(runtime), navigationRevision: 1),
                                          window: parent, theme: SpaceTheme.presets[0], shiftHeld: false,
                                          isCurrent: { store.settings.fiveSecondPreviews && service.isAvailable }, inspect: { [request] in
            $0(.init(rect: NSRect(x: -9800, y: -9500, width: 100, height: 16), arcLink: true, link: request.link))
        }))
        clock.advance(by: 1)
    }
    func finish() { controller.stop(); parent.orderOut(nil) }
}

/// Only the unused Tidy Tabs animation path requires this native UI value.
enum SidebarTidyMetrics { static let minimumRun: TimeInterval = 0.9 }

@main @MainActor enum LinkSummaryHooksTests {
    static let answer = LinkSummaryPrompt.Answer(blocked: false, quickSummary: "Synthetic current answer", details: [
        .init(label: "Cost", icon: "tag", info: "Twenty euros per visitor"), .init(label: "Access", icon: "figure.roll", info: "Step free entrance and elevators")
    ])
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-preview-hooks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("CRA_DATA_DIR", root.path, 1)
        // Freeze the fake-inference flag off before exercising real resolver environment states.
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        expect(!TidyTabsService.fakeModel, "this harness exercises actual resolver hooks, not fake availability")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if CommandLine.arguments.contains("--availability") {
            await unrefreshedAvailability()
            print("Link summary actual availability: \(checks) checks passed")
            return
        }
        if CommandLine.arguments.contains("--title") { await titleAvailability(); return }
        if CommandLine.arguments.contains("--image") { await imageAvailability(); return }
        await titleAvailability()
        await imageAvailability()
        await settingOffOn()
        await unrefreshedAvailability()
        await repeatedUnavailableRefresh()
        await disabledBeforeFetch()
        print("Link summary actual store/model hooks: \(checks) checks passed")
    }
    static func titleAvailability() async {
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        TidyTabsService.shared.refresh()
        let entered = PreviewGate<Void>(), release = PreviewGate<LinkSummaryFetch.Page?>()
        var first = true
        let request = LinkSummaryRequest(link: URL(string: "https://example.com/title")!, profilePath: nil, httpsOnly: false, searchQuery: nil, language: "English")
        let service = LinkSummaryService(fetch: { request in
            if first { first = false; entered.resolve(()); return await release.wait() }
            return .init(html: "<title>Fresh title</title>", url: request.fetchURL)
        })
        let task = Task { await service.title(request) }
        await entered.wait()
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        release.resolve(.init(html: "<title>Old title</title>", url: request.fetchURL))
        let old = await task.value
        expect(old == nil, "fresh model loss rejects a late small-card title before publication/cache")
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        let fresh = await service.title(request)
        expect(fresh == "Fresh title", "later hover fetches fresh metadata rather than reusing the revoked title")
    }
    static func imageAvailability() async {
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        TidyTabsService.shared.refresh()
        let imageEntered = PreviewGate<Void>(), imageResult = PreviewGate<NSImage?>(), summaryFinished = PreviewGate<Void>()
        let request = LinkSummaryRequest(link: URL(string: "https://example.com/image")!, profilePath: nil, httpsOnly: false, searchQuery: nil, language: "English")
        let service = LinkSummaryService(fetch: { .init(html: "<head><title>Page</title><meta property='og:image' content='/hero.png'></head><body>One useful paragraph. Another useful paragraph.</body>", url: $0.fetchURL) }, image: { _ in imageEntered.resolve(()); return await imageResult.wait() }, answer: { _, _, _, _, _ in answer })
        var cards: [LinkSummaryService.Card] = []
        let task = Task { await service.load(request) { cards.append($0); if $0.finished { summaryFinished.resolve(()) } } }
        await imageEntered.wait()
        await summaryFinished.wait()
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        imageResult.resolve(NSImage(size: NSSize(width: 12, height: 12)))
        await task.value
        expect(service.cached(request)?.result?.quickSummary == answer.quickSummary && service.cached(request)?.image == nil,
               "model loss rejects a late optional-image cache update while retaining the earlier valid summary")
        expect(cards.allSatisfy { $0.image == nil }, "an image arriving after fresh availability loss cannot publish to the card")
    }
    static func settingOffOn() async {
        let f = PreviewHooksFixture()
        defer { f.finish() }
        f.start()
        await f.provider.entered.wait()
        expect(f.clock.pendingCount == 1, "the actual current presentation owns a loading deadline")
        f.store.settings.fiveSecondPreviews = false
        f.store.settings.fiveSecondPreviews = true
        // No manual controller.validate call: only actual production store didSet/binding can revoke.
        expect(f.clock.pendingCount == 0, "actual same-turn setting off/on synchronously cancels the current presentation")
        f.provider.release.resolve(answer)
        await f.provider.returned.wait()
        expect(f.service.cached(f.request) == nil, "actual store off/on cannot cache the old provider's late final result")
    }
    static func unrefreshedAvailability() async {
        let f = PreviewHooksFixture()
        defer { f.finish() }
        var cards: [LinkSummaryService.Card] = []
        let task = Task { await f.service.load(f.request) { cards.append($0) } }
        await f.provider.entered.wait()
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1) // Deliberately no refresh: UI status stays cached available.
        expect(TidyTabsService.shared.modelAvailable, "the controlled setup keeps actual UI status cached as available")
        f.provider.release.resolve(answer)
        await task.value
        expect(f.service.cached(f.request) == nil && cards.last?.finished == true && cards.last?.result == nil,
               "fresh model loss must reject final cache publication before controller delivery")
        expect(!f.service.isAvailable, "entry eligibility reads actual availability instead of cached UI status")
    }
    static func repeatedUnavailableRefresh() async {
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        TidyTabsService.shared.refresh() // Cache off before the new owner is bound.
        let f = PreviewHooksFixture(refresh: false) // Actual resolver on, cached UI status still off.
        defer { f.finish() }
        expect(!TidyTabsService.shared.modelAvailable && f.service.isAvailable, "fresh availability permits work despite an older cached UI state")
        f.start()
        await f.provider.entered.wait()
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        TidyTabsService.shared.refresh() // Same off enum as cached: must still deliver invalidation.
        setenv("CRA_TIDY_FAKE_MODEL", "1", 1)
        expect(f.clock.pendingCount == 0, "repeated actual unavailable refresh synchronously revokes before off/on can revive the owner")
        f.provider.release.resolve(answer)
        await f.provider.returned.wait()
        expect(f.service.cached(f.request) == nil, "observed model off/on cannot cache a revoked provider's answer")
    }
    static func disabledBeforeFetch() async {
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        var fetches = 0, cards: [LinkSummaryService.Card] = []
        let service = LinkSummaryService(fetch: { _ in fetches += 1; return nil })
        let request = LinkSummaryRequest(link: URL(string: "https://example.com/story")!, profilePath: nil, httpsOnly: false, searchQuery: nil, language: "English")
        await service.load(request) { cards.append($0) }
        expect(fetches == 0 && cards.last?.finished == true && cards.last?.result == nil,
               "actual unavailable model prevents even the first page fetch and produces terminal empty output")
    }
}
