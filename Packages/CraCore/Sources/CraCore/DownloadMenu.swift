import Foundation

/// The context menu of a download row, the same in the tray over the Library button and on
/// Library ▸ Downloads (#272). Arc 1.172's "Download Context Menu" (ContextMenus, read from its
/// binary on 9 Nov 2026): Open %@, Copy %@, Show in Finder, a separator, Cancel Download, a
/// separator, Hide from Arc, Move to Trash. %@ is the file's kind (`Kind`), or else its extension
/// as it is ("Open txt"). Pause Download and Resume Download are Cra's: Arc has a paused row
/// ("Paused") but no item that pauses one.
public enum DownloadMenu {
    public enum Action: Equatable, Sendable {
        case open, copy, showInFinder, pause, resume, cancel, hide, moveToTrash
    }

    /// The kinds Arc names a file by (ARCFoundationBase's URL+DownloadDestination), tested in
    /// this order: a zip is an archive too, and Arc says "Zip Archive".
    public enum Kind: CaseIterable, Equatable, Sendable {
        case image, diskImage, pdf, movie, audio, zip, archive

        public var name: String {
            switch self {
            case .image: "Image"
            case .diskImage: "Disk Image"
            case .pdf: "PDF"
            case .movie: "Movie"
            case .audio: "Audio"
            case .zip: "Zip Archive"
            case .archive: "Archive"
            }
        }

        /// The first kind the file's type conforms to (the app asks UTType).
        public static func first(where conforms: (Kind) -> Bool) -> Kind? { allCases.first(where: conforms) }
    }

    /// The menu's groups, a separator between two. A finished file can be opened, copied, shown,
    /// hidden from the list or trashed; a running or paused one shown (once its file exists),
    /// paused or resumed and cancelled; a failed or cancelled one only hidden.
    public static func sections(for row: DownloadList.Listed, fileExists: (String) -> Bool) -> [[Action]] {
        switch row {
        case .finished(let e):
            guard fileExists(e.path) else { return [[.hide]] }
            return [[.open, .copy, .showInFinder], [.hide, .moveToTrash]]
        case .live(let l):
            guard l.running else { return [[.hide]] }
            let show: [[Action]] = !l.path.isEmpty && fileExists(l.path) ? [[.showInFinder]] : []
            return show + [[l.paused ? .resume : .pause, .cancel]]
        }
    }

    public static func title(_ action: Action, kind: Kind?, fileName: String) -> String {
        let noun = kind?.name ?? { let ext = (fileName as NSString).pathExtension; return ext.isEmpty ? "File" : ext }()
        switch action {
        case .open: return "Open \(noun)"
        case .copy: return "Copy \(noun)"
        case .showInFinder: return "Show in Finder"
        case .pause: return "Pause Download"
        case .resume: return "Resume Download"
        case .cancel: return "Cancel Download"
        case .hide: return "Hide from Cra"
        case .moveToTrash: return "Move to Trash"
        }
    }
}

/// Asked before Cra quits. Arc 1.172 asks "Downloads in progress" while one runs ("There are
/// downloads in progress. Closing the application will cancel them.", Keep browsing / Close Arc),
/// in place of its usual "Quit Arc?" (#272). A restart into an update or another page engine asks
/// neither: the update's own Install and Relaunch asks about downloads before it starts.
public enum QuitPrompt: Equatable, Sendable {
    case none
    /// Settings ▸ Advanced ▸ Warn before quitting.
    case confirmQuit
    case downloadsInProgress

    public static func on(source: MenuBarMode.QuitSource, downloadsRunning: Bool, warnBeforeQuitting: Bool) -> QuitPrompt {
        guard source != .relaunch else { return .none }
        if downloadsRunning { return .downloadsInProgress }
        return warnBeforeQuitting ? .confirmQuit : .none
    }
}

/// One quit at a time (#426). Once a quit is asked about, more requests are part of it. macOS
/// can send quit events while "Quit Cra?" is open (a restart). Chromium's own exit sends a
/// terminate once Cra starts closing its pages. Neither asks again. A quit that doesn't happen
/// (Cancel, Cra staying in the menu bar, a page's "Leave site?" ▸ Stay) lets the next one ask.
public struct QuitRequests: Equatable, Sendable {
    private enum Phase: Equatable, Sendable { case idle, asking, quitting }
    private var phase = Phase.idle

    public init() {}

    public enum Request: Equatable, Sendable {
        /// A new quit: ask, then quit or stay.
        case new
        /// "Quit Cra?" (or "Downloads in progress") is open and answers this one too.
        case asking
        /// Already quitting: go on without asking or saving again.
        case quitting
    }

    /// A terminate request, and what it is part of.
    public mutating func begin() -> Request {
        switch phase {
        case .asking: return .asking
        case .quitting: return .quitting
        case .idle:
            phase = .asking
            return .new
        }
    }

    /// How the question (or no question) came out: quitting, or staying.
    public mutating func answered(quit: Bool) { phase = quit ? .quitting : .idle }

    /// Chromium stopped the quit under way (a page's "Leave site?" ▸ Stay).
    public mutating func cancelled() { phase = .idle }
}
