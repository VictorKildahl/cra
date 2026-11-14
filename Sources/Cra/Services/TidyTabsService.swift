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
    static let shared: TidyTabsService = {
        let service = TidyTabsService()
        service.activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak service] _ in
            MainActor.assumeIsolated { service?.refresh() }
        }
        return service
    }()

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
    /// Eligibility at a mutation boundary may be newer than the cached UI status.
    var currentModelAvailable: Bool { Self.currentStatus() == .available }

    typealias Generate = @MainActor (TidyTabs.Request) async throws -> TidyTabsModel.Answer
    private struct Key: Hashable { let store: ObjectIdentifier; let space: UUID }
    private struct Run {
        let token = UUID()
        weak var store: SidebarStore?
        let today: UUID
        let started: Date
        var task: Task<Void, Never>?
        var delay: ScheduledWork?
    }
    private enum Outcome { case success(TidyTabsModel.Answer), failure }
    @ObservationIgnored private let generate: Generate
    @ObservationIgnored private let availability: (@MainActor () -> Bool)?
    @ObservationIgnored private var runs: [Key: Run] = [:]
    @ObservationIgnored private var activation: NSObjectProtocol?

    init(generate: Generate? = nil, modelAvailable: (@MainActor () -> Bool)? = nil) {
        self.generate = generate ?? Self.ask
        self.availability = modelAvailable
        refresh()
    }

    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
        let pending = Array(runs)
        pending.forEach { $0.value.task?.cancel() }
        Task { @MainActor in
            for (key, run) in pending {
                run.delay?.cancel()
                run.store?.setTidying(key.space, false)
            }
        }
    }

    func refresh() {
        let now = Self.currentStatus()
        // Invalidate synchronously even if the unavailable status was already cached.
        if now != .available { cancelAll() }
        if now != status { status = now }
    }

    func cancelAll(store: SidebarStore? = nil) {
        let owner = store.map(ObjectIdentifier.init)
        let keys = runs.keys.filter { owner == nil || $0.store == owner }
        for key in keys { if let token = runs[key]?.token { finish(key, token: token) } }
    }

    func cancel(_ sid: UUID, store: SidebarStore) {
        let key = Key(store: ObjectIdentifier(store), space: sid)
        if let token = runs[key]?.token { finish(key, token: token) }
    }

    private var eligibleModel: Bool { availability?() ?? currentModelAvailable }

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

    /// The retained provider task completes after its outcome has scheduled/applied the minimum
    /// animation. The service also owns any remaining delay; settings and lifecycle cancellation
    /// invalidate both without waiting for an uncooperative provider.
    @discardableResult
    func tidy(_ sid: UUID, store: SidebarStore) -> Task<Void, Never>? {
        let key = Key(store: ObjectIdentifier(store), space: sid)
        if let old = runs[key], old.store !== store { finish(key, token: old.token) }
        guard store.settings.tidyTabs, eligibleModel, store.canTidy(sid),
              runs[key] == nil, !store.tidyingSpaces.contains(sid), let space = store.space(sid) else { return nil }
        let loose = store.tidyCandidates(sid).prefix(TidyTabs.maximumTabs)
        let tabs = loose.map { item in
            TidyTabs.Tab(id: item.id, title: item.displayTitle, host: item.tab.flatMap { URL(string: $0.url)?.host() } ?? "")
        }
        let groups = store.tabGroups(in: sid).map { TidyTabs.ExistingGroup(id: $0.id, name: $0.title ?? "") }
        guard let request = TidyTabs.request(tabs: tabs, existingGroups: groups,
                                             maximumBytes: TidyTabsModel.promptByteLimit) else { return nil }
        let run = Run(store: store, today: space.todayContainerID, started: store.clock.now)
        runs[key] = run
        store.setTidying(sid, true)
        let generate = self.generate, token = run.token
        let task = Task { @MainActor [weak self] in
            await withTaskCancellationHandler {
                do {
                    try Task.checkCancellation()
                    let answer = try await generate(request)
                    try Task.checkCancellation()
                    self?.generated(.success(answer), key: key, token: token)
                } catch is CancellationError {
                    self?.finish(key, token: token)
                } catch {
                    CraLog.note(error is TidyTabsModel.Failure ? "Tidy Tabs: model unavailable or context limit" : "Tidy Tabs: generation failed")
                    if Task.isCancelled { self?.finish(key, token: token) }
                    else { self?.generated(.failure, key: key, token: token) }
                }
            } onCancel: { [weak self] in
                Task { @MainActor [weak self] in self?.finish(key, token: token) }
            }
        }
        runs[key]?.task = task
        return task
    }

    private func generated(_ outcome: Outcome, key: Key, token: UUID) {
        guard let run = runs[key], run.token == token else { return }
        runs[key]?.task = nil
        guard let store = run.store, eligible(key, run: run, store: store) else { finish(key, token: token); return }
        let rest = TidyTabs.minimumRun - store.clock.now.timeIntervalSince(run.started)
        if rest > 0 {
            runs[key]?.delay = store.clock.after(rest) { [weak self] in self?.apply(outcome, key: key, token: token) }
        } else { apply(outcome, key: key, token: token) }
    }

    private func eligible(_ key: Key, run: Run, store: SidebarStore) -> Bool {
        store.settings.tidyTabs && eligibleModel && !store.isIncognito(space: key.space)
            && store.space(key.space)?.todayContainerID == run.today && store.item(run.today) != nil
    }

    private func apply(_ outcome: Outcome, key: Key, token: UUID) {
        guard let run = runs[key], run.token == token else { return }
        guard let store = run.store, eligible(key, run: run, store: store) else { finish(key, token: token); return }
        if case .success(let answer) = outcome {
            // The adapter may have reduced this request: consume its actual fitted mapping only.
            store.applyTidy(answer.request.plan(answer.proposals), tabIDs: answer.request.tabIDs, in: key.space)
            CraLog.note("Tidy Tabs: completed \(answer.request.tabs.count) tabs, \(answer.proposals.count) proposed groups")
        }
        finish(key, token: token)
    }

    private func finish(_ key: Key, token: UUID) {
        guard let run = runs[key], run.token == token else { return }
        runs[key] = nil
        run.store?.setTidying(key.space, false)
        run.delay?.cancel()
        run.task?.cancel()
    }

    private static func ask(_ request: TidyTabs.Request) async throws -> TidyTabsModel.Answer {
        if fakeModel { return try await fakeAnswer(request) }
        return try await TidyTabsModel.group(request)
    }

    // MARK: Test model

    static let fakeModel = ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"] == "1"

    /// Groups tabs by site, named after it, after a model-like pause: enough to drive the UI in a
    /// test copy on a Mac without Apple Intelligence.
    private static func fakeAnswer(_ request: TidyTabs.Request) async throws -> TidyTabsModel.Answer {
        try await Task.sleep(for: .seconds(1.6))
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
