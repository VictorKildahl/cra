import Foundation

/// A page that accepts the connection and then takes long to answer looks blank apart from the
/// loading bar, and edge to edge or in fullscreen there is no bar at all (GitHub #256). After ten
/// seconds in the loading bar's waiting phase (the request is out, nothing committed), Cra says
/// so in its toast with Stop Loading; the request goes on unless that is pressed.
///
/// Not Arc: Arc 1.172.1 shows nothing more than the bar during a long wait (offline copy against
/// a local server that answers after 40 s, 8 Nov 2026: white page, "Untitled" tab, the address
/// reading about:blank, no status text, identical frames at 13, 20 and 30 s). The notice is Arc's
/// own toast (ShinyToast) with its button and ✕, like Cra's other notices.
///
/// One per tab. It goes as soon as the page answers (commits; a slow image after that never brings
/// it back), fails (Cra's error page commits too), is stopped, or its ✕ is pressed; ✕ holds for
/// that navigation only.
public struct SlowResponseNotice: Equatable, Sendable {
    /// How long a navigation waits for its first response before the notice shows.
    public static let delay: TimeInterval = 10

    /// When the current navigation started waiting; nil while the tab isn't waiting.
    public private(set) var waitingSince: Date?
    private var navigation = 0
    private var closed = false

    public init() {}

    /// The tab's loading phase as of `now`. `navigation` counts the main-frame navigations the
    /// page started (not redirects): another one while still waiting starts the clock again.
    public mutating func update(_ phase: LoadingIndicator.Phase, navigation: Int, now: Date) {
        guard phase == .waiting else {
            waitingSince = nil
            closed = false
            return
        }
        if waitingSince == nil || navigation != self.navigation {
            waitingSince = now
            closed = false
        }
        self.navigation = navigation
    }

    public func isShown(at now: Date) -> Bool {
        guard let waitingSince, !closed else { return false }
        return now.timeIntervalSince(waitingSince) >= Self.delay
    }

    /// When it shows if nothing changes before then; nil when it won't on its own.
    public var showsAt: Date? {
        closed ? nil : waitingSince?.addingTimeInterval(Self.delay)
    }

    /// The ✕: gone until the next navigation waits.
    public mutating func close() {
        if waitingSince != nil { closed = true }
    }

    /// The toast's text for the address being loaded: its host, without "www.".
    public static func message(for url: String) -> String {
        let host = URL(string: url)?.host.map(Boost.siteHost) ?? ""
        return "Still waiting for \(host.isEmpty ? "the page" : host) to respond"
    }
}
