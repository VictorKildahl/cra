import AppKit
import Foundation

/// Settings ▸ Privacy ▸ Data, and onboarding's "Help improve Cra" row (CraCore Sharing): the
/// daily usage stats and the crash reports, posted to crabrowser.app. Nothing goes out unless the
/// user turned it on, except a crash report they chose to send from the dialog. Only the
/// released app reports (Sharing.mayReport); CRA_SHARING_ENDPOINT=http://127.0.0.1:<port> points
/// a test copy at a local server. docs/sharing.md lists every field.
@MainActor
final class SharingService {
    static let shared = SharingService()

    private var store: SidebarStore?
    private var clock: Scheduler = LiveScheduler.shared
    private var repeating: ScheduledWork?
    private var asking = false
    private let file = JSONStore<SharingState>("sharing.json")
    private lazy var state = file.load { SharingState() }
    private let endpointBase = ProcessInfo.processInfo.environment["CRA_SHARING_ENDPOINT"]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Cra"]
        return URLSession(configuration: config)
    }()

    var mayReport: Bool {
        Sharing.mayReport(hasUpdateFeed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
                          testDataFolder: ProcessInfo.processInfo.environment["CRA_DATA_DIR"] != nil,
                          bundleID: Bundle.main.bundleIdentifier, endpointOverride: endpointBase != nil)
    }

    func start(store: SidebarStore, clock: Scheduler) {
        guard self.store == nil else { return }
        self.store = store
        self.clock = clock
        guard mayReport else { return }
        CraLog.note("sharing: stats \(store.settings.shareUsageStats ? "on" : "off"), crash reports \(store.settings.crashReports.rawValue)")
        // After the windows and pages have settled, and again every few hours for a Mac left running.
        clock.after(30) { [weak self] in
            self?.checkCrashReports()
            self?.sendStatsIfDue()
        }
        repeating = clock.every(6 * 3600) { [weak self] in self?.sendStatsIfDue() }
        // Turned on while Cra runs (onboarding's row, Settings ▸ Privacy): today's report now, not
        // in six hours. The first read is the launch value, which the check above covers.
        var launched = false
        observeChanges(of: { [store] in store.settings.shareUsageStats }) { [weak self] on in
            defer { launched = true }
            if launched, on { self?.sendStatsIfDue() }
        }
    }

    // MARK: - Usage stats

    func currentStats() -> UsageStats? {
        guard let store else { return nil }
        let info = Bundle.main.infoDictionary
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return UsageStats(id: UUID(), version: info?["CFBundleShortVersionString"] as? String ?? "?",
                          build: info?["CFBundleVersion"] as? String ?? "?",
                          os: ProcessInfo.processInfo.operatingSystemVersion, arch: arch,
                          memoryBytes: ProcessInfo.processInfo.physicalMemory,
                          spaces: store.spaces.count, profiles: store.profiles.count, tabs: store.allTabs().count,
                          extensions: ExtensionStore.shared.entries.count, settings: store.settings)
    }

    func sendStatsIfDue(force: Bool = false) {
        guard mayReport, let store else { return }
        guard store.settings.shareUsageStats else {
            if force { CraLog.note("sharing: usage stats off, nothing sent") }
            return
        }
        guard force || UsageStats.isDue(lastSent: state.statsSentAt, now: clock.now), let stats = currentStats() else { return }
        post(stats.json(), to: Sharing.statsURL(base: endpointBase)) { [weak self] ok in
            guard let self else { return }
            CraLog.note("sharing: usage stats \(ok ? "sent" : "not sent")")
            if ok {
                state.statsSentAt = clock.now
                file.save(state)
            }
        }
    }

    // MARK: - Crash reports

    private nonisolated static var reportsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Cra's crash reports written since the last look: sent, offered or passed over by the
    /// user's choice. The first look only marks where to start.
    func checkCrashReports() {
        guard mayReport, let store, !asking else { return }
        let choice = store.settings.crashReports
        let seen = state.crashesSeenUntil
        let now = clock.now
        let home = NSHomeDirectory()
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let urls = (try? fm.contentsOfDirectory(at: Self.reportsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let files = urls.map { CrashReports.File(name: $0.lastPathComponent,
                                                     modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            let pending = CrashReports.pending(files, seenUntil: seen, now: now)
            var reports: [(name: String, data: Data)] = []
            if choice != .never {
                for name in pending.send {
                    guard let text = try? String(contentsOf: Self.reportsFolder.appendingPathComponent(name), encoding: .utf8),
                          let data = CrashReports.reduce(ips: text, id: UUID(), home: home) else { continue }
                    reports.append((name, data))
                }
            }
            await MainActor.run { [reports] in
                self.state.crashesSeenUntil = pending.seenUntil
                self.file.save(self.state)
                guard !reports.isEmpty else { return }
                CraLog.note("sharing: \(reports.count) new crash reports, \(choice.rawValue)")
                switch choice {
                case .send: self.send(reports.map(\.data))
                case .ask: self.ask(reports)
                case .never: break
                }
            }
        }
    }

    private func send(_ reports: [Data]) {
        for data in reports {
            post(data, to: Sharing.crashURL(base: endpointBase)) { ok in CraLog.note("sharing: crash report \(ok ? "sent" : "not sent")") }
        }
    }

    /// macOS's "quit unexpectedly" question, with the report one click away and "always" as
    /// the checkbox.
    private func ask(_ reports: [(name: String, data: Data)]) {
        asking = true
        let quit = reports.contains { CrashReports.isAppQuit($0.name) }
        let dialog = AppDialog(
            title: quit ? "Cra quit unexpectedly" : "Part of Cra stopped unexpectedly",
            message: (reports.count == 1 ? "Send the crash report to help fix it?" : "Send the \(reports.count) crash reports to help fix it?")
                + " It shows what Cra was doing when it crashed. It never holds the sites you visit, and nothing that identifies you or this Mac.",
            actions: [DialogAction("Send"), DialogAction("Show Report", role: .secondary), DialogAction("Don’t Send", role: .cancel)],
            suppressionTitle: "Always send crash reports", icon: .application)
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue {
            case 0:
                if dialog.isSuppressed { store?.settings.crashReports = .send }
                send(reports.map(\.data))
                asking = false
            case 1:
                show(reports.map(\.data))
                ask(reports)
            default:
                asking = false
            }
        }
        if let parent = AppDialog.parentWindow {
            dialog.present(over: parent, completion: finish)
        } else {
            finish(dialog.runModal())
        }
    }

    /// The exact text that would be sent, opened in TextEdit.
    func show(_ reports: [Data], name: String = "Cra Crash Report") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Cra Sharing", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".txt")
        let text = reports.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n\n")
        guard (try? Data(text.utf8).write(to: file)) != nil else { return }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Settings ▸ Privacy ▸ "Show What’s Sent": the next usage report, exactly.
    func showStats() {
        guard let stats = currentStats() else { return }
        show([stats.json()], name: "Cra Usage Stats")
    }

    // MARK: - Network

    private func post(_ body: Data, to url: URL, done: @escaping @MainActor (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { _, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false)
            Task { @MainActor in done(ok) }
        }.resume()
    }
}
