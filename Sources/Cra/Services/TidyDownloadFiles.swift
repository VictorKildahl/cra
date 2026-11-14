import Foundation

/// Renames and handing a destination back to a download share this serial filesystem boundary.
/// A replacement starts only after any earlier rename/undo has finished its physical move.
actor TidyDownloadFiles {
    static let shared = TidyDownloadFiles()
    private var pendingMoves: [UUID: (path: String, identity: Identity?)] = [:]

    struct Identity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    struct Move: Sendable {
        let from: String
        let to: String
    }

    struct Preparation: Sendable {
        let ready: Bool
        let previous: Identity?
    }

    typealias RemoveExisting = @Sendable (String) throws -> Void

    nonisolated static func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }

    /// The request is already cancelled if a newer download claimed its path before this work ran.
    func identity(at path: String) -> Identity? {
        guard !Task.isCancelled else { return nil }
        return Self.fileIdentity(at: path)
    }

    private static func fileIdentity(at path: String) -> Identity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return Identity(device: device.uint64Value, inode: inode.uint64Value)
    }

    /// Runs after synchronous request invalidation, before CEF/WebKit may start writing.
    func prepareDestination(_ path: String, replacing: Bool, removeExisting: RemoveExisting) -> Preparation {
        let previous = Self.fileIdentity(at: path)
        let revoked = pendingMoves.keys.filter {
            pendingMoves[$0]?.path == path || (previous != nil && pendingMoves[$0]?.identity == previous)
        }
        for ticket in revoked { pendingMoves[ticket] = nil }
        do {
            if replacing, FileManager.default.fileExists(atPath: path) { try removeExisting(path) }
            return Preparation(ready: true, previous: previous)
        } catch {
            CraLog.note("Download destination: the previous file couldn't be replaced")
            return Preparation(ready: false, previous: previous)
        }
    }

    func move(from source: String, name: String, identity: Identity? = nil,
              eligible: @escaping @MainActor @Sendable () -> Bool) async -> Move? {
        guard !Task.isCancelled else { return nil }
        // Eligibility hops to MainActor and permits actor reentry. A reservation revokes this
        // transient admission even when an undo is not cancelled and the writer keeps its inode.
        let ticket = UUID()
        pendingMoves[ticket] = (source, identity ?? Self.fileIdentity(at: source))
        defer { pendingMoves[ticket] = nil }
        guard await eligible(), pendingMoves[ticket] != nil, !Task.isCancelled else { return nil }
        let fm = FileManager.default
        let folder = (source as NSString).deletingLastPathComponent
        let free: String? = TidyDownloads.unique(name, existing: {
            fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0))
        })
        guard fm.fileExists(atPath: source), identity == nil || Self.fileIdentity(at: source) == identity,
              let free else { return nil }
        let destination = (folder as NSString).appendingPathComponent(free)
        // Replacement invalidates before joining this actor. Its writer cannot begin until our
        // synchronous move returns, so cancellation cannot race with a replacement's file writes.
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
