import Foundation

/// Serial, feature-local filesystem boundary. No main-actor disk queries or moves.
actor TidyDownloadFiles {
    static let shared = TidyDownloadFiles()

    struct Move: Sendable {
        let from: String
        let to: String
    }

    func move(from source: String, name: String,
              eligible: @escaping @MainActor @Sendable () -> Bool) async -> Move? {
        guard !Task.isCancelled, await eligible() else { return nil }
        let fm = FileManager.default
        let folder = (source as NSString).deletingLastPathComponent
        guard fm.fileExists(atPath: source), let free = TidyDownloads.unique(name, existing: {
            fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0))
        }) else { return nil }
        let destination = (folder as NSString).appendingPathComponent(free)
        // Setting/owner invalidation cancels the owning task, including during collision queries.
        guard !Task.isCancelled else { return nil }
        do {
            try fm.moveItem(atPath: source, toPath: destination)
            return Move(from: source, to: destination)
        } catch {
            CraLog.note("Tidy Downloads: the file couldn't be renamed")
            return nil
        }
    }
}
