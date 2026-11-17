import CoreGraphics
import CraCore
import Foundation
import Testing

/// A Peek on a call asks before it closes: its Close button turns into Arc's red Confirm pill (GitHub #425).
struct PeekCloseConfirmTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/425"))
    func aPeekOnACallHoldsItsFirstClose() {
        for attempt in [PeekCloseAttempt.closeButton, .closeShortcut, .background, .swipe] {
            #expect(PeekCloseHold.after(attempt, holding: nil, capturingMedia: true) == .mediaInput)
            #expect(PeekCloseHold.after(attempt, holding: nil, capturingMedia: false) == nil)
        }
        // Esc closes at once unless it asks to be confirmed; Cra's Esc doesn't (Arc's rule for when it does is unread).
        #expect(PeekCloseHold.after(.escape(prefersConfirmation: false), holding: nil, capturingMedia: true) == nil)
        #expect(PeekCloseHold.after(.escape(prefersConfirmation: true), holding: nil, capturingMedia: false) == .escape)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/425"))
    func aSecondCloseGoesThrough() {
        for attempt in [PeekCloseAttempt.closeButton, .closeShortcut, .escape(prefersConfirmation: false), .escape(prefersConfirmation: true)] {
            #expect(PeekCloseHold.after(attempt, holding: .mediaInput, capturingMedia: true) == nil)
            #expect(PeekCloseHold.after(attempt, holding: .escape, capturingMedia: true) == nil)
        }
        // A click outside or a swipe keeps a call's pill up, and ends an Esc's.
        for attempt in [PeekCloseAttempt.background, .swipe] {
            #expect(PeekCloseHold.after(attempt, holding: .mediaInput, capturingMedia: true) == .mediaInput)
            #expect(PeekCloseHold.after(attempt, holding: .escape, capturingMedia: false) == nil)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/425"))
    func thePillIsArcs() {
        #expect(PeekCloseHold.mediaInput.timeout == 10)
        #expect(PeekCloseHold.escape.timeout == 1)
        #expect(PeekCloseHold.mediaInput.symbol == "phone.down.fill")
        #expect(PeekCloseHold.escape.symbol == "xmark")
        #expect(PeekCloseHold.mediaInput.help == "Hang up")
        #expect(PeekCloseHold.escape.help == "Close")
        #expect(PeekCloseHold.text == "Confirm")
        // Arc's DestructiveButtonFace, sRGB 245/55/20, with white ink.
        #expect(PeekCloseHold.fill == RGB(0.961, 0.216, 0.078))
        #expect(PeekCloseHold.ink == .white)
        #expect(PeekCloseHold.spring == PeekControlLook.Spring(response: 0.25, dampingFraction: 0.8))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/425"))
    func thePillGrowsRightFromTheButton() {
        let button = PeekLayout.buttonSize
        // 8 pt of padding, the glyph, 4 pt, the text, 8 pt.
        let width: CGFloat = PeekCloseHold.pillWidth(textWidth: 52, button: button)
        #expect(width == 90)
        // The glyph keeps its place: the text starts 4 pt past where the round button ends its glyph.
        let textX: CGFloat = PeekCloseHold.textMinX(button: button)
        #expect(textX == 30)
    }
}
