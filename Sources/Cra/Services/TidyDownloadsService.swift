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
        var task: Task<Void, Never>?
    }

    /// Only downloads still running keep source context; inference owns its bounded snapshot.
    @ObservationIgnored private var sources: [Key: TidyDownloads.Source] = [:]
    @ObservationIgnored private var requests: [Key: Request] = [:]
    @ObservationIgnored private let modelAvailable: @MainActor () -> Bool
    @ObservationIgnored private let generate: @MainActor (TidyDownloads.Request) async -> String?

    init(modelAvailable: @escaping @MainActor () -> Bool = { TidyTabsService.shared.currentModelAvailable },
         generate: @escaping @MainActor (TidyDownloads.Request) async -> String? = { await TidyDownloadsService.ask($0) }) {
        self.modelAvailable = modelAvailable
        self.generate = generate
    }

    deinit {
        for request in requests.values { request.task?.cancel() }
        dismissal?.cancel()
    }

    /// Called only for a running download. Terminal notifications must not recapture a source.
    func noteSource(_ id: UInt32, window: UUID, tab: TabData, referrer: TabData?) {
        let key = Key(download: id, window: window)
        if sources[key] == nil, requests[key] == nil {
            sources[key] = TidyDownloads.Source(tab: tab, referrer: referrer)
        }
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
        let source = sources.removeValue(forKey: key)
        guard requests[key] == nil, store.settings.tidyDownloads, modelAvailable(), ownerEligible(),
              store.prefs.windows.contains(where: { $0.id == window }), !path.isEmpty else { return nil }
        let original = (path as NSString).lastPathComponent
        let language = Locale.preferredLanguages.first.flatMap {
            Locale(identifier: "en").localizedString(forLanguageCode: Locale(identifier: $0).language.languageCode?.identifier ?? "en")
        } ?? "English"
        let input = TidyDownloads.Request(file: original, source: source, downloadURL: downloadURL, language: language)
        let generate = self.generate
        var request = Request(path: path)
        let token = request.token
        request.task = Task { @MainActor [weak self, weak store] in
            let answer = await generate(input)
            guard let self else { return }
            // A cancelled provider may still finish after a newer request has taken this key.
            defer { if self.requests[key]?.token == token { self.requests[key] = nil } }
            guard let answer, let name = TidyDownloads.clean(answer, original: original) else { return }
            let folder = (path as NSString).deletingLastPathComponent
            let fm = FileManager.default
            guard let free = TidyDownloads.unique(name, existing: {
                fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0))
            }) else { return }
            let newPath = (folder as NSString).appendingPathComponent(free)
            // No suspension separates this last eligibility check from the existing move boundary.
            guard !Task.isCancelled, self.requests[key]?.token == token,
                  self.requests[key]?.path == path, let store, store.settings.tidyDownloads,
                  self.modelAvailable(), ownerEligible(), store.prefs.windows.contains(where: { $0.id == window }),
                  fm.fileExists(atPath: path) else { return }
            guard (try? fm.moveItem(atPath: path, toPath: newPath)) != nil else {
                CraLog.note("Tidy Downloads: the file couldn't be renamed")
                return
            }
            DownloadHistory.shared.move(from: path, to: newPath)
            moved(newPath)
            CraLog.note("Tidy Downloads: renamed a download (\(original.count) → \(free.count) characters)")
            self.show(Rename(download: id, window: window, oldPath: path, newPath: newPath))
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
    func revert(_ r: Rename, moved: (String, String) -> Void) -> Bool {
        dismiss()
        let fm = FileManager.default
        guard fm.fileExists(atPath: r.newPath) else { return false }
        let folder = (r.oldPath as NSString).deletingLastPathComponent
        guard let free = TidyDownloads.unique(r.oldName, existing: {
            fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0))
        }) else { return false }
        let back = (folder as NSString).appendingPathComponent(free)
        guard (try? fm.moveItem(atPath: r.newPath, toPath: back)) != nil else { return false }
        DownloadHistory.shared.move(from: r.newPath, to: back)
        moved(r.newPath, back)
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
