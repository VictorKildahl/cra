import CraCore
import Testing

struct FaviconKeyTests {
    @Test(arguments: [
        ("https://Mail.Example.com/inbox?x=1", "mail.example.com" as String?),
        ("http://localhost:3000/", "localhost"),
        ("https://www.example.com/", "www.example.com"),
        ("notes", nil),
        ("about:blank", nil),
        ("file:///tmp/a.html", nil),
    ])
    func keyIsTheLowercasedHost(url: String, key: String?) {
        #expect(FaviconKey.key(for: url) == key)
    }
}
