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
    var moveFile: TidyDownloadsService.MoveFile = { await TidyDownloadFiles.shared.move(from: $0, name: $1, eligible: $2) }
    private(set) var moved: [UInt32: String] = [:]
    lazy var service = TidyDownloadsService(modelAvailable: { [weak self] in self?.available == true }, generate: model.answer, moveFile: moveFile)

    init(_ root: URL, moveFile: TidyDownloadsService.MoveFile? = nil) throws {
        if let moveFile { self.moveFile = moveFile }
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
        DownloadHistory.shared.add(path: path)
        return service.finished(id, path: path, downloadURL: "https://example.test/report", window: window ?? store.activeWindowID,
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

/// Suspends at the actual filesystem seam, without sleeps or fake move outcomes.
@MainActor
private final class MoveGate {
    let afterMove: Bool
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var resumeMove: CheckedContinuation<Void, Never>?

    init(afterMove: Bool) { self.afterMove = afterMove }

    func move(_ path: String, _ name: String, _ eligible: @escaping @MainActor @Sendable () -> Bool) async -> TidyDownloadFiles.Move? {
        if !afterMove { await pause() }
        let result = await TidyDownloadFiles.shared.move(from: path, name: name, eligible: eligible)
        if afterMove { await pause() }
        return result
    }

    private func pause() async {
        await withCheckedContinuation { continuation in
            resumeMove = continuation
            entered = true
            waiter?.resume()
            waiter = nil
        }
    }

    func wait() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() { resumeMove?.resume(); resumeMove = nil }
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
        try await hiddenHistoryMustNotMoveNewerRow(root)
        try await undoHiddenHistoryPathReuse(root)
        try await failedUndoKeepsCard(root)
        try await filesystemOutcomes(root)
        try await cancellationAtMove(root)
        try await undoConsistency(root)
        try await undoInFlight(root)
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
        print("Tidy Downloads lifecycle/filesystem/undo: 21 cases passed")
    }

    private static func hiddenHistoryMustNotMoveNewerRow(_ root: URL) async throws {
        let gate = MoveGate(afterMove: true)
        let f = try DownloadFixture(root, moveFile: { await gate.move($0, $1, $2) }), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        let original = DownloadHistory.shared.entries.last!
        DownloadHistory.shared.hide(.finished(original))
        f.model.complete(with: "Annual Report.pdf")
        await gate.wait()
        try Data("new download bytes".utf8).write(to: URL(fileURLWithPath: path))
        let newer = DownloadHistory.shared.add(path: path)
        gate.release()
        await task?.value
        let actual = DownloadHistory.shared.entries.first(where: { $0.id == newer.id })!
        precondition(actual.path == path,
                     "a completed move without its history row must not rename a newer row at the reused source path")
        let newerBytes = try String(contentsOfFile: path, encoding: .utf8)
        precondition(newerBytes == "new download bytes")
        let destination = f.folder.appendingPathComponent("Annual Report.pdf").path
        let movedBytes = try String(contentsOfFile: destination, encoding: .utf8)
        precondition(movedBytes == "original bytes: report_123.pdf" && f.moved[1] == destination,
                     "a completed move still reconciles its actual destination without a history row")
        let card = f.service.card!
        let undo = await f.service.revert(card) { _, _ in preconditionFailure("absent history cannot authorize undo") }
        precondition(!undo && f.service.card == card && FileManager.default.fileExists(atPath: destination))
    }

    private static func failedUndoKeepsCard(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        let card = f.service.card!
        try FileManager.default.removeItem(atPath: card.newPath)
        let success = await f.service.revert(card) { _, _ in preconditionFailure("failed undo cannot publish") }
        precondition(!success && f.service.card == card, "failed undo must preserve the current rename card")
    }

    private static func filesystemOutcomes(_ root: URL) async throws {
        let f = try DownloadFixture(root)
        let a = try f.file("first.pdf"), b = try f.file("second.pdf")
        let occupied = try f.file("Report.pdf")
        async let first = TidyDownloadFiles.shared.move(from: a, name: "Report.pdf", eligible: { true })
        async let second = TidyDownloadFiles.shared.move(from: b, name: "Report.pdf", eligible: { true })
        let results = await [first, second].compactMap { $0 }
        precondition(Set(results.map { ($0.to as NSString).lastPathComponent }) == ["Report (1).pdf", "Report (2).pdf"], "serial concurrent moves choose distinct actual destinations")
        for result in results {
            let bytes = try String(contentsOfFile: result.to, encoding: .utf8)
            precondition(bytes == "original bytes: \((result.from as NSString).lastPathComponent)")
            precondition(!FileManager.default.fileExists(atPath: result.from))
        }
        let collisionBytes = try String(contentsOfFile: occupied, encoding: .utf8)
        precondition(collisionBytes == "original bytes: Report.pdf", "colliding file is untouched")
        let missing = await TidyDownloadFiles.shared.move(from: a, name: "Missing.pdf", eligible: { true })
        precondition(missing == nil)
        let source = try f.file("source.pdf")
        let failed = await TidyDownloadFiles.shared.move(from: source, name: "nonexistent/Report.pdf", eligible: { true })
        precondition(failed == nil && FileManager.default.fileExists(atPath: source), "move error preserves source")
        for index in 0...100 { _ = try f.file(index == 0 ? "Full.pdf" : "Full (\(index)).pdf") }
        let full = await TidyDownloadFiles.shared.move(from: source, name: "Full.pdf", eligible: { true })
        precondition(full == nil && FileManager.default.fileExists(atPath: source), "101 occupied candidates return no move")
        try FileManager.default.removeItem(atPath: f.folder.appendingPathComponent("Full (100).pdf").path)
        let last = await TidyDownloadFiles.shared.move(from: source, name: "Full.pdf", eligible: { true })
        precondition(last?.to == f.folder.appendingPathComponent("Full (100).pdf").path)
    }

    private static func cancellationAtMove(_ root: URL) async throws {
        for afterMove in [false, true] {
            let gate = MoveGate(afterMove: afterMove)
            let f = try DownloadFixture(root, moveFile: { await gate.move($0, $1, $2) }), path = try f.file()
            let task = f.finish(path: path)
            await f.model.waitForRequests()
            f.model.complete(with: "Annual Report.pdf")
            await gate.wait()
            // Synchronous preference invalidation cancels even when disk work is queued/running.
            f.store.settings.tidyDownloads = false
            gate.release()
            await task?.value
            if afterMove {
                let destination = f.folder.appendingPathComponent("Annual Report.pdf").path
                precondition(!FileManager.default.fileExists(atPath: path) && FileManager.default.fileExists(atPath: destination))
                precondition(DownloadHistory.shared.entries.last?.path == destination && f.moved[1] == destination,
                             "cancellation after physical move must still reconcile real history and recent publication")
                precondition(f.service.card == nil, "cancelled move suppresses stale card only")
            } else {
                try f.unchanged(path)
                precondition(DownloadHistory.shared.entries.last?.path == path)
            }
        }
    }

    private static func undoConsistency(_ root: URL) async throws {
        let f = try DownloadFixture(root), path = try f.file()
        let unrelated = DownloadHistory.shared.add(path: try f.file("unrelated.pdf"))
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        let card = f.service.card!
        let history = DownloadHistory.shared.entries.last!
        let duplicate = DownloadHistory.shared.add(path: card.newPath)
        _ = try f.file() // The original path was reused: undo must choose the next Arc candidate.
        var published: (String, String)?
        let success = await f.service.revert(card) { published = ($0, $1) }
        let back = f.folder.appendingPathComponent("report_123 (1).pdf").path
        precondition(success && published?.0 == card.newPath && published?.1 == back && f.service.card == nil)
        let restored = try String(contentsOfFile: back, encoding: .utf8)
        precondition(restored == "original bytes: report_123.pdf")
        precondition(DownloadHistory.shared.entries.contains(where: { $0.id == history.id && $0.path == back }))
        precondition(DownloadHistory.shared.entries.contains(duplicate), "undo updates its recorded history ID, not a newer row at the same path")
        precondition(DownloadHistory.shared.entries.contains(unrelated), "undo preserves unrelated real history entries")
        let repeated = await f.service.revert(card) { _, _ in preconditionFailure("repeated undo cannot publish") }
        precondition(!repeated && FileManager.default.fileExists(atPath: path))
        let next = f.finish(2, path: try f.file("other.pdf"))
        await f.model.waitForRequests(2)
        f.model.complete(1, with: "Other Report.pdf")
        await next?.value
        let current = f.service.card!
        let stale = await f.service.revert(card) { _, _ in preconditionFailure("stale undo cannot publish") }
        precondition(!stale && f.service.card == current)
        DownloadHistory.shared.move(from: current.newPath, to: "different-recorded-path")
        let mismatched = await f.service.revert(current) { _, _ in preconditionFailure("mismatched history cannot publish") }
        precondition(!mismatched && f.service.card == current && FileManager.default.fileExists(atPath: current.newPath))
    }

    private static func undoInFlight(_ root: URL) async throws {
        let gate = MoveGate(afterMove: true)
        let f = try DownloadFixture(root, moveFile: { path, name, eligible in
            if name == "report_123.pdf" { return await gate.move(path, name, eligible) }
            return await TidyDownloadFiles.shared.move(from: path, name: name, eligible: eligible)
        })
        let path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        let card = f.service.card!
        let undo = Task { await f.service.revert(card) { _, back in
            precondition(back == path)
        } }
        await gate.wait()
        let repeated = await f.service.revert(card) { _, _ in preconditionFailure("parallel undo cannot publish") }
        precondition(!repeated)
        let nextPath = try f.file("another.pdf")
        let next = f.finish(2, path: nextPath)
        await f.model.waitForRequests(2)
        f.model.complete(1, with: "Newer Report.pdf")
        await next?.value
        let newer = f.service.card!
        undo.cancel()
        gate.release()
        let success = await undo.value
        precondition(success && f.service.card == newer
                     && DownloadHistory.shared.entries.contains(where: { $0.id == card.historyID && $0.path == path }),
                     "completed undo reconciles despite cancellation and preserves a newer card")
    }

    private static func undoHiddenHistoryPathReuse(_ root: URL) async throws {
        let gate = MoveGate(afterMove: true)
        let f = try DownloadFixture(root, moveFile: { path, name, eligible in
            if name == "report_123.pdf" { return await gate.move(path, name, eligible) }
            return await TidyDownloadFiles.shared.move(from: path, name: name, eligible: eligible)
        })
        let path = try f.file()
        let task = f.finish(path: path)
        await f.model.waitForRequests()
        f.model.complete(with: "Annual Report.pdf")
        await task?.value
        let card = f.service.card!
        var published: String?
        let undo = Task { await f.service.revert(card) { _, back in published = back } }
        await gate.wait()
        let original = DownloadHistory.shared.entries.first(where: { $0.id == card.historyID })!
        DownloadHistory.shared.hide(.finished(original))
        try Data("new download bytes".utf8).write(to: URL(fileURLWithPath: card.newPath))
        let newer = DownloadHistory.shared.add(path: card.newPath)
        gate.release()
        let success = await undo.value
        precondition(success && published == path && f.service.card == nil,
                     "a completed undo still reconciles its actual destination after its history is hidden")
        precondition(DownloadHistory.shared.entries.contains(newer), "completed undo must preserve newer history at the reused source path")
        let newerBytes = try String(contentsOfFile: card.newPath, encoding: .utf8)
        let restoredBytes = try String(contentsOfFile: path, encoding: .utf8)
        precondition(newerBytes == "new download bytes" && restoredBytes == "original bytes: report_123.pdf")
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
