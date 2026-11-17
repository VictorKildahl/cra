import Foundation

/// Pause All Media (GitHub #438; not in Arc): pauses what plays in every page Cra has loaded, in
/// every window, space and profile, Little Windows and Peeks included, in both engines. It pauses
/// and never plays: a paused player stays paused, and nothing resumes later. Sleeping tabs aren't
/// loaded to be paused, tabs aren't selected and windows don't come forward.
///
/// The command bar's Pause All Media takes every page; AppleScript's `pause media` can take some
/// windows, spaces or tabs, leave some out, keep to one profile and close Picture in Picture.
/// Afterwards Cra says what happened, and doesn't claim a page went quiet when it didn't: a page
/// still making sound a moment later (Web Audio, a player in a frame that never answered, a page
/// that plays again on pause) is reported as having kept playing.
public enum MediaPause {
    /// A page Cra holds: a tab's in a browser window, a Little Window's or a Peek's.
    public struct Page: Equatable, Sendable {
        /// The tab (a Little Window or Peek: its own id).
        public var id: UUID
        /// The browser window it shows in; a Peek's is the window under it, a Little Window has none.
        public var window: UUID?
        public var space: UUID?
        /// The profile its page loads in; nil is the Default profile.
        public var profile: UUID?
        /// A live page. A sleeping tab has none, and isn't woken to be paused.
        public var loaded: Bool

        public init(id: UUID, window: UUID?, space: UUID?, profile: UUID?, loaded: Bool) {
            (self.id, self.window, self.space, self.profile, self.loaded) = (id, window, space, profile, loaded)
        }
    }

    /// Which pages to pause. Windows, spaces and tabs name pages; a page is in `only` when any of
    /// them names it, and out when any of `except` does.
    public struct Scope: Equatable, Sendable {
        public struct Names: Equatable, Sendable {
            public var windows: Set<UUID>
            public var spaces: Set<UUID>
            public var tabs: Set<UUID>

            public init(windows: Set<UUID> = [], spaces: Set<UUID> = [], tabs: Set<UUID> = []) {
                (self.windows, self.spaces, self.tabs) = (windows, spaces, tabs)
            }

            public var isEmpty: Bool { windows.isEmpty && spaces.isEmpty && tabs.isEmpty }

            func names(_ page: Page) -> Bool {
                tabs.contains(page.id) || page.window.map(windows.contains) == true || page.space.map(spaces.contains) == true
            }
        }

        /// nil: every page.
        public var only: Names?
        public var except: Names
        /// Only pages of this profile (`.some(nil)` is the Default profile); nil: any profile.
        public var profile: UUID??

        public init(only: Names? = nil, except: Names = Names(), profile: UUID?? = nil) {
            (self.only, self.except, self.profile) = (only, except, profile)
        }

        public static let everything = Scope()

        public func includes(_ page: Page) -> Bool {
            if let only, !only.names(page) { return false }
            if except.names(page) { return false }
            if let profile, page.profile != profile { return false }
            return true
        }
    }

    /// The pages to ask, in the order given: loaded, in scope.
    public static func targets(_ pages: [Page], in scope: Scope) -> [Page] {
        pages.filter { isTarget($0, in: scope) }
    }

    public static func isTarget(_ page: Page, in scope: Scope) -> Bool { page.loaded && scope.includes(page) }

    /// What Chromium's engine did in one page (Cra.pauseMedia's answer).
    public struct EngineAnswer: Equatable, Sendable {
        /// The page's media session was playing; the engine paused it.
        public var session: Bool
        /// Media elements the page's frames paused.
        public var paused: Int
        /// Media elements that played on right after pause().
        public var resisted: Int

        public init(session: Bool = false, paused: Int = 0, resisted: Int = 0) {
            (self.session, self.paused, self.resisted) = (session, paused, resisted)
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// Nothing played in the page.
        case quiet
        case paused
        /// Still playing after the pause, as far as Cra can tell.
        case keptPlaying
    }

    /// How long after the pause a page is checked for sound: past the page's own pause handler
    /// (Cra.pauseMedia gives it 0.3 s) and the frames' answers, short of the speaker's 2 s hold.
    public static let checkDelay: TimeInterval = 1

    /// One page's outcome.
    /// - Parameters:
    ///   - answer: what the engine paused (nil: a WebKit page, an engine without Cra.pauseMedia, or
    ///     no answer).
    ///   - playingBefore: the page made sound, or (WebKit) played media, as the pause started.
    ///   - playingAfter: it still did `checkDelay` later.
    public static func outcome(answer: EngineAnswer?, playingBefore: Bool, playingAfter: Bool) -> Outcome {
        let played = playingBefore || answer.map { $0.session || $0.paused > 0 || $0.resisted > 0 } == true
        guard played else { return .quiet }
        return playingAfter || (answer?.resisted ?? 0) > 0 ? .keptPlaying : .paused
    }

    /// What Pause All Media did, page by page.
    public struct Report<ID: Hashable & Sendable>: Equatable, Sendable {
        public var paused: [ID] = []
        public var keptPlaying: [ID] = []

        public init(paused: [ID] = [], keptPlaying: [ID] = []) {
            (self.paused, self.keptPlaying) = (paused, keptPlaying)
        }

        public mutating func add(_ id: ID, _ outcome: Outcome) {
            switch outcome {
            case .quiet: break
            case .paused: paused.append(id)
            case .keptPlaying: keptPlaying.append(id)
            }
        }

        /// Cra's toast after the command bar's Pause All Media. When a page kept playing, the
        /// toast's Show button goes to it.
        public var toast: String {
            func tabs(_ n: Int) -> String { n == 1 ? "1 Tab" : "\(n) Tabs" }
            switch (paused.count, keptPlaying.count) {
            case (0, 0): return "Nothing Is Playing"
            case (let p, 0): return "Paused \(tabs(p))"
            case (0, let k): return "\(tabs(k)) Kept Playing"
            case (let p, let k): return "Paused \(tabs(p)), \(k) Kept Playing"
            }
        }
    }
}
