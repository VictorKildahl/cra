import CraCore
import Testing

/// The link preview at the page's bottom left, as Arc 1.17x shows it (GitHub #689).
struct LinkPreviewTests {
    static let option = KeyChord.Modifiers.option.rawValue
    static let command = KeyChord.Modifiers.command.rawValue
    static let shift = KeyChord.Modifiers.shift.rawValue
    static let control = KeyChord.Modifiers.control.rawValue
    /// Caps Lock (NSEvent.ModifierFlags.capsLock).
    static let capsLock: UInt = 1 << 16
    static let link = "https://adblock-tester.com/ad-blockers/"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/689"))
    func withNoKeyHeldTheAddressShowsWithoutItsSchemeOrTrailingSlash() {
        // Arc's capsule over adblock-tester.com: "adblock-tester.com/ad-blockers".
        #expect(LinkPreview.text(Self.link, modifiers: 0, peekOnShiftClick: true)
                == .init(lead: "", emphasis: "", trail: "adblock-tester.com/ad-blockers"))
        #expect(LinkPreview.shortAddress("http://example.com/") == "example.com")
        #expect(LinkPreview.shortAddress("https://example.com") == "example.com")
        #expect(LinkPreview.shortAddress("https://www.example.com/a/b?q=1#top") == "www.example.com/a/b?q=1#top")
        #expect(LinkPreview.shortAddress("https://example.com/search?q=a/") == "example.com/search?q=a/")
        // Other schemes and text that isn't an address show as the page gave them.
        #expect(LinkPreview.shortAddress("mailto:someone@example.com") == "mailto:someone@example.com")
        #expect(LinkPreview.shortAddress("javascript:void(0)") == "javascript:void(0)")
        #expect(LinkPreview.shortAddress("file:///Users/me/a.html") == "file:///Users/me/a.html")
        #expect(LinkPreview.shortAddress("Loading…") == "Loading…")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/689"))
    func aHeldKeySaysWhatAClickWillDo() {
        // Arc: "Open <the whole address> in Peek / in Split View / in a new tab", the address bright.
        #expect(LinkPreview.text(Self.link, modifiers: Self.shift, peekOnShiftClick: true)
                == .init(lead: "Open ", emphasis: Self.link, trail: " in Peek"))
        #expect(LinkPreview.text(Self.link, modifiers: Self.option, peekOnShiftClick: true)
                == .init(lead: "Open ", emphasis: Self.link, trail: " in Split View"))
        #expect(LinkPreview.text(Self.link, modifiers: Self.command, peekOnShiftClick: true)
                == .init(lead: "Open ", emphasis: Self.link, trail: " in a new tab"))
        // Caps Lock doesn't change it.
        #expect(LinkPreview.click(Self.link, modifiers: Self.option | Self.capsLock, peekOnShiftClick: true) == .splitView)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/689"))
    func theHintFollowsWhatCraDoesWithTheClick() {
        // ⌘⌥ is Chromium's split view click and ⌘⇧ a front tab (LinkSplitClick, Chromium's dispositions).
        #expect(LinkPreview.click(Self.link, modifiers: Self.command | Self.option, peekOnShiftClick: true) == .splitView)
        #expect(LinkPreview.click(Self.link, modifiers: Self.command | Self.shift, peekOnShiftClick: true) == .newTab)
        // ⌥⇧ is a Shift-click to Chromium.
        #expect(LinkPreview.click(Self.link, modifiers: Self.option | Self.shift, peekOnShiftClick: true) == .peek)
        // With Settings ▸ Links' Shift-click Peek off (or in incognito), Shift isn't a Peek: no hint.
        #expect(LinkPreview.click(Self.link, modifiers: Self.shift, peekOnShiftClick: false) == nil)
        #expect(LinkPreview.text(Self.link, modifiers: Self.shift, peekOnShiftClick: false).trail == "adblock-tester.com/ad-blockers")
        // ⌃-click is a right-click on a Mac.
        #expect(LinkPreview.click(Self.link, modifiers: Self.control, peekOnShiftClick: true) == nil)
        #expect(LinkPreview.click(Self.link, modifiers: Self.control | Self.command, peekOnShiftClick: true) == nil)
        // A mail or script link doesn't open in a Peek, a split or a tab.
        #expect(LinkPreview.click("mailto:someone@example.com", modifiers: Self.command, peekOnShiftClick: true) == nil)
        #expect(LinkPreview.click("javascript:void(0)", modifiers: Self.option, peekOnShiftClick: true) == nil)
        #expect(LinkPreview.click("Loading…", modifiers: Self.shift, peekOnShiftClick: true) == nil)
    }
}
