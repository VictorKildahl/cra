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

    @ObservationIgnored private var pending: Set<UUID> = []
    @ObservationIgnored private let titleLayout: @MainActor (UUID, UUID) -> TidyTitleLayout?

    init(titleLayout: @escaping @MainActor (UUID, UUID) -> TidyTitleLayout? = { id, window in
        SpaceListView.tidyTitleLayout(for: id, window: window)
    }) {
        self.titleLayout = titleLayout
    }

    /// The store saw a tab pinned. Ask for a name if the setting is on and the model can run.
    func tabPinned(_ id: UUID, store: SidebarStore) {
        guard store.settings.tidyTabTitles, TidyTabsService.shared.modelAvailable, !pending.contains(id),
              let item = store.item(id), item.title == nil, let tab = item.tab, !item.isEmptyTab else { return }
        let shown = TidyTitleRules.arc.tidy(item.displayTitle, url: tab.url)
        let title = item.displayTitle
        let language = Locale.preferredLanguages.first.flatMap {
            Locale(identifier: "en_US").localizedString(forLanguageCode: $0)
        } ?? "English"
        let prompt = TidyTitles.prompt(title: title, url: tab.url, language: language)
        // Programmatic pins fall back to the store's active window at pin time.
        let originWindowID = store.activeWindowID
        pending.insert(id)
        let started = Date()
        Task { @MainActor in
            defer { pending.remove(id) }
            let answer = await Self.ask(prompt, title: title)
            let rest = Self.delayAfterPin - Date().timeIntervalSince(started)
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            let candidates = answer.map(TidyTitles.candidates) ?? []
            let layout = titleLayout(id, originWindowID) ?? .fallback
            // Only if nothing changed meanwhile: still pinned, still unnamed, same page title.
            guard let name = layout.select(candidates, shown: shown),
                  let now = store.item(id), now.title == nil, store.isPinned(id),
                  now.tab.map({ TidyTitleRules.arc.tidy(now.displayTitle, url: $0.url) }) == shown else { return }
            store.rename(id, to: name)
            let effect = Effect(oldTitle: shown, start: Date())
            effects[id] = effect
            CraLog.note("Tidy Tab Titles: renamed a pinned tab (\(shown.count) → \(name.count) characters)")
            try? await Task.sleep(for: .seconds(Self.subtitleShown))
            if effects[id]?.token == effect.token { effects[id] = nil }
        }
    }

    private static func ask(_ prompt: String, title: String) async -> TidyTitles.Answer? {
        if let fake = fakeAnswer(title) { return fake }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: TidyTitles.instructions)
                let r = try await session.respond(to: prompt, generating: TidyTitleAnswer.self, options: GenerationOptions(sampling: .greedy))
                return TidyTitles.Answer(filtered: r.content.filtered, rewritten: r.content.rewritten)
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
