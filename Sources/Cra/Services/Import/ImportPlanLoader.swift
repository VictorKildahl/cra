import Foundation

/// The import window's plan reads (ImportFlowModel.load): off the main thread, since a big
/// archive and its icons take a while (#748), and only the last browser picked gets its plan.
@MainActor
final class ImportPlanLoader {
    /// Counts `load` and `cancel` calls, so a read for an earlier pick is dropped.
    private var count = 0

    /// Runs `read` on a background thread and hands its result to `done` on the main actor,
    /// unless another `load` or `cancel` came after it.
    func load(_ read: @escaping @Sendable () throws -> ImportPlan, done: @escaping (Result<ImportPlan, Error>) -> Void) {
        count += 1
        let pick = count
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { Result { try read() } }.value
            guard pick == count else { return }
            done(result)
        }
    }

    /// Drops the read in flight, for a pick that needs none (Full Disk Access, Safari's export).
    func cancel() { count += 1 }
}
