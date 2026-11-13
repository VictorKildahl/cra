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

    /// Where Apple Intelligence stands on this Mac, as Settings explains it.
    enum Status: Equatable {
        case available
        /// Off in System Settings ▸ Apple Intelligence & Siri.
        case off
        /// On, with the model still downloading.
        case preparing
        /// An Intel Mac, or one Apple Intelligence doesn't support.
        case ineligible
        /// macOS 15 or earlier: no FoundationModels.
        case needsNewerMacOS
        case unavailable

        /// What Settings ▸ Max says under its features.
        var explanation: String {
            switch self {
            case .available: return "Max features run on Apple Intelligence on this Mac, so the model sends nothing anywhere."
            case .off: return "Max features run on Apple Intelligence, which is off on this Mac."
            case .preparing: return "Apple Intelligence is still downloading. Max features turn on once it’s ready."
            case .ineligible: return "Max features run on Apple Intelligence, which needs a Mac with Apple silicon."
            case .needsNewerMacOS: return "Max features run on Apple Intelligence, which needs macOS 26 or later."
            case .unavailable: return "Apple Intelligence isn’t available right now."
            }
        }

        /// Whether System Settings can fix it.
        var canOpenSettings: Bool { self == .off || self == .preparing || self == .unavailable }
    }

    /// Read again when Cra comes to the front and while Settings shows it, so turning Apple
    /// Intelligence on in System Settings shows the button without a relaunch.
    private(set) var status: Status = .needsNewerMacOS {
        didSet {
            if status != .available {
                NotificationCenter.default.post(name: AskOnPage.unavailableNotification, object: self)
            }
        }
    }
    var modelAvailable: Bool { status == .available }
    /// Ask rechecks the real resolver at request/delivery boundaries rather than trusting UI cache.
    var currentModelAvailable: Bool { Self.currentStatus() == .available }

    @ObservationIgnored private var activation: NSObjectProtocol?

    private init() {
        refresh()
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TidyTabsService.shared.refresh() }
        }
    }

    func refresh() {
        let now = Self.currentStatus()
        if now != status { status = now }
        else if now != .available {
            // A repeated unavailable refresh must invalidate work even when the UI cache did not change.
            NotificationCenter.default.post(name: AskOnPage.unavailableNotification, object: self)
        }
    }

    private static func currentStatus() -> Status {
        // A test copy can stand in a fixed model (CRA_TIDY_FAKE_MODEL=1) where Apple Intelligence is off,
        // or show Settings as a Mac without it would (=off, =preparing, =ineligible).
        switch ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"] {
        case "1": return .available
        case "off": return .off
        case "preparing": return .preparing
        case "ineligible": return .ineligible
        default: break
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.appleIntelligenceNotEnabled): return .off
            case .unavailable(.modelNotReady): return .preparing
            case .unavailable(.deviceNotEligible): return .ineligible
            case .unavailable: return .unavailable
            }
        }
        #endif
        return .needsNewerMacOS
    }

    /// System Settings ▸ Apple Intelligence & Siri (the Siri-Settings extension's pane).
    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.systemSettingsURL)
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
