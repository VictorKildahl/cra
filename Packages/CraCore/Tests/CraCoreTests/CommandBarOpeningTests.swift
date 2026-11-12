import CraCore
import Testing

struct CommandBarOpeningTests {
    /// GitHub #379: ⌘T in a Peek opened the Peek's own bar on its address, so the only rows were the
    /// Peek's page. It opens the browser window's New Tab bar, with its tabs; ⌘L still edits the Peek.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/379"))
    func commandTInAPeekIsTheBrowserWindowsNewTab() {
        #expect(CommandBarOpening.of(.newTab, in: .peek, hasPage: true) == CommandBarOpening(owner: .browserWindow, mode: .newTab))
        #expect(CommandBarOpening.of(.newTab, in: .peek, hasPage: false) == CommandBarOpening(owner: .browserWindow, mode: .newTab))
        #expect(CommandBarOpening.of(.editURL, in: .peek, hasPage: true) == CommandBarOpening(owner: .ownWindow, mode: .editURL))
    }

    /// Little Arc (Arc 1.168, live): ⌘T is ⌘L there, the window's bar on its address; empty, a new page.
    @Test func littleWindowKeepsItsOwnBar() {
        #expect(CommandBarOpening.of(.newTab, in: .littleWindow, hasPage: true) == CommandBarOpening(owner: .ownWindow, mode: .editURL))
        #expect(CommandBarOpening.of(.editURL, in: .littleWindow, hasPage: true) == CommandBarOpening(owner: .ownWindow, mode: .editURL))
        #expect(CommandBarOpening.of(.newTab, in: .littleWindow, hasPage: false) == CommandBarOpening(owner: .ownWindow, mode: .newTab))
        #expect(CommandBarOpening.of(.editURL, in: .littleWindow, hasPage: false) == CommandBarOpening(owner: .ownWindow, mode: .newTab))
    }

    @Test func browserWindowOpensWhatTheKeySays() {
        #expect(CommandBarOpening.of(.newTab, in: .browser, hasPage: true) == CommandBarOpening(owner: .ownWindow, mode: .newTab))
        #expect(CommandBarOpening.of(.editURL, in: .browser, hasPage: true) == CommandBarOpening(owner: .ownWindow, mode: .editURL))
    }
}
