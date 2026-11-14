import AppKit
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tidy Downloads on the Mac's Apple Intelligence model (Arc Max's renameDownloads): a finished
/// download gets a readable name from its file name, the tab it came from and the site, and the
/// file on disk is renamed. The sidebar's card above the download bin says so ("Download renamed
/// to:", Arc's SidebarBanner) with a way back; reverting says "Download name reverted!" in Cra's toast.
@MainActor @Observable
final class TidyDownloadsService {
    static let shared = TidyDownloadsService()

    /// A rename the card shows: the file's path before and after, and the window it downloaded in.
    struct Rename: Equatable, Identifiable {
        let id = UUID()
        var download: UInt32
        var window: UUID
        var historyID: UUID?
        var identity: TidyDownloadFiles.Identity? = nil
        var oldPath: String
        var newPath: String
        var oldName: String { (oldPath as NSString).lastPathComponent }
        var newName: String { (newPath as NSString).lastPathComponent }
    }

    /// The card on screen, if any.
    private(set) var card: Rename?

    /// Arc 1.171 (27 Oct 2026): the card leaves 8 s after it comes in.
    static let cardShown: TimeInterval = 8

    private struct Key: Hashable {
        var download: UInt32
        var window: UUID
    }

    private struct Request {
        let token = UUID()
        let path: String
        var identity: TidyDownloadFiles.Identity?
        var task: Task<Void, Never>?
    }

    private struct Source {
        let tab: UUID?
        let snapshot: TidyDownloads.Source
    }

    /// Only downloads still running keep source context; inference owns its bounded snapshot.
    @ObservationIgnored private var sources: [Key: Source] = [:]
    @ObservationIgnored private var requests: [Key: Request] = [:]
    typealias MoveFile = @Sendable (String, String, TidyDownloadFiles.Identity?, @escaping @MainActor @Sendable () -> Bool) async -> TidyDownloadFiles.Move?
    private let moveFile: MoveFile
    @ObservationIgnored private var reverting: UUID?
    private let modelAvailable: @MainActor () -> Bool
    private let generate: @MainActor (TidyDownloads.Request) async -> String?

    init(modelAvailable: @escaping @MainActor () -> Bool = { TidyTabsService.shared.currentModelAvailable },
         generate: @escaping @MainActor (TidyDownloads.Request) async -> String? = { await TidyDownloadsService.ask($0) },
         moveFile: @escaping MoveFile = { await TidyDownloadFiles.shared.move(from: $0, name: $1, identity: $2, eligible: $3) }) {
        self.moveFile = moveFile
        self.modelAvailable = modelAvailable
        self.generate = generate
    }

    deinit {
        for request in requests.values { request.task?.cancel() }
        dismissal?.cancel()
    }

    /// Called only for a running download. Terminal notifications must not recapture a source.
    func noteSource(_ id: UInt32, window: UUID, tabID: UUID? = nil, tab: TabData, referrer: TabData?) {
        let key = Key(download: id, window: window)
        if sources[key] == nil, requests[key] == nil {
            sources[key] = Source(tab: tabID, snapshot: TidyDownloads.Source(tab: tab, referrer: referrer))
        }
    }

    /// A live browser keeps its initiating snapshot when another window adopts it. Retire the
    /// old owner's keys so its later teardown cannot cancel the download in its new owner.
    @discardableResult
    func transferSources(tab: UUID, from old: UUID, to new: UUID) -> [UInt32] {
        guard old != new else { return [] }
        let keys = sources.keys.filter { $0.window == old && sources[$0]?.tab == tab }
        for key in keys {
            sources[Key(download: key.download, window: new)] = sources.removeValue(forKey: key)
        }
        return keys.map(\.download)
    }

