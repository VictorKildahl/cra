import CraCore
import Testing

/// #663 follow-up (Victor, 22 Nov 2026): Arc 1.174.1's ⌘L on a local page edits the developer bar in place, its
/// suggestions dropping across the page card; an ordinary site keeps the centred bar.
struct DeveloperBarPanelTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/663"))
    func onlyTheDeveloperBarEditsInPlace() {
        #expect(DeveloperBarPanel.opens(editingURL: true, barIsDeveloper: true, barShown: true))
        #expect(!DeveloperBarPanel.opens(editingURL: true, barIsDeveloper: false, barShown: true), "an ordinary site: the centred bar")
        #expect(!DeveloperBarPanel.opens(editingURL: true, barIsDeveloper: true, barShown: false), "the toolbar hidden")
        #expect(!DeveloperBarPanel.opens(editingURL: false, barIsDeveloper: true, barShown: true), "⌘T: a new tab's bar")
    }

    /// Arc's panel with five rows ran from the bar's top (y 43.5) to 347: 303.5 pt; the field row is the bar's 40.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/663"))
    func heightIsArcs() {
        #expect(DeveloperBarPanel.height(rows: 5) == 303.5)
        #expect(DeveloperBarPanel.height(rows: 0) == 40)
        #expect(DeveloperBarPanel.height(rows: 1) == 40 + 6 + 46 + 11.5)
    }
}
