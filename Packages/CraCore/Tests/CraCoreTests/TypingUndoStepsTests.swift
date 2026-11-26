import CraCore
import Testing

/// The command bar's undo steps (#809): ⌘Z after typing in the bar undoes the typing, a run of letters at a time,
/// as in Arc and any Mac text field.
@Suite struct TypingUndoStepsTests {
    typealias Steps = TypingUndoSteps

    func step(_ steps: inout Steps, _ before: String, _ after: String) -> Bool { steps.startsStep(from: before, to: after) }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/809"))
    func lettersTypedInARowAreOneStep() {
        var steps = Steps()
        #expect(step(&steps, "", "g"))
        #expect(!step(&steps, "g", "gi"))
        #expect(!step(&steps, "gi", "git"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/809"))
    func deletingAfterTypingIsTheNextStep() {
        var steps = Steps()
        _ = steps.startsStep(from: "", to: "gith")
        #expect(step(&steps, "gith", "git"))
        #expect(!step(&steps, "git", "gi"))
        #expect(step(&steps, "gi", "gil"))
    }

    /// A paste over a selection, or a letter typed over all of it: a step of its own each time.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/809"))
    func replacingIsAlwaysItsOwnStep() {
        var steps = Steps()
        #expect(Steps.kind(from: "https://arc.net/", to: "g") == .replacing)
        #expect(step(&steps, "https://arc.net/", "g"))
        #expect(!step(&steps, "g", "g"))
        #expect(step(&steps, "github", "gitlab"))
        #expect(step(&steps, "gitlab", "gitlub"))
    }

    /// An undo, a row arrowed to, or the bar's own text: the next letters start a new step.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/809"))
    func closingStartsANewStep() {
        var steps = Steps()
        _ = steps.startsStep(from: "", to: "a")
        steps.close()
        #expect(step(&steps, "a", "ab"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/809"))
    func typingOrDeletingInTheMiddle() {
        #expect(Steps.kind(from: "gthub", to: "github") == .inserting)
        #expect(Steps.kind(from: "github", to: "gthub") == .deleting)
        #expect(Steps.kind(from: "hub", to: "github") == .inserting)
        #expect(Steps.kind(from: "abc", to: "xbc") == .replacing)
        #expect(Steps.kind(from: "", to: "") == .replacing)
    }
}
