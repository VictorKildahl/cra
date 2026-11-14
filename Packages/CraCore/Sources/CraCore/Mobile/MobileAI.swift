import Foundation

/// Where Apple Intelligence's on-device model stands on this phone, for Browse for Me and
/// Summarize (Victor, 13 Nov: show them on every iPhone that can run Apple Intelligence; when
/// it is switched off, ask to switch it on; phones that can't run it don't get them).
public enum MobileAIState: Equatable {
    /// The model answers.
    case ready
    /// The phone can run Apple Intelligence but it is switched off in Settings.
    case turnedOff
    /// Switched on, still downloading or getting ready.
    case preparing
    /// Not a phone that runs Apple Intelligence (or an iOS without the on-device model).
    case unsupported

    /// The buttons show: everywhere but on a phone that can never run them.
    public var offersFeatures: Bool { self != .unsupported }
    public var canRun: Bool { self == .ready }
}

public enum MobileAI {
    public struct Prompt: Equatable {
        public var title: String
        public var message: String
        /// "Open Settings" beside "Not Now"; otherwise one "OK".
        public var opensSettings: Bool
    }

    /// What a tap on Browse for Me or Summarize says when the model can't answer yet; nil when
    /// it can (or when the button isn't there at all).
    public static func prompt(for state: MobileAIState) -> Prompt? {
        switch state {
        case .ready, .unsupported:
            return nil
        case .turnedOff:
            return Prompt(title: "Turn on Apple Intelligence",
                          message: "Browse for Me and Summarize run on this iPhone with Apple Intelligence, so nothing you read leaves it. Turn it on in Settings \u{25B8} Apple Intelligence & Siri, then come back.",
                          opensSettings: true)
        case .preparing:
            return Prompt(title: "Apple Intelligence is getting ready",
                          message: "Apple Intelligence is still downloading to this iPhone. Browse for Me and Summarize work as soon as it\u{2019}s done.",
                          opensSettings: false)
        }
    }
}
