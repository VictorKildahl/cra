import Foundation

/// Inference deliberately ignores cancellation and can finish in any order.
@MainActor
private final class SuspendedDownloadsModel {
    private(set) var requests: [TidyDownloads.Request] = []
    private var pending: [Int: CheckedContinuation<String?, Never>] = [:]
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    func answer(_ request: TidyDownloads.Request) async -> String? {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuation in
            pending[index] = continuation
            if let (count, continuation) = waiter, requests.count >= count {
                waiter = nil
                continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int = 1) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func complete(_ index: Int = 0, with answer: String?) {
        precondition(pending[index] != nil, "complete an actually suspended request")
        pending.removeValue(forKey: index)?.resume(returning: answer)
    }
}

@MainActor
private final class DownloadFixture {
    let store = SidebarStore(clock: ManualScheduler())
    let model = SuspendedDownloadsModel()
    let folder: URL
    var available = true
    var ownerPresent = true
    private(set) var moved: [UInt32: String] = [:]
    lazy var service = TidyDownloadsService(modelAvailable: { [weak self] in self?.available == true }, generate: model.answer)

    init(_ root: URL) throws {
        folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store.settings.tidyDownloads = true
        let service = service
        store.tidyDownloadsChanged = { [weak service] enabled in if !enabled { service?.cancelAll() } }
    }

    func file(_ name: String = "report_123.pdf") throws -> String {
        let path = folder.appendingPathComponent(name).path
        try Data("original bytes: \(name)".utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    @discardableResult
    func finish(_ id: UInt32 = 1, path: String, window: UUID? = nil) -> Task<Void, Never>? {
        service.finished(id, path: path, downloadURL: "https://example.test/report", window: window ?? store.activeWindowID,
                         store: store, ownerEligible: { [weak self] in self?.ownerPresent == true }) { [weak self] path in
            self?.moved[id] = path
        }
    }

    func capture(_ title: String, id: UInt32 = 1, window: UUID? = nil) {
        service.noteSource(id, window: window ?? store.activeWindowID,
                           tab: TabData(url: "https://source.test/file", title: title), referrer: nil)
    }

    func unchanged(_ path: String) throws {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        precondition(contents == "original bytes: \((path as NSString).lastPathComponent)",
                     "discarded inference preserves the original file bytes and location")
        precondition(moved.isEmpty && service.card == nil, "discarded inference publishes neither path nor card")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(files.count == 1,
                     "discarded inference creates no destination")
    }

    func renamed(_ id: UInt32 = 1, from path: String, to name: String) throws {
        let destination = folder.appendingPathComponent(name).path
        precondition(!FileManager.default.fileExists(atPath: path), "successful rename consumes the source")
        let contents = try String(contentsOfFile: destination, encoding: .utf8)
        precondition(contents == "original bytes: \((path as NSString).lastPathComponent)",
                     "successful rename preserves bytes")
        precondition(moved[id] == destination && service.card?.newPath == destination, "publication follows the actual destination")
    }

}

@MainActor
@main
enum TidyDownloadsServiceTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-download-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("CRA_DATA_DIR", root.appendingPathComponent("profile").path, 1)
        setenv("CRA_TIDY_FAKE_MODEL", "off", 1)
        try await optOut(root)
        try await offThenOn(root)
        try await unavailable(root)
        try await availabilityRefresh(root)
        try await cancellation(root)
        try await ownerTeardown(root)
        try await missingOwner(root)
        try await obsoleteCompletion(root)
        try await independentDownloads(root)
        try await separateOwners(root)
        try await sourceRetirement(root)
        try await sourceTabCloses(root)
        try await rejectedAnswers(root)
        try await storeLifetime(root)
        print("Tidy Downloads lifecycle: 14 cases passed")
    }

    private static func optOut(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        precondition(task != nil)
        await f.model.waitForRequests()
        f.store.settings.tidyDownloads = false
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
    }

