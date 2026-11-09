import CraCore
import Testing

/// What a `cra://` URL brings to the front before it runs.
struct InternalURLRaiseTests {
    /// `cra://open?url=…&background=1` adds the tab without switching to it, so Cra stays behind
    /// the app in use. It came to the front anyway, showing the tab that was already open.
    @Test(arguments: [false, true])
    func aBackgroundOpenLeavesCraWhereItIs(littleWindowIsKey: Bool) {
        #expect(!InternalURLRaise.raises(host: "open", little: false, background: true, littleWindowIsKey: littleWindowIsKey))
    }

    /// A plain open shows its tab, so the window and Cra come forward.
    @Test func anOpenBringsCraForward() {
        #expect(InternalURLRaise.raises(host: "open", little: false, background: false, littleWindowIsKey: false))
    }

    /// A Little Window brings itself forward on the Space in use; the browser window stays (#186).
    @Test func aLittleWindowOpenLeavesTheBrowserWindowWhereItIs() {
        #expect(!InternalURLRaise.raises(host: "open", little: true, background: false, littleWindowIsKey: false))
    }

    /// An action goes to the key Little Window when there is one; otherwise the browser window
    /// comes forward to take it, as do the command bar and dismiss.
    @Test func actionsAndTheCommandBarBringTheBrowserWindowForward() {
        #expect(!InternalURLRaise.raises(host: "action", little: false, background: false, littleWindowIsKey: true))
        #expect(InternalURLRaise.raises(host: "action", little: false, background: false, littleWindowIsKey: false))
        #expect(InternalURLRaise.raises(host: "commandbar", little: false, background: false, littleWindowIsKey: true))
        #expect(InternalURLRaise.raises(host: "dismiss", little: false, background: false, littleWindowIsKey: false))
    }
}
