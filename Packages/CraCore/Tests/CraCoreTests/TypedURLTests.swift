import CraCore
import Testing

struct TypedURLTests {
    @Test(arguments: [
        ("example.org/new?q=1", "https://example.org/new?q=1" as String?),
        ("  https://Example.com/a#b  ", "https://Example.com/a#b"),
        ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.1/admin", "http://192.168.1.1/admin"),
        ("file:///tmp/a.html", "file:///tmp/a.html"),
        ("about:blank", "about:blank"),
        ("", nil),
        ("hello world", nil),
        ("notes", nil),
        ("javascript:alert(1)", nil),
        ("https://", nil),
        ("http:///path", nil),
    ])
    func pinnedDestination(input: String, url: String?) {
        #expect(TypedURL.pinnedDestination(input) == url)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/512"))
    func textTypedPastAGoToRowIsSearchedUnlessItIsAnAddress() {
        // Still the row's text: the row's address.
        #expect(TypedURL.navigation(typed: "example.com", rowURL: "https://example.com/", rowIsForTyped: true) == "https://example.com/")
        // A comma typed before the rows caught up: not an address, so it is searched.
        #expect(TypedURL.navigation(typed: "example.com,", rowURL: "https://example.com/", rowIsForTyped: false) == nil)
        // More of an address typed past the row: that address.
        #expect(TypedURL.navigation(typed: "example.com/shop", rowURL: "https://example.com/", rowIsForTyped: false) == "https://example.com/shop")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/545"), arguments: [
        ("chapter-2.16", false),
        ("3.14", false),
        ("v2.5", false),
        ("example.com", true),
        ("sub.example.co.uk/path", true),
        ("example.com:8080/a", true),
        ("192.168.1.1", true),
        ("localhost:3000", true),
    ])
    func aTopLevelDomainHasALetter(input: String, isAddress: Bool) {
        #expect(TypedURL.looksLikeURL(input) == isAddress)
    }

    @Test func searchesAreNotAddresses() {
        #expect(!TypedURL.looksLikeURL("cra browser"))
        #expect(TypedURL.looksLikeURL("view-source:https://example.com"))
        #expect(TypedURL.fromInput("example.com") == "https://example.com")
        #expect(TypedURL.fromInput("localhost:3000/a") == "http://localhost:3000/a")
        #expect(TypedURL.fromInput("http://localhost:3000") == "http://localhost:3000")
        #expect(TypedURL.fromInput("mailto:a@example.com") == "mailto:a@example.com")
    }
}
