import CoreGraphics
import CraCore
import Testing

/// The sidebar dock's space icons, as Arc 1.171 draws them (#252: dots for spaces with no icon).
struct SpaceDockTests {
    /// A 300 pt sidebar leaves 217 pt between the Library and + buttons.
    static let room: CGFloat = 217

    /// Arc's widths with 4, 12, 16 and 22 spaces (31 Oct 2026): 34 pt each until the share drops
    /// under 22, then the open space keeps 22 and the rest split what is left in half points.
    @Test func cellWidthsMatchArc() {
        #expect(SpaceDock.widths(count: 4, open: 1, room: Self.room) == [34, 34, 34, 34])
        #expect(SpaceDock.widths(count: 12, open: 0, room: Self.room) == [22] + Array(repeating: 17.5, count: 11))
        #expect(Set(SpaceDock.widths(count: 16, open: 3, room: Self.room)) == [22, 13])
        #expect(Set(SpaceDock.widths(count: 22, open: 21, room: Self.room)) == [22, 9])
        #expect(SpaceDock.widths(count: 1, open: 0, room: 10) == [10], "one space is never squeezed")
        #expect(SpaceDock.widths(count: 0, open: nil, room: Self.room).isEmpty)
    }

    @Test func squeezedOnlyBelowTheOpenCellsWidth() {
        #expect(!SpaceDock.isSqueezed(count: 9, room: Self.room), "9 spaces get 24 pt each")
        #expect(SpaceDock.isSqueezed(count: 10, room: Self.room), "10 spaces would get 21.5 pt")
        #expect(!SpaceDock.isSqueezed(count: 1, room: 5))
    }

    /// A space with no icon is an 8 pt dot; emoji and symbols draw themselves (#252).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/252"))
    func aSpaceWithNoIconIsADot() {
        #expect(SpaceDock.mark(for: .none, isOpen: false, squeezed: false) == .dot(diameter: 8))
        #expect(SpaceDock.mark(for: .none, isOpen: true, squeezed: false) == .dot(diameter: 8))
        #expect(SpaceDock.mark(for: .emoji("🍕"), isOpen: false, squeezed: false) == .emoji("🍕"))
        #expect(SpaceDock.mark(for: .symbol("star.fill"), isOpen: false, squeezed: false) == .symbol("star.fill"))
    }

    /// In a squeezed dock every space but the open one is a 4 pt dot, whatever its icon; the open
    /// one shows its own icon, or the full-size dot (#252).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/252"))
    func aSqueezedDockIsDots() {
        for icon in [SpaceIcon.emoji("🧪"), .symbol("star.fill"), .none] {
            #expect(SpaceDock.mark(for: icon, isOpen: false, squeezed: true) == .dot(diameter: 4))
        }
        #expect(SpaceDock.mark(for: .emoji("🧪"), isOpen: true, squeezed: true) == .emoji("🧪"))
        #expect(SpaceDock.mark(for: .none, isOpen: true, squeezed: true) == .dot(diameter: 8))
    }

    /// Arc 1.171 (10 Nov 2026, 12 spaces): hovering a squeezed dot gives that space the wide cell
    /// and its icon, an icon-less space its 8 pt dot, lit; the open space becomes a plain 4 pt dot
    /// until the pointer leaves (#252, erkage).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/252"))
    func aHoveredSqueezedDotTakesTheWideCell() {
        let open = 0, mail = 2, plain = 4
        #expect(SpaceDock.wide(open: open, hovered: nil) == open)
        #expect(SpaceDock.wide(open: open, hovered: mail) == mail)
        #expect(SpaceDock.widths(count: 12, open: SpaceDock.wide(open: open, hovered: mail), room: Self.room)
                == [17.5, 17.5, 22] + Array(repeating: 17.5, count: 9))
        let wide = SpaceDock.wide(open: open, hovered: mail)
        #expect(SpaceDock.mark(for: .emoji("📮"), isOpen: mail == wide, squeezed: true) == .emoji("📮"))
        #expect(SpaceDock.mark(for: .emoji("🧑‍💻"), isOpen: open == wide, squeezed: true) == .dot(diameter: 4))
        #expect(SpaceDock.mark(for: .none, isOpen: plain == SpaceDock.wide(open: open, hovered: plain), squeezed: true)
                == .dot(diameter: 8))
        #expect(SpaceDock.isLit(isOpen: false, hovered: true, pressed: false, isWide: true, squeezed: true))
        #expect(!SpaceDock.isLit(isOpen: true, hovered: false, pressed: false, isWide: false, squeezed: true),
                "the open space's dot takes the others' ink while another is hovered")
        #expect(SpaceDock.isLit(isOpen: true, hovered: false, pressed: false, isWide: true, squeezed: true))
        #expect(SpaceDock.isLit(isOpen: true, hovered: false, pressed: false, isWide: false, squeezed: false),
                "a dock with room keeps the open space lit")
    }

    /// Arc's dot ink over the sidebar: 50 % for the open space, 25 % (light) or 18 % (dark) for
    /// the others (#252).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/252"))
    func dotInk() {
        #expect(SpaceDock.dotAlpha(dark: false, lit: true) == 0.5 && SpaceDock.dotAlpha(dark: true, lit: true) == 0.5)
        #expect(SpaceDock.dotAlpha(dark: false, lit: false) == 0.25)
        #expect(SpaceDock.dotAlpha(dark: true, lit: false) == 0.18)
    }
}
