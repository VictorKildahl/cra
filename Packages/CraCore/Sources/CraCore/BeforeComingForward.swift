import Foundation

/// What was in use as Cra came forward, before AppKit raised a browser window and made one key.
///
/// A link clicked in another app brings Cra forward (LaunchServices) at about the moment it arrives,
/// and AppKit picks a key window on the way, at times not the one in use: a full-screen browser
/// window on another display. For that link, the window order (#607) and the browser window in use
/// are the ones held here, so the link opens in that window's space and profile.
public struct BeforeComingForward: Equatable {
    public let at: Date
    /// The windows on screen, front to back.
    public let stack: [StackedWindow]
    /// The normal browser window used last.
    public let window: UUID

    public init(at: Date, stack: [StackedWindow], window: UUID) {
        self.at = at
        self.stack = stack
        self.window = window
    }

    /// This, when Cra came forward for a link arriving `now`: it is in front and came forward
    /// within `FrontmostAppHistory.linkGrace`. Nil when the user brought Cra forward themselves.
    public func forLink(at now: Date, craActive: Bool) -> BeforeComingForward? {
        craActive && now.timeIntervalSince(at) <= FrontmostAppHistory.linkGrace ? self : nil
    }
}
