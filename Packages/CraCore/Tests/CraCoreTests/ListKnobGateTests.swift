import CraCore
import Testing

struct ListKnobGateTests {
    /// A touch on a list at rest may start a swipe between spaces: the knob AppKit flashes at it
    /// stays hidden until the gesture scrolls the list.
    @Test func aTouchOnAListAtRestHidesTheKnob() {
        var gate = ListKnobGate()
        gate.touched(at: 100)
        #expect(gate.hidden)
        gate.reveal()
        #expect(!gate.hidden)
    }

    /// Scrolling a long list is flick after flick: each touches the trackpad while the last one's
    /// momentum still scrolls, the knob showing. Hiding it at each touch made it blink (#544).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/544"))
    func aTouchWhileTheListScrollsKeepsTheKnob() {
        var gate = ListKnobGate()
        gate.listScrolled(at: 100)
        gate.listScrolled(at: 100.4)
        gate.touched(at: 100.45)
        #expect(!gate.hidden)
        // A touch to stop the momentum, fingers lifted, then the next flick.
        gate.touched(at: 101.2)
        #expect(!gate.hidden)
    }

    /// Once AppKit has faded the knob out after the last scroll, a touch hides it again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/544"))
    func aTouchAfterTheKnobFadedHidesIt() {
        var gate = ListKnobGate()
        gate.listScrolled(at: 100)
        gate.touched(at: 100 + ListKnobGate.shownAfterScroll)
        #expect(gate.hidden)
    }

    /// A scroll shows the knob a touch hid: the gesture went vertical, or a wheel turned.
    @Test func aScrollShowsTheKnob() {
        var gate = ListKnobGate()
        gate.touched(at: 100)
        gate.listScrolled(at: 100.1)
        #expect(!gate.hidden)
    }
}
