import AppKit
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tidy Tab Titles on the Mac's Apple Intelligence model: a tab you pin gets a short name (Arc Max's
/// renamePinnedTabs). The name becomes the tab's custom title, as in Arc, and the row plays Arc's
/// rename (TabRowView.playTidyRename): the old title sweeps into the new one with sparkles, and
/// "Double-click to rename" shows under it for a few seconds.
@MainActor @Observable
final class TidyTitlesService {
    static let shared = TidyTitlesService()

    /// A rename the row is showing: what it was called, and since when.
    struct Effect: Equatable {
        var token = UUID()
        var oldTitle: String
        var start: Date
    }

    /// Tabs renamed in the last few seconds: their rows show the subtitle and play the sweep once.
    private(set) var effects: [UUID: Effect] = [:]

    /// Arc 1.171, two 120 fps recordings (4 Nov 2026): the rename started ~1 s after the pin (its
    /// server's round trip; Cra's model answers in ~0.5 s, so it waits the rest), the sweep and
    /// sparkles ran 0.55 s, and the subtitle left 3.1 s after that.
    static let delayAfterPin: TimeInterval = 1.0
    static let sweep: TimeInterval = 0.55
    static let subtitleShown: TimeInterval = 3.65
    static let subtitle = "Double-click to rename"

    private struct Request {
        let token = UUID()
        let shown: String
        let homeURL: String
        let windowID: UUID
        let started: Date
        var task: Task<Void, Never>?
        var reveal: ScheduledWork?
        var expiry: ScheduledWork?

        @MainActor func cancel() {
            task?.cancel()
            reveal?.cancel()
            expiry?.cancel()
        }
    }

    @ObservationIgnored private var requests: [UUID: Request] = [:]
    @ObservationIgnored private let titleLayout: @MainActor (UUID, UUID) -> TidyTitleLayout?
    @ObservationIgnored private let generate: @MainActor (String, String) async -> TidyTitles.Answer?
    @ObservationIgnored private let modelAvailable: @MainActor () -> Bool

    init(titleLayout: @escaping @MainActor (UUID, UUID) -> TidyTitleLayout? = { id, window in
        SpaceListView.tidyTitleLayout(for: id, window: window)
    }, generate: @escaping @MainActor (String, String) async -> TidyTitles.Answer? = { prompt, title in
        await TidyTitlesService.ask(prompt, title: title)
    }, modelAvailable: @escaping @MainActor () -> Bool = { TidyTabsService.shared.modelAvailable }) {
        self.titleLayout = titleLayout
        self.generate = generate
        self.modelAvailable = modelAvailable
    }

    deinit {
        let pending = Array(requests.values)
        pending.forEach { $0.task?.cancel() }
        Task { @MainActor in pending.forEach { $0.cancel() } }
    }

    /// Disabling the feature invalidates work before asking its tasks/timers to stop.
    func cancelAll() {
        let pending = Array(requests.values)
        requests.removeAll()
        effects.removeAll()
        pending.forEach { $0.cancel() }
    }

    /// The store saw a tab pinned. Ask for a name if the setting is on and the model can run.
    func tabPinned(_ id: UUID, store: SidebarStore) {
        guard store.settings.tidyTabTitles, modelAvailable(), requests[id] == nil,
              let item = store.item(id), item.title == nil, let tab = item.tab,
              !item.isEmptyTab, store.isPinned(id) else { return }
        let shown = TidyTitleRules.arc.tidy(item.displayTitle, url: tab.url)
        let title = item.displayTitle
        let language = Locale.preferredLanguages.first.flatMap {
            Locale(identifier: "en_US").localizedString(forLanguageCode: $0)
        } ?? "English"
        let prompt = TidyTitles.prompt(title: title, url: tab.url, language: language)
        // Programmatic pins fall back to the store's active window at pin time.
        let request = Request(shown: shown, homeURL: tab.savedURL,
                              windowID: store.activeWindowID, started: store.clock.now)
        requests[id] = request
        let generate = self.generate
        requests[id]?.task = Task { @MainActor [weak self, weak store] in
            guard !Task.isCancelled, self?.requests[id]?.token == request.token, store != nil else { return }
            let answer = await generate(prompt, title)
            guard !Task.isCancelled else { self?.finish(id, token: request.token); return }
            self?.generated(answer, for: id, token: request.token, store: store)
        }
    }

