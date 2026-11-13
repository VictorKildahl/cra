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
    private(set) var status: Status = .needsNewerMacOS
    var modelAvailable: Bool { status == .available }

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
        let loose = Array(store.tidyCandidates(sid).prefix(TidyTabs.maximumTabs))
        guard !loose.isEmpty else { return }
        let tabs = loose.map { item in
            TidyTabs.Tab(id: item.id, title: item.displayTitle, host: item.tab.flatMap { URL(string: $0.url)?.host() } ?? "")
        }
        let groups = store.tabGroups(in: sid).map { TidyTabs.ExistingGroup(id: $0.id, name: $0.title ?? "") }
        guard let request = TidyTabs.request(tabs: tabs, existingGroups: groups,
                                             maximumBytes: TidyTabsModel.promptByteLimit) else { return }
        store.setTidying(sid, true)
        let started = Date()
        Task { @MainActor in
            let answer = await Self.ask(request)
            // Counts and time only: tab titles stay out of the log (it goes into diagnostics).
            CraLog.note(String(format: "Tidy Tabs: %d tabs, %d groups proposed in %.1f s", answer?.request.tabs.count ?? request.tabs.count, answer?.proposals.count ?? -1,
                               Date().timeIntervalSince(started)))
            // The squiggle runs at least one full swing of the broom, so a quick answer doesn't flash.
            let rest = SidebarTidyMetrics.minimumRun - Date().timeIntervalSince(started)
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            store.setTidying(sid, false)
            guard let answer else {
                store.markTidied(sid)
                return
            }
            // The list slides the tabs under their new headers (SpaceListView.placeViews).
            store.applyTidy(answer.request.plan(answer.proposals), tabIDs: answer.request.tabIDs, in: sid)
        }
    }

    /// Failures stay distinct from a successful empty answer; the caller owns the UI outcome.
    private static func ask(_ request: TidyTabs.Request) async -> TidyTabsModel.Answer? {
        if fakeModel { return await fakeAnswer(request) }
        do {
            return try await TidyTabsModel.group(request)
        } catch is CancellationError {
            CraLog.note("Tidy Tabs: generation cancelled")
        } catch TidyTabsModel.Failure.contextLimit {
            CraLog.note("Tidy Tabs: context limit after bounded recovery")
        } catch {
            CraLog.note("Tidy Tabs: generation unavailable or failed")
        }
        return nil
    }

    // MARK: Test model

    static let fakeModel = ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"] == "1"

    /// Groups tabs by site, named after it, after a model-like pause: enough to drive the UI in a
    /// test copy on a Mac without Apple Intelligence.
    private static func fakeAnswer(_ request: TidyTabs.Request) async -> TidyTabsModel.Answer {
        try? await Task.sleep(for: .seconds(1.6))
        var bySite: [String: [Int]] = [:]
        var order: [String] = []
        for (id, tab) in request.tabs.enumerated() {
            let site = tab.host.isEmpty ? "Tabs" : tab.host
            if bySite[site] == nil { order.append(site) }
            bySite[site, default: []].append(id)
        }
        return TidyTabsModel.Answer(request: request, proposals: order.map {
            TidyTabs.Proposal(name: $0.replacingOccurrences(of: "www.", with: ""), tabs: bySite[$0] ?? [])
        })
    }
}