    /// Reserving a path is synchronous even if its writer has not started or finished yet.
    /// The actor task is a barrier before the caller may give that path to CEF/WebKit.
    func prepareDestination(_ path: String, replacing: Bool,
                            removeExisting: @escaping TidyDownloadFiles.RemoveExisting = { try TidyDownloadFiles.trash($0) }) -> Task<Bool, Never> {
        invalidate(path: path)
        return Task { @MainActor [weak self] in
            let prepared = await TidyDownloadFiles.shared.prepareDestination(path, replacing: replacing, removeExisting: removeExisting)
            // A rename may have moved this resource to the chosen path before the barrier ran.
            // Retire its pending publication/card as well before allowing the new writer to start.
            self?.invalidate(path: path, identity: prepared.previous)
            return prepared.ready
        }
    }

    private func invalidate(path: String, identity: TidyDownloadFiles.Identity? = nil) {
        let keys = requests.keys.filter {
            requests[$0]?.path == path || (identity != nil && requests[$0]?.identity == identity)
        }
        for key in keys { requests.removeValue(forKey: key)?.task?.cancel() }
        if let card, card.newPath == path || (identity != nil && card.identity == identity) { dismiss() }
    }

    /// Opt-out and an unavailable model invalidate inference synchronously. Source snapshots for
    /// downloads still running remain until their terminal notification or their owner's teardown.
    func cancelAll() {
        let pending = Array(requests.values)
        requests.removeAll()
        pending.forEach { $0.task?.cancel() }
    }

    func cancel(_ id: UInt32, window: UUID) {
        let key = Key(download: id, window: window)
        sources[key] = nil
        requests.removeValue(forKey: key)?.task?.cancel()
    }

    func cancel(window: UUID) {
        sources = sources.filter { $0.key.window != window }
        let keys = requests.keys.filter { $0.window == window }
        for key in keys { requests.removeValue(forKey: key)?.task?.cancel() }
    }

    /// MainWindowController's finishedDownloads gate delivers each terminal completion once.
    /// The service also rejects duplicate finishes while inference is pending, without retaining
    /// a process-lifetime set of completed Chromium identifiers.
    @discardableResult
    func finished(_ id: UInt32, path: String, downloadURL: String, window: UUID, store: SidebarStore,
                  ownerEligible: @escaping () -> Bool, moved: @escaping (String) -> Void) -> Task<Void, Never>? {
        let key = Key(download: id, window: window)
        let source = sources.removeValue(forKey: key)?.snapshot
        guard requests[key] == nil, store.settings.tidyDownloads, modelAvailable(), ownerEligible(),
              store.prefs.windows.contains(where: { $0.id == window }), !path.isEmpty else { return nil }
        let original = (path as NSString).lastPathComponent
        let language = Locale.preferredLanguages.first.flatMap {
            Locale(identifier: "en").localizedString(forLanguageCode: Locale(identifier: $0).language.languageCode?.identifier ?? "en")
        } ?? "English"
        let input = TidyDownloads.Request(file: original, source: source, downloadURL: downloadURL, language: language)
        let generate = self.generate
        let historyID = DownloadHistory.shared.entries.last(where: { $0.path == path })?.id
        var request = Request(path: path)
        let token = request.token
        request.task = Task { @MainActor [weak self, weak store] in
            defer { if self?.requests[key]?.token == token { self?.requests[key] = nil } }
            // A replacement invalidates this task synchronously before it joins the same actor.
            // Consequently a snapshot obtained here still belongs to this completed download.
            guard let identity = await TidyDownloadFiles.shared.identity(at: path), !Task.isCancelled else { return }
            guard self?.requests[key]?.token == token else { return }
            self?.requests[key]?.identity = identity
            let answer = await generate(input)
            guard let self else { return }
            guard let answer, let name = TidyDownloads.clean(answer, original: original) else { return }
            let eligible: @MainActor @Sendable () -> Bool = { [weak self, weak store] in
                guard let self, let store else { return false }
                return self.requests[key]?.token == token
                    && store.settings.tidyDownloads && self.modelAvailable() && ownerEligible()
                    && store.prefs.windows.contains(where: { $0.id == window })
            }
            guard let result = await self.moveFile(path, name, identity, eligible) else { return }
            // A physical move is authoritative even if cancellation/teardown happened during IO.
            // Always reconcile history/recent; eligibility now controls only the transient card.
            if let historyID {
                DownloadHistory.shared.move(from: result.from, to: result.to, id: historyID)
            }
            moved(result.to)
            CraLog.note("Tidy Downloads: renamed a download (\(original.count) → \((result.to as NSString).lastPathComponent.count) characters)")
            if !Task.isCancelled, eligible() {
                self.show(Rename(download: id, window: window, historyID: historyID, identity: identity, oldPath: result.from, newPath: result.to))
            }
        }
        requests[key] = request
        return request.task
    }

