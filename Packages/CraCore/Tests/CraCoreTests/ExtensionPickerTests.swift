import CraCore
import Testing

/// Arc's ⌘E steps through the extensions while ⌘ is held and opens the one ringed when ⌘ is let go (#709).
@Suite struct ExtensionPickerTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/709"))
    func eachPressRingsTheNextExtension() {
        var picker = ExtensionPicker()
        #expect(picker.picked(among: 20) == 0)
        picker.press()
        #expect(picker.picked(among: 20) == 1)
        picker.press()
        #expect(picker.picked(among: 20) == 2)
    }

    /// Past the last extension it starts at the first again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/709"))
    func pastTheLastItStartsAgain() {
        var picker = ExtensionPicker()
        for _ in 0..<3 { picker.press() }
        #expect(picker.picked(among: 3) == 0)
        picker.press()
        #expect(picker.picked(among: 3) == 1)
    }

    /// No extensions: nothing is ringed, and letting go of ⌘ opens nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/709"))
    func noExtensionsRingsNothing() {
        var picker = ExtensionPicker()
        picker.press()
        #expect(picker.picked(among: 0) == nil)
    }

    /// The keyboard with ⌘ held opens the picker; ⌘E again while it is up steps; the menu, the command bar or a
    /// shortcut rebound without ⌘ open the Site Control Center as its button does.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/709"))
    func whatAPressDoes() {
        #expect(ExtensionPicker.press(commandHeld: true, picking: false) == .openPicking)
        #expect(ExtensionPicker.press(commandHeld: true, picking: true) == .step)
        #expect(ExtensionPicker.press(commandHeld: false, picking: false) == .toggle)
        // A picker is only up while ⌘ is held, but a press that says otherwise still steps rather than closes it.
        #expect(ExtensionPicker.press(commandHeld: false, picking: true) == .step)
    }
}
