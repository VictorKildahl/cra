import CraCore
import Testing

/// Option-click on a link opens it in Split View, as in Arc (GitHub #298).
struct LinkSplitClickTests {
    static let option = KeyChord.Modifiers.option.rawValue
    static let command = KeyChord.Modifiers.command.rawValue
    static let shift = KeyChord.Modifiers.shift.rawValue
    static let control = KeyChord.Modifiers.control.rawValue
    /// Caps Lock (NSEvent.ModifierFlags.capsLock) and Fn (.function).
    static let capsLock: UInt = 1 << 16
    static let function: UInt = 1 << 23
    static let link = "https://example.com/page"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/298"))
    func optionClickedLinkOpensInSplitInsteadOfDownloading() {
        #expect(LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option, clickAge: 0.02))
        #expect(LinkSplitClick.opensSplit(downloadOf: "http://127.0.0.1:8080/page.html?n=a", clickModifiers: Self.option, clickAge: 0))
        // Caps Lock or Fn held as well still is an Option-click.
        #expect(LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option | Self.capsLock | Self.function, clickAge: 0.1))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/298"))
    func otherDownloadsStayDownloads() {
        // A plain click on a download link, or ⌘-click (a background tab in Chromium).
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: 0, clickAge: 0.02))
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.command, clickAge: 0.02))
        // ⌥⇧ is a Shift-click to Chromium (Peek), ⌥⌘ comes as its own split disposition.
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option | Self.shift, clickAge: 0.02))
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option | Self.command, clickAge: 0.02))
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option | Self.control, clickAge: 0.02))
        // A download that starts long after the click is the page's own.
        #expect(LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option, clickAge: LinkSplitClick.freshness))
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option, clickAge: LinkSplitClick.freshness + 0.01))
        #expect(!LinkSplitClick.opensSplit(downloadOf: Self.link, clickModifiers: Self.option, clickAge: -1))
        // A file the page made has no address a pane could load.
        #expect(!LinkSplitClick.opensSplit(downloadOf: "blob:https://example.com/9f1c", clickModifiers: Self.option, clickAge: 0.02))
        #expect(!LinkSplitClick.opensSplit(downloadOf: "data:text/plain,hi", clickModifiers: Self.option, clickAge: 0.02))
        #expect(!LinkSplitClick.opensSplit(downloadOf: "", clickModifiers: Self.option, clickAge: 0.02))
        // A page never opens a local file, and an app's address asks first, as a plain click does.
        #expect(!LinkSplitClick.opensSplit(downloadOf: "file:///Users/me/page.html", clickModifiers: Self.option, clickAge: 0.02))
        #expect(!LinkSplitClick.opensSplit(downloadOf: "spotify:track:1", clickModifiers: Self.option, clickAge: 0.02))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/298"))
    func optionAloneOrWithCommandSplitsALinkClick() {
        #expect(LinkSplitClick.opensSplit(Self.link, modifiers: Self.option))
        #expect(LinkSplitClick.opensSplit("http://localhost:8080/a", modifiers: Self.option | Self.command))
        #expect(LinkSplitClick.opensSplit(Self.link, modifiers: Self.option | Self.capsLock))
        #expect(!LinkSplitClick.opensSplit(Self.link, modifiers: 0))
        #expect(!LinkSplitClick.opensSplit(Self.link, modifiers: Self.command))
        #expect(!LinkSplitClick.opensSplit(Self.link, modifiers: Self.option | Self.shift))
        #expect(!LinkSplitClick.opensSplit(Self.link, modifiers: Self.option | Self.command | Self.shift))
        #expect(!LinkSplitClick.opensSplit(Self.link, modifiers: Self.option | Self.control))
        #expect(!LinkSplitClick.opensSplit("file:///Users/me/page.html", modifiers: Self.option))
        #expect(!LinkSplitClick.opensSplit("zoommtg://zoom.us/join", modifiers: Self.option))
    }
}
