import Foundation

/// What the Spaces sheet shows the moment it opens (#556). The sheet reads the Mac's sidebar every
/// time it opens, since the Mac may have changed it, and that read takes a moment (finding the
/// iCloud container, a coordinated read). Until it is back the sheet shows what the last read
/// found, so a reopened sheet has its Spaces at once. "Connecting" is only for an opening with
/// nothing read yet in this run of the app.
public struct MobileSpacesSheet: Equatable {
    /// What a read of the synced folder found.
    public enum Read: Equatable {
        case spaces(SidebarDocument)
        /// iCloud is there but the Mac has not synced anything into it yet.
        case nothingSynced
        /// No iCloud on this phone, or this build may not use it.
        case unavailable
    }

    public private(set) var lastRead: Read?

    public init() {}

    /// What the sheet opens on: the last read, or nil for "Connecting".
    public var opening: Read? { lastRead }

    /// The sheet's own read, which asks iCloud for the Mac's file when it isn't on the phone,
    /// replaces what is remembered whatever it found: Sync turned off on the Mac shows as such the
    /// next time. A quick look that doesn't ask iCloud (the tab row's check for its sync card) only
    /// adds Spaces: not finding a file iCloud hasn't brought down yet says nothing about the Mac.
    public mutating func remember(_ read: Read, askedICloud: Bool) {
        if askedICloud { return lastRead = read }
        if case .spaces = read { lastRead = read }
    }
}
