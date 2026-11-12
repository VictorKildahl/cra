import Foundation

/// The first launch of a new Cra waits 2–3 s before any of its code runs: macOS checks a bundle
/// it hasn't run before (Gatekeeper's evaluation in syspolicyd), and every update is such a bundle.
/// Running the staged update once, hidden, with `CRA_PREWARM=1` (main.swift exits on its first
/// line) pays that check while nobody waits, and the next real launch of those files skips it.
/// The check's result can be dropped again on a busy Mac, so the copy runs again while the update
/// waits to be installed.
public enum UpdatePrewarm {
    /// The environment variable that makes Cra exit at the top of main.swift.
    public static let environmentKey = "CRA_PREWARM"
    /// How often a waiting update runs again. A warm copy exits in ~50 ms.
    public static let interval: TimeInterval = 20 * 60
    /// A run that hasn't exited by then is stopped (a cold check takes a few seconds).
    public static let timeout: TimeInterval = 60

    /// A copy of Cra Sparkle extracted: where it is, its version and when it was written.
    public struct Candidate: Equatable, Sendable {
        public var path: String
        public var version: String?
        public var bundleID: String?
        public var modified: Date
        public init(path: String, version: String?, bundleID: String?, modified: Date) {
            self.path = path
            self.version = version
            self.bundleID = bundleID
            self.modified = modified
        }
    }

    /// The staged copy of `version` with this bundle id, the newest when Sparkle left several.
    /// Sparkle names the update by its CFBundleVersion (`versionString`); the short version is
    /// accepted too, since Cra's releases use the same string for both.
    public static func pick(_ candidates: [Candidate], version: String, bundleID: String) -> Candidate? {
        candidates
            .filter { $0.bundleID == bundleID && $0.version == version }
            .max { $0.modified < $1.modified }
    }

    /// Whether a waiting update should run again now.
    public static func isDue(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval
    }
}
