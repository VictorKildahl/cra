import CraCore
import Testing

struct TypedURLTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/900"))
    func homePathsExpandAndOtherTextKeepsItsRule() {
        #expect(TypedURL.fromInput("~/Desktop/a b.html", home: "/Users/me") == "file:///Users/me/Desktop/a%20b.html")
        #expect(TypedURL.fromInput("~", home: "/Users/me") == "file:///Users/me")
        for input in ["~foo", "~ 50", "cra browser"] {
            #expect(!TypedURL.looksLikeURL(input))
        }
        for input in ["/Users/me/a.html", "/"] {
            #expect(!TypedURL.looksLikeURL(input, filePaths: false))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/900"))
    func filePathsAreAddresses() {
        for input in ["/Users/me/notes/README.html", "/Users/me/My Notes/a b.html", "~/Desktop/a.html", "~", "/", "/r/swift"] {
            #expect(TypedURL.looksLikeURL(input))
        }
        for (input, expected) in [
            ("/Users/me/notes/README.html", "file:///Users/me/notes/README.html"),
            ("  /Users/me/My Notes/a b.html  ", "file:///Users/me/My%20Notes/a%20b.html"),
            ("/", "file:///"),
            ("/r/swift", "file:///r/swift"),
            ("/tmp/a#1?x=%20.html", "file:///tmp/a%231%3Fx=%2520.html"),
            ("/Users/me/dir/", "file:///Users/me/dir/"),
        ] {
            #expect(TypedURL.fromInput(input, home: "/Users/me") == expected)
        }
        #expect(TypedURL.pinnedDestination("/tmp/a.html") == "file:///tmp/a.html")
        #expect(TypedURL.navigation(typed: "/Users/me/a b.html", rowURL: nil, rowIsForTyped: false) == "file:///Users/me/a%20b.html")
    }

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