    private static func offThenOn(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        // Observation delivery coalesces these; the production store callback must be synchronous.
        f.store.settings.tidyDownloads = false
        f.store.settings.tidyDownloads = true
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
    }

    private static func unavailable(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.available = false // No refresh notification: completion still must re-read availability.
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
    }

    private static func availabilityRefresh(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        let service = f.service
        TidyTabsService.shared.downloadsUnavailable = { [weak service] in service?.cancelAll() }
        // Real refresh reads the process's fixed unavailable model state. Even if the state was
        // already cached as off, refresh must invalidate before a later available response.
        TidyTabsService.shared.refresh()
        TidyTabsService.shared.downloadsUnavailable = {}
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
    }

    private static func cancellation(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        task?.cancel()
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
    }

    private static func ownerTeardown(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.service.cancel(window: f.store.activeWindowID)
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
    }

    private static func missingOwner(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.ownerPresent = false
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        try f.unchanged(path)
        // Store window ownership is independent of the weak controller eligibility callback.
        f.ownerPresent = true
        let other = f.store.addWindow(spaceID: f.store.focusedSpaceID, frame: nil).id
        let removed = f.finish(2, path: path, window: other)
        await f.model.waitForRequests(2)
        f.store.removeWindow(other)
        f.model.complete(1, with: "Annual Report.pdf")
        await removed?.value
        try f.unchanged(path)
    }

    private static func obsoleteCompletion(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        f.capture("Old source")
        let old = f.finish(path: path)
        await f.model.waitForRequests()
        f.service.cancel(1, window: f.store.activeWindowID)
        f.capture("New source")
        let current = f.finish(path: path)
        await f.model.waitForRequests(2)
        f.model.complete(with: "Obsolete.pdf")
        await old?.value
        precondition(f.finish(path: path) == nil, "old cleanup cannot remove the newer in-flight duplicate guard")
        precondition(f.model.requests[1].sourceTitle == "New source", "old source retires with its request")
        f.model.complete(1, with: "Current.pdf")
        await current?.value
        precondition(f.model.requests.count == 2, "duplicate finish starts no extra inference")
        try f.renamed(from: path, to: "Current.pdf")
    }

    private static func independentDownloads(_ root: URL) async throws {
        let f = try DownloadFixture(root), a = try f.file("a_123.pdf"), b = try f.file("b_123.pdf")
        let first = f.finish(1, path: a)
        await f.model.waitForRequests()
        let second = f.finish(2, path: b)
        await f.model.waitForRequests(2)
        f.model.complete(1, with: "Beta.pdf")
        await second?.value
        try f.renamed(2, from: b, to: "Beta.pdf")
        f.model.complete(with: "Alpha.pdf")
        await first?.value
        try f.renamed(1, from: a, to: "Alpha.pdf")
    }

    private static func separateOwners(_ root: URL) async throws {
        let f = try DownloadFixture(root), a = try f.file("a_123.pdf"), b = try f.file("b_123.pdf")
        let other = f.store.addWindow(spaceID: f.store.focusedSpaceID, frame: nil).id
        f.capture("Owner one")
        f.capture("Owner two", window: other)
        let first = f.finish(path: a)
        await f.model.waitForRequests()
        let second = f.finish(path: b, window: other)
        await f.model.waitForRequests(2)
        precondition(f.model.requests.map(\.sourceTitle) == ["Owner one", "Owner two"], "same numeric ID has owner-specific context")
        f.service.cancel(window: f.store.activeWindowID)
        f.model.complete(with: "Discarded.pdf")
        await first?.value
        precondition(FileManager.default.fileExists(atPath: a))
        f.model.complete(1, with: "Other Owner.pdf")
        await second?.value
        try f.renamed(from: b, to: "Other Owner.pdf")
    }