    private func generated(_ answer: TidyTitles.Answer?, for id: UUID, token: UUID, store: SidebarStore?) {
        guard let request = requests[id], request.token == token else { return }
        requests[id]?.task = nil
        guard let answer, let store else { finish(id, token: token); return }
        let remaining = Self.delayAfterPin - store.clock.now.timeIntervalSince(request.started)
        if remaining > 0 {
            requests[id]?.reveal = store.clock.after(remaining) { [weak self, weak store] in
                self?.apply(answer, to: id, token: token, store: store)
            }
        } else {
            apply(answer, to: id, token: token, store: store)
        }
    }

    private func apply(_ answer: TidyTitles.Answer, to id: UUID, token: UUID, store: SidebarStore?) {
        guard let request = requests[id], request.token == token else { return }
        requests[id]?.reveal = nil
        let now = store?.item(id)
        let shown = now.flatMap { item in
            item.tab.map { TidyTitleRules.arc.tidy(item.displayTitle, url: $0.url) }
        }
        guard let store,
              TidyTitles.canApply(enabled: store.settings.tidyTabTitles,
                                  pinned: store.isPinned(id), customTitle: now?.title,
                                  shown: shown, originalShown: request.shown,
                                  homeURL: now?.tab?.savedURL, originalHomeURL: request.homeURL) else {
            finish(id, token: token)
            return
        }
        let layout = titleLayout(id, request.windowID) ?? .fallback
        guard let name = layout.select(TidyTitles.candidates(answer), shown: request.shown) else {
            finish(id, token: token)
            return
        }
        store.rename(id, to: name)
        effects[id] = Effect(token: token, oldTitle: request.shown, start: store.clock.now)
        CraLog.note("Tidy Tab Titles: renamed a pinned tab (\(request.shown.count) → \(name.count) characters)")
        requests[id]?.expiry = store.clock.after(Self.subtitleShown) { [weak self] in
            self?.finish(id, token: token)
        }
    }

    private func finish(_ id: UUID, token: UUID) {
        guard requests[id]?.token == token, let request = requests.removeValue(forKey: id) else { return }
        request.cancel()
        if effects[id]?.token == token { effects[id] = nil }
    }

    private static func ask(_ prompt: String, title: String) async -> TidyTitles.Answer? {
        if let fake = fakeAnswer(title) { return fake }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: TidyTitles.instructions)
                let r = try await session.respond(to: prompt, generating: TidyTitleAnswer.self, options: GenerationOptions(sampling: .greedy))
                return TidyTitles.Answer(filtered: r.content.filtered, rewritten: r.content.rewritten)
            } catch is CancellationError {
                return nil
            } catch {
                CraLog.note("Tidy Tab Titles: the model failed: \(error)")
                return nil
            }
        }
        #endif
        return nil
    }

    /// CRA_TIDY_FAKE_MODEL=1: the title up to its first separator, so a test copy renames without
    /// Apple Intelligence ("Climate - BBC News" → "Climate").
    private static func fakeAnswer(_ title: String) -> TidyTitles.Answer? {
        guard TidyTabsService.fakeModel else { return nil }
        let cut = title.components(separatedBy: CharacterSet(charactersIn: "|–—-·:‹")).first ?? title
        let name = cut.trimmingCharacters(in: .whitespaces)
        return TidyTitles.Answer(filtered: name, rewritten: name)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct TidyTitleAnswer {
    @Guide(description: "The title translated and filtered to remove cruft, with no word limit")
    var filtered: String
    @Guide(description: "The title rewritten in 1–3 words, keeping specifics and proper nouns")
    var rewritten: String
}
#endif
