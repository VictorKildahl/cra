import CoreGraphics
import CraCore
import Testing

struct TabRowTrailingTests {
    // A 228.5 pt row (Arc's fill at a ≈236 pt sidebar, #243) whose name starts 46 pt in.
    static let width: CGFloat = 228.5
    static let textX: CGFloat = 46
    static let close = TabRowTrailing.Control(width: 24)

    /// On hover, the name runs to 15 pt before the close button (13 pt from the label's widened box),
    /// as in Arc; it stopped 26 pt short, about two characters before Arc's (#243). The button stays
    /// 6 pt from the row's end.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/243"))
    func hoveredNameRunsToTheCloseButton() {
        let l = TabRowTrailing.layout(rowWidth: Self.width, textX: Self.textX, controls: [Self.close])
        #expect(l.controlX == [Self.width - 6 - 24])
        #expect(Self.textX + l.textWidth == l.controlX[0] - 15)
    }

    /// At rest, with nothing at the row's end, the name keeps its 21 pt tail (#243: Arc's rows match
    /// there).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/243"))
    func restingTailIsUnchanged() {
        let l = TabRowTrailing.layout(rowWidth: Self.width, textX: Self.textX, controls: [])
        #expect(Self.textX + l.textWidth == Self.width - 21)
    }

    /// The unread dot and a peek badge sit centred where the close button shows, and the name stops
    /// the same 15 pt before them.
    @Test func dotSitsInTheCloseButtonsSlot() {
        let dot = TabRowTrailing.Control(width: 6, slot: 24)
        let l = TabRowTrailing.layout(rowWidth: Self.width, textX: Self.textX, controls: [dot])
        #expect(l.controlX[0] + 3 == Self.width - 6 - 12)
        #expect(Self.textX + l.textWidth == l.controlX[0] - TabRowTrailing.nameGap)
    }

    /// Several controls stay at least 11 pt apart (more where one sits centred in a wider slot), the
    /// last in its place, the name 15 pt before the first:
    /// on hover the capture dot and the close button, at rest the capture dot, a peek badge and the
    /// unread dot (the badge and the dot give way to the button on hover).
    @Test(arguments: [
        [TabRowTrailing.Control(width: 8), TabRowTrailingTests.close],
        [TabRowTrailing.Control(width: 8), TabRowTrailing.Control(width: 16, slot: 24), TabRowTrailing.Control(width: 6, slot: 24)],
    ])
    func controlsDoNotOverlap(_ controls: [TabRowTrailing.Control]) {
        let l = TabRowTrailing.layout(rowWidth: Self.width, textX: Self.textX, controls: controls)
        let last = controls[controls.count - 1]
        #expect(l.controlX.last! + last.width / 2 == Self.width - 6 - last.slot / 2)
        for i in 1..<controls.count {
            #expect(l.controlX[i] - (l.controlX[i - 1] + controls[i - 1].width) >= 11)
        }
        #expect(Self.textX + l.textWidth == l.controlX[0] - 15)
    }

    /// A row too narrow for its name gives it no width rather than a negative one.
    @Test func narrowRowGivesNoWidth() {
        let l = TabRowTrailing.layout(rowWidth: 60, textX: Self.textX, controls: [Self.close])
        #expect(l.textWidth == 0)
    }
}
