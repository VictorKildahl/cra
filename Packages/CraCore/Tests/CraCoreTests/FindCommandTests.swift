import CraCore
import Testing

struct FindCommandTests {
    /// GitHub #577: ⌘F in a Little Window did nothing; it dropped Edit ▸ Find's commands. Each of
    /// them is a command its own find bar answers.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/577"))
    func findCommandsAreTheBarsToAnswer() {
        #expect(FindCommand(action: "find") == .show)
        #expect(FindCommand(action: "findNext") == .step(forward: true))
        #expect(FindCommand(action: "findPrevious") == .step(forward: false))
        #expect(FindCommand(action: "useSelectionForFind") == .useSelection)
        #expect(FindCommand(action: "find")?.effect(barShown: false) == .showBar)
        #expect(FindCommand(action: "find")?.effect(barShown: true) == .showBar)
    }

    @Test func otherActionsAreNotFindCommands() {
        for id in ["jumpToSelection", "findInSidebar", "newTab", "", "Find"] { #expect(FindCommand(action: id) == nil) }
    }

    /// ⌘G and ⇧⌘G search again while the bar is up; with it closed they open it.
    @Test func nextAndPreviousOpenAClosedBar() {
        #expect(FindCommand.step(forward: true).effect(barShown: true) == .search(forward: true))
        #expect(FindCommand.step(forward: false).effect(barShown: true) == .search(forward: false))
        #expect(FindCommand.step(forward: true).effect(barShown: false) == .showBar)
        #expect(FindCommand.step(forward: false).effect(barShown: false) == .showBar)
        #expect(FindCommand.useSelection.effect(barShown: false) == .searchSelection)
        #expect(FindCommand.useSelection.effect(barShown: true) == .searchSelection)
    }
}
