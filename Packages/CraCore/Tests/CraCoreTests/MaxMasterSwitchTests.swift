import CraCore
import Testing

/// Arc's Max pane button (Arc 1.172.2, from its binary: `MaxFeaturesState`): "Turn On All" while some of the
/// features are on, "Turn On Max" with none, "Turn Off Max" with all; a press sets every feature the same.
struct MaxMasterSwitchTests {
    @Test func theButtonSaysWhatItWillDo() {
        #expect(MaxMasterSwitch.title([true, true, true, true]) == "Turn Off Max")
        #expect(MaxMasterSwitch.title([true, false, true, false]) == "Turn On All")
        #expect(MaxMasterSwitch.title([false, false, false, false]) == "Turn On Max")
        #expect(MaxMasterSwitch.title([]) == "Turn On Max", "no feature to count: it offers to turn them on")
    }

    @Test func aPressTurnsEverythingOnUnlessEverythingIsOn() {
        #expect(!MaxMasterSwitch.pressTurnsOn([true, true]))
        #expect(MaxMasterSwitch.pressTurnsOn([true, false]))
        #expect(MaxMasterSwitch.pressTurnsOn([false, false]))
        #expect(MaxMasterSwitch.pressTurnsOn([]))
    }

    @Test func theButtonIsEmphasisedUnlessItTurnsMaxOff() {
        #expect(MaxMasterSwitch.isEmphasised([false, true]))
        #expect(MaxMasterSwitch.isEmphasised([false, false]))
        #expect(!MaxMasterSwitch.isEmphasised([true, true]))
    }
}
