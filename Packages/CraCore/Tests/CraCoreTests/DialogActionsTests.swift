import CraCore
import Testing

struct DialogActionsTests {
    @Test func destructiveConfirmationKeepsResponseOrderButPutsCancelOnTheLeft() {
        let actions = DialogActions([DialogAction("Delete Folder", role: .destructive), .cancel])
        #expect(actions.buttons[0].title == "Delete Folder")
        #expect(actions.buttons[0].role == .destructive)
        #expect(actions.displayOrder == [1, 0])
        #expect(actions.defaultIndex == 0)
        #expect(actions.cancelIndex == 1)
        #expect(actions.key(at: 0) == "↩")
        #expect(actions.key(at: 1) == "ESC")
    }

    @Test func threeButtonsKeepForceQuitSeparateFromTheDefaultAction() {
        let actions = DialogActions([DialogAction("Try Again"), DialogAction("Force Quit", role: .destructive), .cancel])
        #expect(actions.displayOrder == [2, 1, 0])
        #expect(actions.defaultIndex == 0)
        #expect(actions.cancelIndex == 2)
        #expect(actions.key(at: 1).isEmpty)
    }

    /// Arc 1.172.1's Quit sheet: "Quit, and don’t ask again" at the card's left edge, Cancel and Quit at its right.
    @Test func quitPutsTheSecondaryChoiceAtTheLeftEdge() {
        let actions = DialogActions([DialogAction("Quit"), .cancel, DialogAction("Quit, and don’t ask again", role: .secondary)])
        #expect(actions.leadingOrder == [2])
        #expect(actions.trailingOrder == [1, 0])
        #expect(actions.key(at: 2).isEmpty)
    }

    @Test func singleAcknowledgementAcceptsReturnAndEscape() {
        let actions = DialogActions([DialogAction("OK")])
        #expect(actions.defaultIndex == 0)
        #expect(actions.cancelIndex == 0)
        #expect(actions.displayOrder == [0])
    }

    @Test func cancellationIsExplicitRatherThanGuessedFromTheTitle() {
        let actions = DialogActions([DialogAction("Allow"), DialogAction("Block", role: .cancel)])
        #expect(actions.cancelIndex == 1)
        #expect(actions.buttons[1].title == "Block")
        let secondary = DialogActions([DialogAction("Other", role: .secondary), DialogAction("Close", role: .cancel)])
        #expect(secondary.defaultIndex == nil)
        #expect(secondary.displayOrder == [1, 0])
        #expect(secondary.key(at: 0).isEmpty)
        #expect(DialogActions([DialogAction("Yes"), DialogAction("No", role: .secondary)]).cancelIndex == nil)
    }

    @Test(arguments: [nil, "", "   ", "\n\t"] as [String?])
    func emptyInputDisablesOnlyTheDefaultAction(_ input: String?) {
        let actions = DialogActions([DialogAction("Rename"), .cancel])
        #expect(!actions.isEnabled(at: 0, input: input, requiresInput: true))
        #expect(actions.isEnabled(at: 1, input: input, requiresInput: true))
        #expect(actions.isEnabled(at: 0, input: input, requiresInput: false))
    }

    @Test func nonemptyInputEnablesSubmission() {
        let actions = DialogActions([DialogAction("Rename"), .cancel])
        #expect(actions.isEnabled(at: 0, input: " Work ", requiresInput: true))
    }

    @Test func quitWithoutAskingAgainIsNotTheReturnOrEscapeAction() {
        let actions = DialogActions([DialogAction("Quit"), .cancel, DialogAction("Quit, and don’t ask again", role: .secondary)])
        #expect(actions.displayOrder == [2, 1, 0])
        #expect(actions.defaultIndex == 0)
        #expect(actions.cancelIndex == 1)
        #expect(actions.key(at: 2).isEmpty)
    }
}
