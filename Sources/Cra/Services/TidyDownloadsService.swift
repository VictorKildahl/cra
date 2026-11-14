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
        var historyID: UUID?
        var fileIdentity: FileIdentity
        var oldName: String { (oldPath as NSString).lastPathComponent }
        var newName: String { (newPath as NSString).lastPathComponent }
    }

    /// The card on screen, if any.
    private(set) var card: Rename?

    /// Arc 1.171 (27 Oct 2026): the card leaves 8 s after it comes in.
    static let cardShown: TimeInterval = 8

    /// The tab a download started from: its title and address, for the prompt.
    @ObservationIgnored private var sources: [UInt32: (title: String, url: String)] = [:]
    @ObservationIgnored private var asked: Set<UInt32> = []
    /// Only pending model work owns a claim; retiring it cannot grow a permanent path registry.
    @ObservationIgnored private var requests: [String: Request] = [:]
    private struct Request {
        let token: UUID
        let fileIdentity: FileIdentity
    }

    struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64

        init?(at path: String) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            self.device = device.uint64Value
            self.inode = inode.uint64Value
        }
    }

    private let generate: (String) async -> String?
    private let modelAvailable: () -> Bool
    private let removeExisting: (String) throws -> Void
    private let beforePreparation: (() async -> Void)?

    init(generate: ((String) async -> String?)? = nil, modelAvailable: (() -> Bool)? = nil,
         beforePreparation: (() async -> Void)? = nil,
         removeExisting: @escaping (String) throws -> Void = {
             try FileManager.default.trashItem(at: URL(fileURLWithPath: $0), resultingItemURL: nil)
         }) {
        self.generate = generate ?? { await Self.ask($0) }
        self.modelAvailable = modelAvailable ?? { TidyTabsService.shared.modelAvailable }
        self.removeExisting = removeExisting
        self.beforePreparation = beforePreparation
    }

    /// The approved destination is ready before either engine starts writing.
    func prepareDestination(_ path: String, replacing: Bool) -> Task<Bool, Never> {
        // Reserve synchronously: a suspended model must lose its claim before the new
        // writer is given this destination, even when the old inode is reused later.
        invalidate(path, identity: FileIdentity(at: path))
        return Task { @MainActor in
            if let beforePreparation { await beforePreparation() }
            // A rename may have arrived while this Task waited. Retire its then-current
            // resource after the last suspension, in the same turn as removal/readiness.
            invalidate(path, identity: FileIdentity(at: path))
            do {
                if replacing, FileManager.default.fileExists(atPath: path) { try removeExisting(path) }
                return true
            } catch { return false }
        }
    }

    private func invalidate(_ path: String, identity: FileIdentity?) {
        // Different path spellings/hard links can still name the resource an engine replaces.
        requests = requests.filter { $0.key != path && $0.value.fileIdentity != identity }
        if let card, card.newPath == path || card.fileIdentity == identity { dismiss() }
    }

    func noteSource(_ id: UInt32, title: String, url: String) {
        if sources[id] == nil { sources[id] = (title, url) }
    }

    /// A download finished at `path`. Rename it if the setting is on and the model can run; `moved`
    /// tells the window the file's new path.
    @discardableResult
    func finished(_ id: UInt32, path: String, downloadURL: String, window: UUID, store: SidebarStore,
                  moved: @escaping (String) -> Void) -> Task<Void, Never>? {
        guard store.settings.tidyDownloads, modelAvailable(), !asked.contains(id), !path.isEmpty else { return nil }
        asked.insert(id)
        let source = sources.removeValue(forKey: id)
        let original = (path as NSString).lastPathComponent
        let prompt = TidyDownloads.prompt(file: original, tabTitle: source?.title ?? "", url: source?.url ?? downloadURL)
        // Capture both identities before creating/suspending the model task. A later history
        // lookup by path could otherwise select a different download's completed row.
        guard let identity = FileIdentity(at: path) else { return nil }
        let historyID = DownloadHistory.shared.entries.last(where: { $0.path == path })?.id
        let token = UUID()
        requests[path] = Request(token: token, fileIdentity: identity)
        return Task { @MainActor in
            defer { if requests[path]?.token == token { requests.removeValue(forKey: path) } }
            guard let answer = await generate(prompt), let name = TidyDownloads.clean(answer, original: original),
                  requests[path]?.token == token, FileIdentity(at: path) == identity else { return }
            let folder = (path as NSString).deletingLastPathComponent
            let fm = FileManager.default
            let free = TidyDownloads.unique(name) { fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0)) }
            let newPath = (folder as NSString).appendingPathComponent(free)
            guard fm.fileExists(atPath: path), (try? fm.moveItem(atPath: path, toPath: newPath)) != nil else {
                CraLog.note("Tidy Downloads: the file couldn't be renamed")
                return
            }
            if let historyID { DownloadHistory.shared.move(id: historyID, from: path, to: newPath) }
            moved(newPath)
            CraLog.note("Tidy Downloads: renamed a download (\(original.count) → \(free.count) characters)")
            show(Rename(download: id, window: window, oldPath: path, newPath: newPath,
                        historyID: historyID, fileIdentity: identity))
        }
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
        guard card?.id == r.id, FileIdentity(at: r.newPath) == r.fileIdentity else { return false }
        dismiss()
        let fm = FileManager.default
        guard fm.fileExists(atPath: r.newPath) else { return false }
        let folder = (r.oldPath as NSString).deletingLastPathComponent
        let free = TidyDownloads.unique(r.oldName) { fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0)) }
        let back = (folder as NSString).appendingPathComponent(free)
        guard (try? fm.moveItem(atPath: r.newPath, toPath: back)) != nil else { return false }
        if let historyID = r.historyID { DownloadHistory.shared.move(id: historyID, from: r.newPath, to: back) }
        moved(r.newPath, back)
        return true
    }

    private static func ask(_ prompt: String) async -> String? {
        if TidyTabsService.fakeModel {
            // Test copies without Apple Intelligence: the file's name tidied by hand.
            guard let line = prompt.split(separator: "\n").last, let q = line.range(of: "Rename: '") else { return nil }
            let file = line[q.upperBound...].prefix { $0 != "'" }
            let ext = (String(file) as NSString).pathExtension
            let stem = (String(file) as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
                .filter { !$0.isNumber }.split(separator: " ").joined(separator: " ").capitalized
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: TidyDownloads.instructions)
                let r = try await session.respond(to: prompt, generating: TidyDownloadAnswer.self, options: GenerationOptions(sampling: .greedy))
                return r.content.name
            } catch {
                CraLog.note("Tidy Downloads: the model failed: \(error)")
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
    @Guide(description: "The file's new name, with its extension")
    var name: String
}
#endif
