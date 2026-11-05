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

    /// The tab a download started from: its title and address, for the prompt.
    @ObservationIgnored private var sources: [UInt32: (title: String, url: String)] = [:]
    @ObservationIgnored private var asked: Set<UInt32> = []

    private init() {}

    func noteSource(_ id: UInt32, title: String, url: String) {
        if sources[id] == nil { sources[id] = (title, url) }
    }

    /// A download finished at `path`. Rename it if the setting is on and the model can run; `moved`
    /// tells the window the file's new path.
    func finished(_ id: UInt32, path: String, downloadURL: String, window: UUID, store: SidebarStore,
                  moved: @escaping (String) -> Void) {
        guard store.settings.tidyDownloads, TidyTabsService.shared.modelAvailable, !asked.contains(id), !path.isEmpty else { return }
        asked.insert(id)
        let source = sources.removeValue(forKey: id)
        let original = (path as NSString).lastPathComponent
        let prompt = TidyDownloads.prompt(file: original, tabTitle: source?.title ?? "", url: source?.url ?? downloadURL)
        Task { @MainActor in
            guard let answer = await Self.ask(prompt), let name = TidyDownloads.clean(answer, original: original) else { return }
            let folder = (path as NSString).deletingLastPathComponent
            let fm = FileManager.default
            let free = TidyDownloads.unique(name) { fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0)) }
            let newPath = (folder as NSString).appendingPathComponent(free)
            guard fm.fileExists(atPath: path), (try? fm.moveItem(atPath: path, toPath: newPath)) != nil else {
                CraLog.note("Tidy Downloads: the file couldn't be renamed")
                return
            }
            DownloadHistory.shared.move(from: path, to: newPath)
            moved(newPath)
            CraLog.note("Tidy Downloads: renamed a download (\(original.count) → \(free.count) characters)")
            show(Rename(download: id, window: window, oldPath: path, newPath: newPath))
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
        dismiss()
        let fm = FileManager.default
        guard fm.fileExists(atPath: r.newPath) else { return false }
        let folder = (r.oldPath as NSString).deletingLastPathComponent
        let free = TidyDownloads.unique(r.oldName) { fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0)) }
        let back = (folder as NSString).appendingPathComponent(free)
        guard (try? fm.moveItem(atPath: r.newPath, toPath: back)) != nil else { return false }
        DownloadHistory.shared.move(from: r.newPath, to: back)
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
