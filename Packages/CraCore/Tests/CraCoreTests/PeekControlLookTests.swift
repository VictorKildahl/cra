import CraCore
import Foundation
import Testing

/// The Peek buttons' hover and press, and the shortcuts that press them (GitHub #385).
struct PeekControlLookTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/385"))
    func hoverLiftsTheButtonAndDeepensItsShadow() {
        let rest = PeekControlLook.of(hovered: false, pressed: false)
        let hover = PeekControlLook.of(hovered: true, pressed: false)
        #expect(rest == PeekControlLook(lift: 0, scale: 1, shadowOpacity: 0.2, shadowRadius: 4))
        #expect(hover == PeekControlLook(lift: 1, scale: 1, shadowOpacity: 0.3, shadowRadius: 6))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/385"))
    func aPressShrinksTheButtonAndTightensItsShadow() {
        #expect(PeekControlLook.of(hovered: true, pressed: true) == PeekControlLook(lift: 1, scale: 0.95, shadowOpacity: 0.3, shadowRadius: 4))
        // A shortcut presses a button the pointer isn't over.
        #expect(PeekControlLook.of(hovered: false, pressed: true) == PeekControlLook(lift: 0, scale: 0.95, shadowOpacity: 0.2, shadowRadius: 4))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/385"))
    func springsAreArcsInCoreAnimationTerms() {
        let hover = PeekControlLook.hoverSpring, press = PeekControlLook.pressSpring
        #expect(hover == .init(response: 0.15, dampingFraction: 0.95))
        #expect(press == .init(response: 0.28, dampingFraction: 0.63))
        // stiffness (2π / response)², damping 4π · fraction / response, mass 1.
        #expect(abs(hover.stiffness - 1754.6) < 0.1)
        #expect(abs(hover.damping - 79.587) < 0.01)
        #expect(abs(press.stiffness - 503.55) < 0.01)
        #expect(abs(press.damping - 28.274) < 0.01)
        // A press is bouncy (under 1 is underdamped), the hover all but settles straight.
        #expect(press.dampingFraction < hover.dampingFraction)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/385"))
    func shortcutsPressTheirButtons() {
        #expect(PeekControl.pressed(byAction: "closeWindow") == .close)
        #expect(PeekControl.pressed(byAction: "closeTab") == .close)
        #expect(PeekControl.pressed(byAction: "promoteLittleWindow") == .expand)
        #expect(PeekControl.pressed(byAction: "reload") == nil)
        #expect(PeekControl.pressed(byAction: "newTab") == nil)
    }
}
