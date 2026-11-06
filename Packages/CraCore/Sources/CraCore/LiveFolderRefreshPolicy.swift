import Foundation

public enum LiveFolderRefreshPolicy {
    public enum Trigger { case automatic, manual, configuration }
    public static let minimumInterval: TimeInterval = 10

    public static func shouldStart(lastFetch: Date?, lastError: LiveFolderError?, now: Date, trigger: Trigger) -> Bool {
        if trigger != .automatic || lastError != nil { return true }
        return lastFetch.map { now.timeIntervalSince($0) >= minimumInterval } ?? true
    }

    public static func feedbackDelay(startedAt: Date?, now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, 0.45 - now.timeIntervalSince(startedAt))
    }
}
