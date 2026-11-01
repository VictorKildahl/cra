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

    @Test func searchesAreNotAddresses() {
        #expect(!TypedURL.looksLikeURL("cra browser"))
        #expect(TypedURL.looksLikeURL("view-source:https://example.com"))
        #expect(TypedURL.fromInput("example.com") == "https://example.com")
        #expect(TypedURL.fromInput("localhost:3000/a") == "http://localhost:3000/a")
        #expect(TypedURL.fromInput("http://localhost:3000") == "http://localhost:3000")
        #expect(TypedURL.fromInput("mailto:a@example.com") == "mailto:a@example.com")
    }
}
