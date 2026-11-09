import Foundation

/// A row in the downloads list. Arc 1.171 shows downloads that are still running, failed or were
/// cancelled there, with the finished ones, and has no download toast (its strings: "Failed to
/// Download", a download speed "e.g. 3 MB/s", subtitles for paused and cancelled downloads).
/// Cra's bottom-right download cards were the only other toast design and are gone (#85 follow-up).
public enum DownloadRow {
    public enum State: Equatable {
        case downloading(received: Int64, total: Int64, bytesPerSecond: Double?)
        case paused
        case failed
        case cancelled
        case finished(at: Date)
    }

    /// The line under the file name: progress and speed while it runs, Arc's failure text, or
    /// how long ago it finished ("54 seconds ago").
    public static func subtitle(_ state: State, now: Date) -> String {
        switch state {
        case let .downloading(received, total, speed):
            var s = bytes(received)
            if total > 0 { s += " of " + bytes(total) }
            if let speed, speed > 0 { s += " — " + bytes(Int64(speed)) + "/s" }
            return s
        // Arc 1.172's "Subtitle copy for a paused download".
        case .paused: return "Paused"
        case .failed: return "Failed to Download"
        case .cancelled: return "Cancelled"
        // At least a second: a row read just as it finished said "in 0 seconds".
        case let .finished(at): return age.localizedString(fromTimeInterval: -max(1, now.timeIntervalSince(at)))
        }
    }

    /// Bytes per second from two progress reports; nil until there is a span to measure.
    public static func speed(fromBytes a: Int64, at t0: Date, toBytes b: Int64, at t1: Date) -> Double? {
        let dt = t1.timeIntervalSince(t0)
        guard dt >= 0.25, b >= a else { return nil }
        return Double(b - a) / dt
    }

    /// Finder's sizes (1000-based: "980 bytes", "12 KB", "3 MB", "1.5 GB"), always in English like the
    /// rest of Cra; ByteCountFormatter follows the system's locale.
    public static func bytes(_ n: Int64) -> String {
        if n < 1000 { return "\(n) bytes" }
        let units = ["KB", "MB", "GB", "TB"]
        var v = Double(n) / 1000, i = 0
        while v >= 999.95, i < units.count - 1 { v /= 1000; i += 1 }
        if i == 0 { return "\(Int(v.rounded())) KB" }
        let r = (v * 10).rounded() / 10
        return (r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), r)) + " " + units[i]
    }

    private static let age: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .full
        return f
    }()
}
