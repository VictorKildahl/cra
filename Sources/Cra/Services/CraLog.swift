import Foundation

/// Cra's own log, `cra.log` next to Chromium's: what Cra did with each page (opened, shown,
/// loaded, closed) and what the page looked like a moment after it was shown, so a report of
/// a tab that "stays white" can be traced without a debugger. Lines name sites by host only,
/// never the full address: the log is meant to be sent (Help ▸ Export Diagnostics…).
enum CraLog {
    private static let queue = DispatchQueue(label: "dk.kildahl.cra.log", qos: .utility)
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var written = 0
    /// A runaway loop must not fill the disk; a session's log is a few hundred kB.
    private static let limit = 8 << 20

    static var file: URL { AppPaths.file("cra.log") }
    static var previousFile: URL { AppPaths.file("cra.previous.log") }
    static var chromiumPreviousFile: URL { AppPaths.file("chromium.previous.log") }

    /// Before Chromium starts. Only the Cra that owns the data folder rotates: a second launch
    /// that hands its URLs to the running one and quits would move that one's logs away.
    static func startSession(owner: Bool) {
        let fm = FileManager.default
        if owner {
            for (current, previous) in [(file, previousFile), (AppPaths.log, chromiumPreviousFile)] where fm.fileExists(atPath: current.path) {
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: current, to: previous)
            }
        }
        // Above 10: Chromium's DevTools pipe needs descriptors 3 and 4 free (CraCDPPipeSetUp),
        // and this file is opened before Chromium starts.
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        if fd >= 0 {
            let high = fcntl(fd, F_DUPFD_CLOEXEC, 10)
            close(fd)
            if high >= 0 { handle = FileHandle(fileDescriptor: high, closeOnDealloc: true) }
        }
        let info = Bundle.main.infoDictionary
        note("Cra \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) starts, pid \(getpid())\(owner ? "" : ", another Cra owns the data folder")")
    }

    /// Faults this session (the tests read it; persistence reports from its own queue).
    nonisolated(unsafe) private(set) static var faultCount = 0
    private static let faultLock = NSLock()

    /// Something Cra assumes never happens just did: a state the code cannot be in, a write
    /// that failed. Logged as "fault: …" rather than failing silently, so a report shows it
    /// and a scenario run (scripts/scenario.sh) fails on any. With CRA_FAULT_TRAP=1 a debug
    /// build stops there instead.
    static func fault(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        faultLock.lock()
        faultCount += 1
        faultLock.unlock()
        note("fault: \(message) (\(file):\(line))")
        #if DEBUG
        if ProcessInfo.processInfo.environment["CRA_FAULT_TRAP"] == "1" { raise(SIGTRAP) }
        #endif
    }

    static func note(_ message: String) {
        NSLog("Cra: %@", message)
        let line = "\(timestamp.string(from: Date())) \(message)\n"
        queue.async {
            guard let handle, written < limit, let data = line.data(using: .utf8) else { return }
            written += data.count
            try? handle.write(contentsOf: data)
        }
    }

    /// Waits for lines still being written (before the log is copied).
    static func flush() { queue.sync {} }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Only the host: logs get shared in bug reports.
    static func host(_ url: String) -> String {
        URL(string: url).flatMap { $0.host ?? $0.scheme.map { "\($0):" } } ?? "(no page)"
    }
}
