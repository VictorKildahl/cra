import CraCore
import Foundation
import Testing

/// Arc Max's ChatGPT in the Command Bar and ⌥⌘G, measured live on Arc 1.174 (27 Nov 2026, #828).
struct ChatGPTCommandBarTests {
    /// With the switch on, "chatg" offers ChatGPT ("Ask ChatGPT  Tab"), and the scope asks on chatgpt.com: a "ChatGPT"
    /// pill in Arc's #75A99C, "Send a Message…", and a row without a caption. Off, nothing offers it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/828"))
    func typingChatGPTOffersItsScopeOnlyWhenOn() {
        let on = SiteSearch.match("chatg", completion: nil, sites: ChatGPTCommandBar.sites(enabled: true))
        #expect(on == ChatGPTCommandBar.site)
        #expect(on?.hint == "Ask ChatGPT" && on?.placeholder == "Send a Message…" && on?.rowCaption == nil)
        #expect(on?.color == "#75A99C")
        #expect(on?.searchURL("what is 2 + 2?") == "https://chatgpt.com/?q=what%20is%202%20+%202?")
        #expect(SiteSearch.match("chatg", completion: nil, sites: ChatGPTCommandBar.sites(enabled: false)) == nil)
        // Arc's other sites keep their own hint, placeholder and caption.
        let youtube = SiteSearch.match("youtu", completion: nil, sites: ChatGPTCommandBar.sites(enabled: true))
        #expect(youtube?.hint == "Search YouTube" && youtube?.placeholder == "Search…" && youtube?.rowCaption == "Search YouTube")
    }

    /// A question in the plain bar gets the "Ask ChatGPT" row, third as in Arc; not an address, not an empty field,
    /// not with the switch off.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/828"))
    func theAskRowIsThirdForWordsTyped() {
        #expect(ChatGPTCommandBar.offersAskRow(query: "what is two plus two", enabled: true, looksLikeURL: false))
        #expect(!ChatGPTCommandBar.offersAskRow(query: "what is two plus two", enabled: false, looksLikeURL: false))
        #expect(!ChatGPTCommandBar.offersAskRow(query: "example.com", enabled: true, looksLikeURL: true))
        #expect(!ChatGPTCommandBar.offersAskRow(query: "  ", enabled: true, looksLikeURL: false))
        #expect(ChatGPTCommandBar.askRowIndex(rowCount: 5) == 2)
        #expect(ChatGPTCommandBar.askRowIndex(rowCount: 1) == 1)
    }

    /// ⌥⌘G opens the bar scoped to ChatGPT; with the switch off, the plain bar (Arc 1.174 measured both).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/828"))
    func newMessageOpensTheScopeWhenOn() {
        #expect(ChatGPTCommandBar.newMessage(enabled: true) == .scopedToChatGPT)
        #expect(ChatGPTCommandBar.newMessage(enabled: false) == .plainBar)
    }

    /// The Max row's text names the shortcut when there is one, else says to type ChatGPT and Tab (Arc's two strings).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/828"))
    func theSettingsRowTextIsArcs() {
        #expect(ChatGPTCommandBar.settingsTitle == "ChatGPT in the Command Bar")
        #expect(ChatGPTCommandBar.settingsDetail(shortcut: "⌥⌘G") == "Add ChatGPT to your Search suggestions, or press ⌥⌘G to ask any question instantly.")
        #expect(ChatGPTCommandBar.settingsDetail(shortcut: nil) == "Add ChatGPT to your Search suggestions, or start typing ChatGPT, hit Tab, to ask any question instantly.")
        #expect(AppSettings().chatGPTInCommandBar == false)
    }
}