    /// When the card goes by itself, and the timer that takes it.
    @ObservationIgnored private var dismissAt = Date.distantFuture
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    /// After the pointer leaves, the card stays at least this long (Victor, 5 Nov 2026: it went while
    /// he was deciding whether to revert; Arc's hover behaviour wasn't seen).
    static let afterHover: TimeInterval = 3

    private func show(_ r: Rename) {
        card = r
        schedule(after: Self.cardShown)
    }

    private func schedule(after delay: TimeInterval) {
        dismissal?.cancel()
        dismissAt = Date().addingTimeInterval(delay)
        let id = card?.id
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.card?.id == id else { return }
            self.card = nil
        }
    }

    /// The pointer is on the card: it stays until the pointer leaves, then for what was left of its
    /// time, but at least `afterHover`.
    func hold(_ hovering: Bool) {
        guard card != nil else { return }
        if hovering {
            let left = dismissAt.timeIntervalSinceNow
            dismissal?.cancel()
            dismissal = nil
            dismissAt = Date().addingTimeInterval(max(left, 0))
        } else {
            schedule(after: max(dismissAt.timeIntervalSinceNow, Self.afterHover))
        }
    }

    func dismiss() {
        dismissal?.cancel()
        card = nil
    }

    /// Arc's "Revert to original name": the file takes its old name back (or the next free one).
    func revert(_ r: Rename, moved: (String, String) -> Void) async -> Bool {
        guard card?.id == r.id, reverting == nil, let historyID = r.historyID,
              DownloadHistory.shared.entries.contains(where: { $0.id == historyID && $0.path == r.newPath }) else { return false }
        reverting = r.id
        defer { if reverting == r.id { reverting = nil } }
        guard let result = await moveFile(r.newPath, r.oldName, r.identity, { [weak self] in
            self?.card?.id == r.id && DownloadHistory.shared.entries.contains(where: { $0.id == historyID && $0.path == r.newPath })
        }) else { return false }
        DownloadHistory.shared.move(from: result.from, to: result.to, id: historyID)
        moved(result.from, result.to)
        // A newer completion may have presented another card while this move was running.
        if card?.id == r.id { dismiss() }
        return true
    }

    private static func ask(_ request: TidyDownloads.Request) async -> String? {
        if TidyTabsService.fakeModel {
            // Test copies without Apple Intelligence: the file's name tidied by hand.
            let ext = (request.file as NSString).pathExtension
            let stem = (request.file as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
                .filter { !$0.isNumber }.split(separator: " ").joined(separator: " ").capitalized
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: TidyDownloads.instructions(for: request))
                let r = try await session.respond(to: TidyDownloads.prompt(request), generating: TidyDownloadAnswer.self, options: GenerationOptions(sampling: .greedy))
                return r.content.newName
            } catch {
                CraLog.note("Tidy Downloads: the model failed")
                return nil
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct TidyDownloadAnswer {
    @Guide(description: "The new filename written in the requested responseLanguage. Translate generic words into that language; preserve informative proper nouns and the original file extension.")
    var newName: String
}
#endif
