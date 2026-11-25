import CraCore
import Testing

/// The sidebar's "+ New Tab" row: at rest, under the pointer, and while ⌘T's bar is open.
struct NewTabRowLookTests {
    /// Under the pointer it darkens like any hovered row and keeps its muted ink, as in Arc 1.174.1
    /// (sidebar 242/224/155 → 233/216/149, black ≈ 4 %; plus black 0.50). Cra painted it white with dark ink.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/788")) func hoveredIsAnOrdinaryHoveredRow() {
        let look = NewTabRowLook(hovered: true, barOpen: false)
        #expect(look.fill == .hover)
        #expect(look.ink == .secondary)
        #expect(!look.lifted)
    }

    /// While the ⌘T bar is open Arc draws it as the open row: the selected tab's fill, shadow and ink (#47),
    /// hovered or not.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/788")) func theOpenBarStillMakesItTheSelectedRow() {
        for hovered in [false, true] {
            let look = NewTabRowLook(hovered: hovered, barOpen: true)
            #expect(look.fill == .selected)
            #expect(look.ink == .primary)
            #expect(look.lifted)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/788")) func atRestItIsBare() {
        let look = NewTabRowLook(hovered: false, barOpen: false)
        #expect(look.fill == .none)
        #expect(look.ink == .secondary)
        #expect(!look.lifted)
    }
}
