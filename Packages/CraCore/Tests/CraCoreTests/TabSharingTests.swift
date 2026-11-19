import CoreGraphics
import CraCore
import Testing

/// Arc's marks for a tab a call shares (X DM 19 Nov 2026, Arc 1.173 recording with Google Meet).
struct TabSharingTests {
    /// The shared page is ringed in yellow even when it fills the window alone, where no focus ring shows.
    @Test func sharedPageIsRingedAlone() {
        #expect(TabSharing.paneRing(panes: 1, focused: true, shared: true, fullscreen: false) == .shared)
        #expect(TabSharing.paneRing(panes: 1, focused: true, shared: false, fullscreen: false) == .none)
    }

    /// In a split, the shared pane is yellow whether or not it has focus; the focus ring stays on the
    /// focused pane when that's another one.
    @Test func sharedRingBeatsFocusRing() {
        #expect(TabSharing.paneRing(panes: 2, focused: true, shared: true, fullscreen: false) == .shared)
        #expect(TabSharing.paneRing(panes: 2, focused: false, shared: true, fullscreen: false) == .shared)
        #expect(TabSharing.paneRing(panes: 2, focused: true, shared: false, fullscreen: false) == .focus)
        #expect(TabSharing.paneRing(panes: 2, focused: false, shared: false, fullscreen: false) == .none)
    }

    /// A page in full screen has no card to ring.
    @Test func noRingInFullScreen() {
        #expect(TabSharing.paneRing(panes: 1, focused: true, shared: true, fullscreen: true) == .none)
        #expect(TabSharing.paneRing(panes: 2, focused: true, shared: false, fullscreen: true) == .none)
    }

    /// The button shows on a hovered tab the call can switch to, and never on the shared tab, on a tab
    /// being renamed, at rest, or without a call.
    @Test func shareInsteadShowsOnlyOnHoveredOtherTabs() {
        #expect(TabSharing.showsShareInstead(hovered: true, editing: false, canShareInstead: true, shared: false))
        #expect(!TabSharing.showsShareInstead(hovered: false, editing: false, canShareInstead: true, shared: false))
        #expect(!TabSharing.showsShareInstead(hovered: true, editing: true, canShareInstead: true, shared: false))
        #expect(!TabSharing.showsShareInstead(hovered: true, editing: false, canShareInstead: false, shared: false))
        #expect(!TabSharing.showsShareInstead(hovered: true, editing: false, canShareInstead: true, shared: true))
    }

    /// Arc's button is a 24 pt square right against the 24 pt close button (their centres 24 pt
    /// apart), the close button in its usual place 6 pt from the row's end, the name 15 pt before.
    @Test func shareInsteadSitsAgainstTheCloseButton() {
        let width: CGFloat = 228.5, textX: CGFloat = 46
        let share = TabRowTrailing.Control(width: 24, gapAfter: 0)
        let close = TabRowTrailing.Control(width: 24)
        let l = TabRowTrailing.layout(rowWidth: width, textX: textX, controls: [share, close])
        #expect(l.controlX[1] == width - 6 - 24)
        #expect(l.controlX[1] - l.controlX[0] == 24)
        #expect(textX + l.textWidth == l.controlX[0] - TabRowTrailing.nameGap)
    }

    /// The capture dot before the pair keeps its 11 pt gap.
    @Test func captureDotKeepsItsGapBeforeThePair() {
        let dot = TabRowTrailing.Control(width: 16)
        let share = TabRowTrailing.Control(width: 24, gapAfter: 0)
        let close = TabRowTrailing.Control(width: 24)
        let l = TabRowTrailing.layout(rowWidth: 228.5, textX: 46, controls: [dot, share, close])
        #expect(l.controlX[1] - (l.controlX[0] + 16) == 11)
    }
}