    private static func sourceRetirement(_ root: URL) async throws {
        for disabled in [true, false] {
            let f = try DownloadFixture(root), path = try f.file()
            f.capture("Retired source")
            if disabled { f.store.settings.tidyDownloads = false } else { f.available = false }
            precondition(f.finish(path: path) == nil, "ineligible terminal completion starts no request")
            f.store.settings.tidyDownloads = true
            f.available = true
            let task = f.finish(path: path)
            await f.model.waitForRequests()
            precondition(f.model.requests[0].sourceTitle.isEmpty, "disabled/unavailable completion retires source context")
            f.model.complete(with: nil)
            await task?.value
            try f.unchanged(path)
        }
        for closeWindow in [false, true] {
            let f = try DownloadFixture(root), path = try f.file()
            f.capture("Retired source")
            if closeWindow { f.service.cancel(window: f.store.activeWindowID) }
            else { f.service.cancel(1, window: f.store.activeWindowID) } // Cancel and interruption share this path.
            let task = f.finish(path: path)
            await f.model.waitForRequests()
            precondition(f.model.requests[0].sourceTitle.isEmpty, "cancel/interruption/owner teardown retires source context")
            f.model.complete(with: nil)
            await task?.value
            try f.unchanged(path)
        }
        let f = try DownloadFixture(root), path = try f.file()
        f.capture("Empty-path source")
        precondition(f.finish(path: "") == nil)
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        precondition(f.model.requests[0].sourceTitle.isEmpty, "empty-path completion retires source context")
        f.model.complete(with: nil)
        await task?.value
        try f.unchanged(path)
    }

    private static func sourceTabCloses(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let tab = f.store.createTab(url: "https://source.test", title: "Captured page")
        f.service.noteSource(1, window: f.store.activeWindowID, tab: tab.tab!, referrer: nil)
        f.store.archiveTab(tab.id, reason: .manual)
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        precondition(f.model.requests[0].sourceTitle == "Captured page")
        f.model.complete(with: "Captured.pdf")
        await task?.value
        try f.renamed(from: path, to: "Captured.pdf")
    }

    private static func rejectedAnswers(_ root: URL) async throws {
        let answers: [String?] = [nil, ".pdf", "report_123.pdf"]
        for answer in answers {
            let f = try DownloadFixture(root), path = try f.file()
            let task = f.finish(path: path)
            await f.model.waitForRequests()
            f.model.complete(with: answer)
            await task?.value
            try f.unchanged(path)
            // A retired inference has no global lifetime numeric-ID tombstone.
            let next = f.finish(path: path)
            precondition(next != nil)
            await f.model.waitForRequests(2)
            f.model.complete(1, with: nil)
            await next?.value
        }
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        try FileManager.default.removeItem(atPath: path)
        f.model.complete(with: "Missing.pdf")
        await task?.value
        precondition(f.moved.isEmpty && f.service.card == nil && !FileManager.default.fileExists(atPath: f.folder.appendingPathComponent("Missing.pdf").path))
    }

    private static func storeLifetime(_ root: URL) async throws {
        let model = SuspendedDownloadsModel()
        let service = TidyDownloadsService(modelAvailable: { true }, generate: model.answer)
        var store: SidebarStore? = SidebarStore(clock: ManualScheduler())
        store!.settings.tidyDownloads = true
        let storeIsReleased = { [weak store] in store == nil }
        let path = root.appendingPathComponent("lifetime_123.pdf").path
        try Data("unchanged".utf8).write(to: URL(fileURLWithPath: path))
        let task = service.finished(1, path: path, downloadURL: "https://example.test", window: store!.activeWindowID,
                                    store: store!, ownerEligible: { true }) { _ in preconditionFailure("released store cannot publish") }
        await model.waitForRequests()
        store = nil
        precondition(storeIsReleased(), "suspended inference must not retain the production store")
        model.complete(with: "Should Not Move.pdf")
        await task?.value
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        precondition(contents == "unchanged" && service.card == nil)
    }
}
