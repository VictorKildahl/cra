import Foundation

@MainActor private final class SuspendedDownloadAnswers {
    private var pending: [Int: CheckedContinuation<String?, Never>] = [:]
    private var waiting: (Int, CheckedContinuation<Void, Never>)?
    private(set) var count = 0
    func answer(_ prompt: String) async -> String? {
        let index = count
        count += 1
        return await withCheckedContinuation { continuation in
            pending[index] = continuation
            if let (wanted, waiter) = waiting, count >= wanted { waiting = nil; waiter.resume() }
        }
    }
    func wait(_ wanted: Int) async {
        if count >= wanted { return }
        await withCheckedContinuation { waiting = (wanted, $0) }
    }
    func complete(_ index: Int, _ answer: String?) { pending.removeValue(forKey: index)!.resume(returning: answer) }
}

@MainActor private final class PreparationReadiness {
    private var entered = false
    private var entrance: CheckedContinuation<Void, Never>?
    private var released = false
    private var release: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        entrance?.resume(); entrance = nil
        if !released { await withCheckedContinuation { release = $0 } }
    }
    func waitForEntry() async {
        if !entered { await withCheckedContinuation { entrance = $0 } }
    }
    func allow() { released = true; release?.resume(); release = nil }
}

@main @MainActor enum SharedDownloadReplacementTests {
    private static var checks = 0
    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }
    private static func prepare(_ url: URL, replacing: Bool, service: TidyDownloadsService) async -> URL? {
        await withCheckedContinuation { continuation in
            DownloadDestinations.prepare(url, replacing: replacing, service: service) { continuation.resume(returning: $0) }
        }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-shared-download-replacement-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await pendingReplacement(root)
        try await replacementBeforeHistory(root)
        try await reservationBeforeWriter(root)
        try await aliasReservation(root)
        try await destinationAppearsDuringPreparation(root)
        try await resourceReplacedWithoutPreparation(root)
        try await staleUndoAndHistory(root)
        try await undoDifferentResource(root)
        try await failedPreparation(root)
        try await nilAndCEFPreparation(root)
        print("Shared download replacement: \(checks) checks passed")
    }
    private static func folder(_ root: URL) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private static func pendingReplacement(_ base: URL) async throws {
        let root = try folder(base)
        let path = root.appendingPathComponent("download.pdf")
        try Data("A original payload".utf8).write(to: path)
        let history = DownloadHistory.shared
        let a = history.add(path: path.path)
        let answers = SuspendedDownloadAnswers(), store = SidebarStore(), window = UUID()
        let service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true }, removeExisting: {
            try FileManager.default.removeItem(atPath: $0)
        })
        var moves: [UInt32: String] = [:]
        let taskA = service.finished(1, path: path.path, downloadURL: "https://example.test/a", window: window, store: store) { moves[1] = $0 }!
        await answers.wait(1)
        // B starts before its history row exists; the actual destination callback gates its write.
        expect(await prepare(path, replacing: true, service: service) == path, "approved replacement gets its destination")
        try Data("B replacement payload".utf8).write(to: path)
        let b = history.add(path: path.path)
        let taskB = service.finished(2, path: path.path, downloadURL: "https://example.test/b", window: window, store: store) { moves[2] = $0 }!
        await answers.wait(2)
        answers.complete(0, "Answer for A.pdf")
        await taskA.value
        expect(moves[1] == nil, "stale A cannot rename B's replacement file")
        expect((try? String(contentsOf: path, encoding: .utf8)) == "B replacement payload", "replacement payload remains at B's destination")
        expect(history.entries.first { $0.id == a.id }?.path == path.path, "A history row is not rebound to B")
        expect(history.entries.first { $0.id == b.id }?.path == path.path, "B history stays at its own path until B answers")
        answers.complete(1, "Answer for B.pdf")
        await taskB.value
        let bPath = root.appendingPathComponent("Answer for B.pdf")
        expect(moves[2] == bPath.path && (try? String(contentsOf: bPath, encoding: .utf8)) == "B replacement payload", "current B can rename its own payload")
        expect(history.entries.first { $0.id == b.id }?.path == bPath.path, "B keeps its captured history UUID")
        service.dismiss()
    }
    private static func replacementBeforeHistory(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("pending.pdf")
        try Data("A payload".utf8).write(to: path)
        let history = DownloadHistory.shared, a = history.add(path: path.path)
        let answers = SuspendedDownloadAnswers(), store = SidebarStore()
        let service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true }, removeExisting: { try FileManager.default.removeItem(atPath: $0) })
        var moved = false
        let task = service.finished(10, path: path.path, downloadURL: "https://example.test/a", window: UUID(), store: store) { _ in moved = true }!
        await answers.wait(1)
        // Admission must revoke synchronously, before the preparation task can run or B has history.
        let preparation = service.prepareDestination(path.path, replacing: true)
        answers.complete(0, "A late answer.pdf")
        expect(await preparation.value, "replacement preparation completes")
        try Data("B unfinished payload".utf8).write(to: path)
        await task.value
        expect(!moved && (try? String(contentsOf: path, encoding: .utf8)) == "B unfinished payload", "reservation before B history prevents A's stale mutation")
        expect(history.entries.first { $0.id == a.id }?.path == path.path, "A history identity is retained while B is incomplete")
    }
    private static func reservationBeforeWriter(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("before-writer.pdf")
        try Data("original still present".utf8).write(to: path)
        _ = DownloadHistory.shared.add(path: path.path)
        let answers = SuspendedDownloadAnswers(), service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true })
        var moved = false
        let task = service.finished(15, path: path.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in moved = true }!
        await answers.wait(1)
        let preparation = service.prepareDestination(path.path, replacing: false)
        answers.complete(0, "Old answer.pdf")
        await task.value
        expect(await preparation.value, "CEF may start only after reservation")
        expect(!moved && FileManager.default.fileExists(atPath: path.path), "reservation alone revokes old model before a new writer changes identity")
    }
    private static func aliasReservation(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("resource.pdf"), alias = root.appendingPathComponent("alias.pdf")
        try Data("shared inode".utf8).write(to: path)
        try FileManager.default.linkItem(at: path, to: alias)
        expect(TidyDownloadsService.FileIdentity(at: path.path) == TidyDownloadsService.FileIdentity(at: alias.path), "same-volume alias fixture shares actual device/inode")
        _ = DownloadHistory.shared.add(path: path.path)
        let answers = SuspendedDownloadAnswers(), service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true })
        var moved = false
        let task = service.finished(16, path: path.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in moved = true }!
        await answers.wait(1)
        expect(await prepare(alias, replacing: false, service: service) == alias, "alias destination is reserved before engine write")
        // CEF can truncate an approved occupied path without replacing its inode.
        let handle = try FileHandle(forWritingTo: alias)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("replacement via alias".utf8))
        try handle.close()
        answers.complete(0, "Old alias answer.pdf")
        await task.value
        expect(!moved && (try? String(contentsOf: path, encoding: .utf8)) == "replacement via alias", "matching resource reservation invalidates aliases even for in-place engine writes")
    }
    private static func destinationAppearsDuringPreparation(_ base: URL) async throws {
        let root = try folder(base), original = root.appendingPathComponent("preparing.pdf"), chosen = root.appendingPathComponent("Arrived while preparing.pdf")
        try Data("A original payload".utf8).write(to: original)
        _ = DownloadHistory.shared.add(path: original.path)
        let answers = SuspendedDownloadAnswers(), readiness = PreparationReadiness()
        let service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true }, beforePreparation: readiness.suspend,
            removeExisting: { _ in fatalError("CEF performs its own replacement") })
        let taskA = service.finished(17, path: original.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in }!
        await answers.wait(1)
        expect(!FileManager.default.fileExists(atPath: chosen.path), "B chooses a path that has no resource at reservation time")
        let handoff = Task { await prepare(chosen, replacing: false, service: service) }
        await readiness.waitForEntry()
        answers.complete(0, chosen.lastPathComponent)
        await taskA.value
        let rename = service.card!
        expect(rename.newPath == chosen.path && FileManager.default.fileExists(atPath: chosen.path), "A's real rename arrives while B's preparation is suspended")
        readiness.allow()
        expect(await handoff.value == chosen, "B receives the prepared destination")
        expect(service.card == nil, "preparation revalidates newly arrived resource/card before engine handoff")
        // The subsequent engine write can keep the inode: card invalidation must protect undo.
        let handle = try FileHandle(forWritingTo: chosen)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("B in-place replacement".utf8))
        try handle.close()
        expect(!service.revert(rename) { _, _ in }, "pre-handoff resource invalidation rejects stale undo after in-place write")
        expect((try? String(contentsOf: chosen, encoding: .utf8)) == "B in-place replacement", "B's bytes survive the stale undo")
    }
    private static func resourceReplacedWithoutPreparation(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("identity.pdf")
        try Data("original".utf8).write(to: path)
        _ = DownloadHistory.shared.add(path: path.path)
        let answers = SuspendedDownloadAnswers(), service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true })
        var moved = false
        let task = service.finished(20, path: path.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in moved = true }!
        // Change the resource before the task first runs, proving capture precedes task creation.
        try FileManager.default.moveItem(at: path, to: root.appendingPathComponent("kept-original.pdf"))
        try Data("different resource".utf8).write(to: path)
        await answers.wait(1)
        answers.complete(0, "Wrong resource.pdf")
        await task.value
        expect(!moved && (try? String(contentsOf: path, encoding: .utf8)) == "different resource", "resource identity is captured before model task admission")
    }
    private static func staleUndoAndHistory(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("undo.pdf")
        try Data("undo original".utf8).write(to: path)
        let history = DownloadHistory.shared, original = history.add(path: path.path)
        let answers = SuspendedDownloadAnswers(), service = TidyDownloadsService(generate: answers.answer, modelAvailable: { true }, removeExisting: { try FileManager.default.removeItem(atPath: $0) })
        let task = service.finished(30, path: path.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in }!
        // Add the newer row before the model task can even start. The old row is already captured.
        let unrelated = history.add(path: path.path)
        await answers.wait(1)
        answers.complete(0, "Renamed original.pdf")
        await task.value
        let rename = service.card!
        expect(history.entries.first { $0.id == original.id }?.path == rename.newPath, "rename updates captured history UUID")
        expect(history.entries.first { $0.id == unrelated.id }?.path == path.path, "later same-path history row is unchanged")
        expect(await prepare(URL(fileURLWithPath: rename.newPath), replacing: true, service: service) != nil, "replace current renamed destination")
        expect(service.card == nil, "new writer synchronously invalidates the matching undo card")
        try Data("replacement of renamed file".utf8).write(to: URL(fileURLWithPath: rename.newPath))
        var reverted = false
        expect(!service.revert(rename) { _, _ in reverted = true }, "stale undo cannot move replacement resource")
        expect(!reverted && (try? String(contentsOfFile: rename.newPath, encoding: .utf8)) == "replacement of renamed file", "failed stale undo preserves replacement bytes")
        // A fresh ordinary rename/revert still works and keeps its original history row.
        let fresh = root.appendingPathComponent("fresh.pdf")
        try Data("fresh payload".utf8).write(to: fresh)
        let entry = history.add(path: fresh.path)
        let immediate = TidyDownloadsService(generate: { _ in "Fresh readable.pdf" }, modelAvailable: { true })
        await immediate.finished(31, path: fresh.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in }!.value
        let current = immediate.card!
        expect(immediate.revert(current) { _, _ in }, "ordinary current-resource undo succeeds")
        expect(history.entries.first { $0.id == entry.id }?.path == fresh.path && FileManager.default.fileExists(atPath: fresh.path), "undo updates its captured original history row")
        expect(!immediate.revert(current) { _, _ in }, "repeated undo is harmless")
    }
    private static func undoDifferentResource(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("undo-identity.pdf")
        try Data("original undo bytes".utf8).write(to: path)
        _ = DownloadHistory.shared.add(path: path.path)
        let service = TidyDownloadsService(generate: { _ in "Readable undo.pdf" }, modelAvailable: { true })
        await service.finished(40, path: path.path, downloadURL: "https://example.test/a", window: UUID(), store: SidebarStore()) { _ in }!.value
        let rename = service.card!
        try FileManager.default.moveItem(atPath: rename.newPath, toPath: root.appendingPathComponent("kept-undo-resource.pdf").path)
        try Data("different undo resource".utf8).write(to: URL(fileURLWithPath: rename.newPath))
        expect(!service.revert(rename) { _, _ in }, "resource identity rejects undo even when its card is still current")
        expect((try? String(contentsOfFile: rename.newPath, encoding: .utf8)) == "different undo resource", "rejected undo preserves different resource")
        service.dismiss()
    }
    private static func failedPreparation(_ base: URL) async throws {
        enum Failure: Error { case denied }
        let root = try folder(base), path = root.appendingPathComponent("denied.pdf")
        try Data("retained payload".utf8).write(to: path)
        let service = TidyDownloadsService(modelAvailable: { true }, removeExisting: { _ in throw Failure.denied })
        expect(await prepare(path, replacing: true, service: service) == nil, "failed approved removal cancels engine destination")
        expect((try? String(contentsOf: path, encoding: .utf8)) == "retained payload", "failed replacement preserves existing resource")
    }
    private static func nilAndCEFPreparation(_ base: URL) async throws {
        let root = try folder(base), path = root.appendingPathComponent("cef.pdf")
        try Data("CEF handles replacement".utf8).write(to: path)
        let service = TidyDownloadsService(removeExisting: { _ in fatalError("CEF must not trash here") })
        expect(await prepare(path, replacing: false, service: service) == path, "CEF destination is gated without local trash")
        expect(FileManager.default.fileExists(atPath: path.path), "CEF retains responsibility for its engine replacement")
        let cancelled: URL? = await withCheckedContinuation { continuation in
            DownloadDestinations.prepare(nil, replacing: true, service: service) { continuation.resume(returning: $0) }
        }
        expect(cancelled == nil, "cancelled destination remains nil")
    }

}
