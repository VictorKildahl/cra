import AppKit
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tidy Tabs on the Mac's own Apple Intelligence model (FoundationModels, macOS 26): free, and
/// nothing leaves the Mac. Arc sent the same "id: title" list to its server (Arc Max). Without
/// Apple Intelligence (an older macOS, a Mac that can't run it, or it is off) the Tidy button
/// doesn't show at all. What the answer does to the sidebar is TidyTabs (CraCore) and the store.
@MainActor @Observable
final class TidyTabsService {
    static let shared = TidyTabsService()

    /// Whether the system model can run now. Read again when Cra comes to the front, so turning
    /// Apple Intelligence on in System Settings shows the button without a relaunch.
    private(set) var modelAvailable = false
    /// Why not, for Settings (nil while available).
    private(set) var unavailableReason: String? = "Needs macOS 26 and Apple Intelligence."

    @ObservationIgnored private var activation: NSObjectProtocol?

    private init() {
        refresh()
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TidyTabsService.shared.refresh() }
        }
    }

    func refresh() {
        // A test copy can stand in a fixed model (CRA_TIDY_FAKE_MODEL=1) where Apple Intelligence is off.
        if Self.fakeModel {
            set(available: true, reason: nil)
            return
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: set(available: true, reason: nil)
            case .unavailable(.appleIntelligenceNotEnabled):
                set(available: false, reason: "Turn on Apple Intelligence in System Settings to use it.")
            case .unavailable(.deviceNotEligible):
                set(available: false, reason: "This Mac can’t run Apple Intelligence.")
            case .unavailable(.modelNotReady):
                set(available: false, reason: "Apple Intelligence is still getting ready.")
            case .unavailable:
                set(available: false, reason: "Apple Intelligence isn’t available right now.")
            }
            return
        }
        #endif
        set(available: false, reason: "Needs macOS 26 and Apple Intelligence.")
    }

    private func set(available: Bool, reason: String?) {
        if modelAvailable != available { modelAvailable = available }
        if unavailableReason != reason { unavailableReason = reason }
    }

    /// Whether the divider may show Tidy for this space now.
    func offers(_ sid: UUID, store: SidebarStore) -> Bool {
        modelAvailable && store.settings.tidyTabs && store.canTidy(sid)
    }

    /// The Tidy button: ask the model about the space's loose Today tabs and apply its answer.
    func tidy(_ sid: UUID, store: SidebarStore) {
        guard modelAvailable, !store.tidyingSpaces.contains(sid) else { return }
        let loose = Array(store.looseTodayTabs(sid).prefix(TidyTabs.maximumTabs))
        guard !loose.isEmpty else { return }
        let tabs = loose.map { item in
            TidyTabs.Tab(title: item.displayTitle, host: item.tab.flatMap { URL(string: $0.url)?.host() } ?? "")
        }
        let groups = store.tabGroups(in: sid).map { $0.title ?? "" }
        let ids = loose.map(\.id)
        let prompt = TidyTabs.prompt(tabs: tabs, existingGroups: groups)
        store.setTidying(sid, true)
        let started = Date()
        Task { @MainActor in
            let proposals = await Self.ask(prompt)
            // Counts and time only: tab titles stay out of the log (it goes into diagnostics).
            CraLog.note(String(format: "Tidy Tabs: %d tabs, %d groups proposed in %.1f s", tabs.count, proposals?.count ?? -1,
                               Date().timeIntervalSince(started)))
            // The squiggle runs at least one full swing of the broom, so a quick answer doesn't flash.
            let rest = SidebarTidyMetrics.minimumRun - Date().timeIntervalSince(started)
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            store.setTidying(sid, false)
            guard let proposals else {
                store.markTidied(sid)
                return
            }
            // The list slides the tabs under their new headers (SpaceListView.placeViews).
            store.applyTidy(TidyTabs.plan(proposals, tabCount: tabs.count, existingGroups: groups), tabIDs: ids, in: sid)
        }
    }

    /// The model's groups, nil when it couldn't answer.
    private static func ask(_ prompt: String) async -> [TidyTabs.Proposal]? {
        if fakeModel { return await fakeAnswer(prompt) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: TidyTabs.instructions)
                let answer = try await session.respond(to: prompt, generating: TidyAnswer.self,
                                                       options: GenerationOptions(sampling: .greedy))
                return answer.content.groups.map { TidyTabs.Proposal(name: $0.name, tabs: $0.tabs) }
            } catch {
                CraLog.note("Tidy Tabs: the model failed: \(error)")
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: Test model

    static let fakeModel = ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"] == "1"

    /// Groups tabs by site, named after it, after a model-like pause: enough to drive the UI in a
    /// test copy on a Mac without Apple Intelligence.
    private static func fakeAnswer(_ prompt: String) async -> [TidyTabs.Proposal] {
        try? await Task.sleep(for: .seconds(1.6))
        var bySite: [String: [Int]] = [:]
        var order: [String] = []
        for line in prompt.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":"), let id = Int(line[..<colon]),
                  let open = line.lastIndex(of: "("), line.hasSuffix(")") else { continue }
            let site = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            if bySite[site] == nil { order.append(site) }
            bySite[site, default: []].append(id)
        }
        return order.map { TidyTabs.Proposal(name: $0.replacingOccurrences(of: "www.", with: ""), tabs: bySite[$0] ?? []) }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct TidyAnswer {
    @Guide(description: "The groups, each with a name and the ids of its tabs")
    var groups: [TidyGroup]
}

@available(macOS 26.0, *)
@Generable
struct TidyGroup {
    @Guide(description: "What the tabs have in common, in one or two words, like a folder name: 'Planets', 'Trip to Lisbon', 'Cra Pull Requests'")
    var name: String
    @Guide(description: "Ids of every tab that belongs in this group")
    var tabs: [Int]
}
#endif
