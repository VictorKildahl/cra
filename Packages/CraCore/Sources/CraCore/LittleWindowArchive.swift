import Foundation

/// Arc's Settings ▸ Links ▸ "Archive Little Arcs after:" (Arc 1.172.1): a Little Arc left alone
/// that long is closed, its page kept in the archive. Arc offers 1 hour, 6 hours (its default)
/// and 12 hours.
public enum LittleWindowArchive: String, Codable, CaseIterable, Sendable {
    case oneHour, sixHours, twelveHours

    public var seconds: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .sixHours: 6 * 3600
        case .twelveHours: 12 * 3600
        }
    }

    public var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours (default)"
        case .twelveHours: "12 hours"
        }
    }

    /// Whether a Little Window last in use at `lastUsed` is archived now. The key one is in use.
    public func expired(lastUsed: Date, now: Date, isKey: Bool) -> Bool {
        !isKey && now.timeIntervalSince(lastUsed) >= seconds
    }
}
