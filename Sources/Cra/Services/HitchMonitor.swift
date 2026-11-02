import Foundation
import QuartzCore

/// Testing aids. With CRA_HITCH_LOG=<path> set, every main-thread stall of 8 ms or
/// more is appended to that file, with the actions that ran through CRA_COMMAND_FILE
/// as markers between them. The main thread is also Chromium's browser UI thread,
/// so a stall here delays input, scrolling and page-window moves as well as Cra's UI.
enum HitchMonitor {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handle: FileHandle?

    /// CRA_TEST_BACKGROUND=1: a test instance measured behind other apps. Scripted commands
    /// don't bring it to the front, and App Nap doesn't slow it down.
    static let background = ProcessInfo.processInfo.environment["CRA_TEST_BACKGROUND"] == "1"
    nonisolated(unsafe) private static var activity: NSObjectProtocol?

    static func startIfRequested() {
        if background {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                                                             reason: "Background test instance")
        }
        guard let path = ProcessInfo.processInfo.environment["CRA_HITCH_LOG"], !path.isEmpty else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        let thread = Thread {
            let done = DispatchSemaphore(value: 0)
            while true {
                let start = CACurrentMediaTime()
                DispatchQueue.main.async { done.signal() }
                done.wait()
                let ms = (CACurrentMediaTime() - start) * 1000
                if ms >= 8 { write(String(format: "stall %.1f", ms)) }
                // Each ping wakes the run loop (and Chromium's observers on it): not too often.
                usleep(4000)
            }
        }
        thread.name = "HitchMonitor"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Also a breadcrumb for the performance recorder: what Cra did before a stall.
    static func mark(_ label: String) {
        Perf.mark(label)
        write("mark \(label)")
    }

    private static func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        handle.write(String(format: "%.3f %@\n", CACurrentMediaTime(), line).data(using: .utf8)!)
    }
}
