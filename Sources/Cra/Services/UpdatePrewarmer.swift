import Foundation

/// Runs a downloaded update once, hidden, while it waits to be installed, so the first launch
/// after the update doesn't wait for macOS to check the new bundle (CraCore `UpdatePrewarm`).
@MainActor
final class UpdatePrewarmer {
    private let clock: Scheduler
    private var build: String?
    private var lastRun: Date?
    private var repeating: ScheduledWork?
    private var running: Process?

    init(clock: Scheduler) { self.clock = clock }

    /// Sparkle extracted `build` and keeps it until Cra quits or restarts into it.
    func staged(build: String) {
        guard build != self.build else { return }
        self.build = build
        lastRun = nil
        runIfDue()
        repeating?.cancel()
        repeating = clock.every(60) { [weak self] in self?.runIfDue() }
    }

    func stop() {
        repeating?.cancel()
        repeating = nil
        build = nil
    }

    private func runIfDue() {
        guard let build, running == nil, UpdatePrewarm.isDue(lastRun: lastRun, now: clock.now),
              let id = Bundle.main.bundleIdentifier else { return }
        lastRun = clock.now
        Task.detached(priority: .utility) {
            let picked = UpdatePrewarm.pick(Self.stagedCopies(bundleID: id), version: build, bundleID: id)
            await MainActor.run { self.run(picked) }
        }
    }

    private func run(_ copy: UpdatePrewarm.Candidate?) {
        guard let copy, let exe = Bundle(path: copy.path)?.executableURL else {
            CraLog.note("update prewarm: no staged copy of \(build ?? "?") found")
            return
        }
        let app = URL(fileURLWithPath: copy.path)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: app.appendingPathComponent("Contents/Frameworks").path)) ?? []
        let programs = [exe] + UpdatePrewarm.helperExecutables(frameworkEntries: entries).map { app.appendingPathComponent($0) }
        runNext(programs[...], copy: copy, started: Date())
    }

    /// The main program, then each helper, one at a time.
    private func runNext(_ programs: ArraySlice<URL>, copy: UpdatePrewarm.Candidate, started: Date) {
        guard let exe = programs.first else {
            CraLog.note("update prewarm: \(copy.path) ran in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            running = nil
            return
        }
        let p = Process()
        p.executableURL = exe
        p.environment = [UpdatePrewarm.environmentKey: "1"]
        p.qualityOfService = .utility
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.runNext(programs.dropFirst(), copy: copy, started: started) }
        }
        do {
            try p.run()
            running = p
            clock.after(UpdatePrewarm.timeout) { [weak self] in
                guard let self, let r = self.running, r === p, r.isRunning else { return }
                CraLog.note("update prewarm: \(exe.lastPathComponent) still running after \(Int(UpdatePrewarm.timeout)) s; stopped")
                r.terminate()
            }
        } catch {
            CraLog.note("update prewarm: \(exe.lastPathComponent): \(error.localizedDescription)")
            runNext(programs.dropFirst(), copy: copy, started: started)
        }
    }

    /// Every app bundle in Sparkle's installation folder for this app (a few levels down: Sparkle
    /// keeps each update in its own folder, and its layout differs between versions).
    nonisolated static func stagedCopies(bundleID: String) -> [UpdatePrewarm.Candidate] {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
        let root = caches.appendingPathComponent(bundleID).appendingPathComponent("org.sparkle-project.Sparkle/Installation")
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [UpdatePrewarm.Candidate] = []
        for case let url as URL in walk {
            if walk.level > 4 { walk.skipDescendants(); continue }
            guard url.pathExtension == "app" else { continue }
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            found.append(.init(path: url.path, version: info?["CFBundleVersion"] as? String,
                               bundleID: info?["CFBundleIdentifier"] as? String, modified: modified))
        }
        return found
    }
}
