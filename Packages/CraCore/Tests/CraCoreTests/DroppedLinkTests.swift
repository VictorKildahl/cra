import CraCore
import Testing

/// What a drag into the sidebar's list opens as a tab (#419).
struct DroppedLinkTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/419"))
    func theFirstWebAddressOnThePasteboardOpens() {
        // A page's link drag: the URL object and its text agree.
        #expect(DroppedLink.address(urls: ["https://example.com/a"], text: "https://example.com/a") == "https://example.com/a")
        // Two links (another app's drag): the first, as Arc takes one external item.
        #expect(DroppedLink.address(urls: ["https://one.example", "https://two.example"], text: nil) == "https://one.example")
        // A selected address dragged as text.
        #expect(DroppedLink.address(urls: [], text: " http://example.org/b \n") == "http://example.org/b")
        // A file from Finder isn't a web page; its name as text isn't either.
        #expect(DroppedLink.address(urls: ["file:///Users/me/notes.txt"], text: "notes.txt") == nil)
        // A file next to a web address: the address.
        #expect(DroppedLink.address(urls: ["file:///tmp/a.png"], text: "https://example.net") == "https://example.net")
        #expect(DroppedLink.address(urls: ["javascript:alert(1)"], text: "some words") == nil)
        #expect(DroppedLink.address(urls: [], text: nil) == nil)
    }
}
