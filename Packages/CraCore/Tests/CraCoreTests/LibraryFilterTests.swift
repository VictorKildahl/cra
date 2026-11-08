import CraCore
import Foundation
import Testing

/// Arc's Filter chips on Archived Tabs and Downloads.
struct LibraryFilterTests {
    static let space = UUID(), other = UUID()

    static func entry(_ reason: ArchiveReason, space: UUID?, little: Bool = false) -> ArchivedItem {
        ArchivedItem(archivedAt: Date(), reason: reason, sourceSpaceID: space, wasPinned: false,
                     item: SidebarItem(id: UUID(), parentID: nil, title: nil, children: [], isUnread: false, createdAt: Date(), data: .tab(TabData(url: "https://example.com"))), fromLittleWindow: little)
    }

    @Test func nothingPickedShowsAll() {
        #expect(ArchiveFilter().shows(Self.entry(.auto, space: Self.space)))
    }

    @Test func howItClosed() {
        var f = ArchiveFilter()
        f.closed = [.auto]
        #expect(f.shows(Self.entry(.auto, space: nil)))
        #expect(!f.shows(Self.entry(.manual, space: nil)))
        #expect(!f.shows(Self.entry(.clear, space: nil)), "a Clear is by hand")
        f.closed = [.auto, .manual]
        #expect(f.shows(Self.entry(.clear, space: nil)))
    }

    @Test func whereItWasNarrowsHowItClosed() {
        var f = ArchiveFilter()
        f.places = [.space(Self.space), .littleWindow]
        #expect(f.shows(Self.entry(.manual, space: Self.space)))
        #expect(f.shows(Self.entry(.manual, space: nil, little: true)))
        #expect(!f.shows(Self.entry(.manual, space: Self.other)))
        f.closed = [.auto]
        #expect(!f.shows(Self.entry(.manual, space: Self.space)))
    }

    @Test func downloadsByProfile() {
        var f = DownloadFilter()
        #expect(f.shows(profile: "Profile 2"))
        f.profiles = [""]
        #expect(f.shows(profile: nil))
        #expect(!f.shows(profile: "Profile 2"))
    }
}
