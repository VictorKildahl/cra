import Foundation

/// Where Apple Intelligence's on-device model stands for Cra, as Settings ▸ Max explains it. Max
/// features run only on that model (FoundationModels), so every case but `available` keeps them off.
public enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    /// Off in System Settings ▸ Apple Intelligence & Siri.
    case off
    /// On, with the model still downloading.
    case preparing
    /// An Intel Mac: Apple Intelligence needs Apple silicon.
    case needsAppleSilicon
    /// The Intel copy of Cra running under Rosetta on an Apple silicon Mac.
    case needsAppleSiliconCopy
    /// An Apple silicon Mac whose Apple Intelligence doesn't give apps the model, as on macOS 27.3
    /// beta in mainland China (#538).
    case notOfferedToApps
    /// macOS 15 or earlier: no FoundationModels.
    case needsNewerMacOS
    case unavailable

    /// What FoundationModels said, without importing it.
    public enum Reason: Sendable {
        case appleIntelligenceNotEnabled, modelNotReady, deviceNotEligible, other
    }

    /// The Mac Cra runs on, and how.
    public enum Hardware: Sendable {
        case appleSilicon, rosetta, intel
    }

    /// `reason` is nil when the model is available.
    public init(reason: Reason?, hardware: Hardware) {
        switch reason {
        case nil: self = .available
        case .appleIntelligenceNotEnabled: self = .off
        case .modelNotReady: self = .preparing
        case .deviceNotEligible:
            switch hardware {
            case .intel: self = .needsAppleSilicon
            case .rosetta: self = .needsAppleSiliconCopy
            case .appleSilicon: self = .notOfferedToApps
            }
        case .other: self = .unavailable
        }
    }

    /// What Settings ▸ Max says under its features.
    public var explanation: String {
        switch self {
        case .available: return "Max features run on Apple Intelligence on this Mac, so the model sends nothing anywhere."
        case .off: return "Max features run on Apple Intelligence, which is off on this Mac."
        case .preparing: return "Apple Intelligence is still downloading. Max features turn on once it’s ready."
        case .needsAppleSilicon: return "Max features run on Apple Intelligence, which needs a Mac with Apple silicon."
        case .needsAppleSiliconCopy: return "Max features run on Apple Intelligence, which the Intel copy of Cra can’t use. Install Cra for Apple silicon from crabrowser.app."
        case .notOfferedToApps: return "Max features run on the Apple Intelligence model that apps use, which Apple doesn’t offer on this Mac yet. In some regions, Apple Intelligence doesn’t include it."
        case .needsNewerMacOS: return "Max features run on Apple Intelligence, which needs macOS 26 or later."
        case .unavailable: return "Apple Intelligence isn’t available right now."
        }
    }

    /// Whether System Settings can fix it.
    public var canOpenSettings: Bool { self == .off || self == .preparing || self == .unavailable }
}
