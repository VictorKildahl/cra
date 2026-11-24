import CraCore
import Testing

struct ImportedAddressTests {
    /// What Arc import always kept, now every browser's: files, bookmarklets, other browsers' own pages.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/742"), arguments: [
        "https://example.com/",
        "http://localhost:3000",
        "file:///Users/me/notes.html",
        "javascript:void(document.title)",
        "chrome://settings/",
        "edge://settings/",
        "about:preferences",
        "about:blankpage",
        "mailto:a@example.com",
        "spotify:album:1",
        "https://example.com/newtab",
        "http://newtab/",
        "https://startpage/",
        "chrome://vivaldi-webui/settings",
    ])
    func keeps(url: String) {
        #expect(ImportedAddress.keeps(url))
    }

    /// What can't work once imported: nothing, a blank or new tab page, a dead blob:, a Firefox history
    /// query, and Cra's own cra: commands (another app's data never reaches them).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/742"), arguments: [
        "",
        "  \n",
        "about:blank",
        "ABOUT:BLANK",
        "about:blank#frag",
        "about:blank?q=1",
        " about:blank ",
        "about:newtab",
        "about:home",
        "chrome://newtab",
        "chrome://newtab/",
        "edge://newtab/",
        "Brave://NewTab/",
        "opera://startpage",
        "chrome://startpage/",
        "chrome://startpageshared/",
        "vivaldi://startpage",
        "chrome://vivaldi-webui/startpage?section=Speed-dials",
        "blob:https://example.com/5f1c",
        "BLOB:https://example.com/5f1c",
        "place:sort=8&maxResults=10",
        "PLACE:type=6",
        "cra://open?url=file:///etc/hosts",
        "CRA://debug?activate=1",
        "cra:action/newTab",
    ])
    func leavesOut(url: String) {
        #expect(!ImportedAddress.keeps(url))
    }
}
