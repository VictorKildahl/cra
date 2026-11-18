import CraCore
import Foundation
import Testing

/// Esc closes a Peek even when its page keeps every Esc, as Gmail does (GitHub #520).
struct PeekEscapeTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func anEscThePageLeavesAloneIsThePages() {
        var escapes = PeekEscapePresses()
        // The page sees it first: Cra waits for it to come back.
        let takes = escapes.beforePage(at: 10, holding: nil, isRepeat: false)
        #expect(!takes)
        escapes.pageLeft()
        // It came back (and closed the Peek): nothing asks afterwards.
        let asks = escapes.pageKept(pressedAt: 10, holding: nil)
        #expect(!asks)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func anEscThePageKeepsAsksAndTheNextOneCloses() {
        var escapes = PeekEscapePresses()
        let takes = escapes.beforePage(at: 10, holding: nil, isRepeat: false)
        #expect(!takes)
        // Not handed back in time: the page kept it, so Close asks (Arc's Esc pill).
        let asks = escapes.pageKept(pressedAt: 10, holding: nil)
        #expect(asks)
        let asksAgain = escapes.pageKept(pressedAt: 10, holding: nil)
        #expect(!asksAgain)
        let hold = PeekCloseHold.after(.escape(prefersConfirmation: true), holding: nil, capturingMedia: false)
        #expect(hold == .escape)
        // While the pill is up, the next Esc is Cra's before the page sees it, and it closes.
        let closes = escapes.beforePage(at: 10.6, holding: hold, isRepeat: false)
        #expect(closes)
        #expect(PeekCloseHold.after(.escape(prefersConfirmation: false), holding: hold, capturingMedia: false) == nil)
        // A call's pill too: Esc closes any pill (Arc).
        let closesACall = escapes.beforePage(at: 11, holding: .mediaInput, isRepeat: false)
        #expect(closesACall)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func aDoubleEscClosesBeforeThePill() {
        var escapes = PeekEscapePresses()
        let first = escapes.beforePage(at: 10, holding: nil, isRepeat: false)
        #expect(!first)
        // The page hasn't handed the first back: the second closes, and the first's check finds nothing.
        let second = escapes.beforePage(at: 10.2, holding: nil, isRepeat: false)
        #expect(second)
        let asks = escapes.pageKept(pressedAt: 10, holding: nil)
        #expect(!asks)
        // After one the page handed back, the next is the page's again.
        _ = escapes.beforePage(at: 20, holding: nil, isRepeat: false)
        escapes.pageLeft()
        let next = escapes.beforePage(at: 20.2, holding: nil, isRepeat: false)
        #expect(!next)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func aHeldEscStaysThePages() {
        var escapes = PeekEscapePresses()
        _ = escapes.beforePage(at: 10, holding: nil, isRepeat: false)
        // Its repeats aren't presses: they don't close, through the pill or the press still waiting.
        let repeatWhileWaiting = escapes.beforePage(at: 10.5, holding: nil, isRepeat: true)
        #expect(!repeatWhileWaiting)
        let repeatWhileAsking = escapes.beforePage(at: 10.7, holding: .escape, isRepeat: true)
        #expect(!repeatWhileAsking)
        let asks = escapes.pageKept(pressedAt: 10, holding: nil)
        #expect(asks)
        #expect(PeekEscapePresses.answerTime == UseBothPresses.answerTime)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func theEscAPeekActsOnIsAPlainEsc() {
        typealias M = KeyChord.Modifiers
        #expect(PeekEscapePresses.isEscape(keyCode: 53, modifiers: 0))
        // Caps Lock (1 << 16) and fn (1 << 23) aren't held for a shortcut.
        #expect(PeekEscapePresses.isEscape(keyCode: 53, modifiers: 1 << 16 | 1 << 23))
        // ⇧Esc, ⌃Esc, ⌥Esc and ⌘Esc are other keys, the page's or another shortcut's.
        for held in [M.shift, .control, .option, .command, [.command, .shift]] {
            #expect(!PeekEscapePresses.isEscape(keyCode: 53, modifiers: held.rawValue))
        }
        // Return (36), Tab (48), Delete (51): not Esc.
        for code: UInt16 in [36, 48, 51] {
            #expect(!PeekEscapePresses.isEscape(keyCode: code, modifiers: 0))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func aPillThatCameUpMeanwhileIsntReplaced() {
        var escapes = PeekEscapePresses()
        _ = escapes.beforePage(at: 10, holding: nil, isRepeat: false)
        // ⌘W on a call raised the call's pill before the Esc's check: it stays the call's.
        let asks = escapes.pageKept(pressedAt: 10, holding: .mediaInput)
        #expect(!asks)
        // And the Esc is forgotten: the next one is the page's, not a second press.
        let takes = escapes.beforePage(at: 12, holding: nil, isRepeat: false)
        #expect(!takes)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/520"))
    func afterThePillGivesUpTheNextEscIsThePagesAgain() {
        var escapes = PeekEscapePresses()
        _ = escapes.beforePage(at: 10, holding: nil, isRepeat: false)
        let asks = escapes.pageKept(pressedAt: 10, holding: nil)
        #expect(asks)
        // The pill gave up (holding nil again): the page sees the next Esc first, and Cra waits again.
        let takes = escapes.beforePage(at: 12, holding: nil, isRepeat: false)
        #expect(!takes)
        let asksAgain = escapes.pageKept(pressedAt: 12, holding: nil)
        #expect(asksAgain)
    }
}
