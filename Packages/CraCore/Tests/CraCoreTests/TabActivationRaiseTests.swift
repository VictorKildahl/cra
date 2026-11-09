import CraCore
import Testing

/// A tab brought to the front by an extension or by its page (GitHub #38, #239).
struct TabActivationRaiseTests {
    /// #239: a Cra window on each monitor, on the same space, someone else's app over the left
    /// one. Switching tabs in the right window brought the left one up over that app. Pages move to
    /// the window in use, so the left window holds the space's other pages, and an extension that
    /// activates one of them (tab managers react to every switch) reached the left window, which
    /// raised itself although the right window had the keyboard. It selects the tab and stays put.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/239"))
    func anExtensionNeverRaisesAWindowBehindTheOneInUse() {
        #expect(TabActivationRaise.outcome(byPage: false, appActive: true, windowIsKey: false, anotherBrowserWindowIsKey: true) == .none)
    }

    /// #38: with no other browser window in use (a Settings or Little Window has the keyboard),
    /// the tab's window comes forward, as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/239"))
    func anExtensionRaisesItsWindowWhenNoOtherBrowserWindowIsInUse() {
        #expect(TabActivationRaise.outcome(byPage: false, appActive: true, windowIsKey: false, anotherBrowserWindowIsKey: false) == .window)
    }

    /// The window in use only selects the tab; an extension never makes Cra the active app.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/239"))
    func anExtensionLeavesTheWindowInUseAndOtherAppsAlone() {
        #expect(TabActivationRaise.outcome(byPage: false, appActive: true, windowIsKey: true, anotherBrowserWindowIsKey: false) == .none)
        #expect(TabActivationRaise.outcome(byPage: false, appActive: false, windowIsKey: false, anotherBrowserWindowIsKey: false) == .none)
    }

    /// A page may ask only after a click on its notification or from its opener (Chromium's rule):
    /// its window and Cra come forward, like Arc (Messenger's chat opens on a click).
    @Test(arguments: [false, true])
    func aPageAlwaysBringsItsWindowAndCraForward(otherKey: Bool) {
        #expect(TabActivationRaise.outcome(byPage: true, appActive: false, windowIsKey: false, anotherBrowserWindowIsKey: otherKey) == .windowAndApp)
        #expect(TabActivationRaise.outcome(byPage: true, appActive: true, windowIsKey: false, anotherBrowserWindowIsKey: otherKey) == .windowAndApp)
    }
}
