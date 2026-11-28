import Foundation

/// Arc Max's ChatGPT in the Command Bar (`gptSiteSearchEnabled`, Settings ▸ Max; measured live on Arc 1.174, 27 Nov
/// 2026, #828). With it on, ChatGPT is one of the bar's site searches: typing the start of "chatgpt" offers it ("Ask
/// ChatGPT  Tab" at the field's end), Tab scopes the bar to it (a "ChatGPT" pill, "Send a Message…"), and Return asks
/// ChatGPT on its site. A question typed in the plain bar gets Arc's "Ask ChatGPT" row, third. ⌥⌘G (Arc's `gptMessage`,
/// "Compose a ChatGPT message in the Command Bar.") opens the bar already scoped to ChatGPT; with the switch off it
/// opens the plain bar. Nothing goes to OpenAI from Cra: the message goes to chatgpt.com as a page load, signed in as
/// the page is.
public enum ChatGPTCommandBar {
    /// Arc's SearchEngine.chatGPT: its template on chat.openai.com (which now redirects to chatgpt.com, kept with the
    /// query) and its colour, #75A99C (drawn #64AB9C on the dark bar).
    public static let site = SiteSearch(name: "ChatGPT", host: "chatgpt.com", url: "https://chatgpt.com/?q=%s", color: "#75A99C")
    /// The hint at the field's end and the row's caption.
    public static let ask = "Ask ChatGPT"
    /// The scoped field's placeholder.
    public static let placeholder = "Send a Message…"
    public static let actionID = "newChatGPTMessage"
    public static let actionName = "New ChatGPT Message"

    public static let settingsTitle = "ChatGPT in the Command Bar"
    /// Arc's two texts: with a shortcut set for the action it names it, without one it says to type ChatGPT and Tab.
    public static func settingsDetail(shortcut: String?) -> String {
        if let shortcut, !shortcut.isEmpty { return "Add ChatGPT to your Search suggestions, or press \(shortcut) to ask any question instantly." }
        return "Add ChatGPT to your Search suggestions, or start typing ChatGPT, hit Tab, to ask any question instantly."
    }

    /// The site searches Tab can offer: Arc's list, and ChatGPT while the switch is on.
    public static func sites(enabled: Bool) -> [SiteSearch] { enabled ? SiteSearch.all + [site] : SiteSearch.all }

    /// Whether the plain bar gets Arc's "Ask ChatGPT" row for what is typed: on, with words typed, not an address.
    public static func offersAskRow(query: String, enabled: Bool, looksLikeURL: Bool) -> Bool {
        enabled && !looksLikeURL && !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Where the row goes: third, after the typed search and the first suggestion, as Arc listed it.
    public static func askRowIndex(rowCount: Int) -> Int { min(2, rowCount) }

    /// What ⌥⌘G opens.
    public enum Opening: Equatable, Sendable { case scopedToChatGPT, plainBar }
    public static func newMessage(enabled: Bool) -> Opening { enabled ? .scopedToChatGPT : .plainBar }
}
