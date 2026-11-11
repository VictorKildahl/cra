import CraCore
import Testing

struct ViewSourceTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"), arguments: [
        ("https://example.com/a?b=1#c", "view-source:https://example.com/a?b=1#c"),
        ("http://127.0.0.1:8080/page.html", "view-source:http://127.0.0.1:8080/page.html"),
        ("HTTPS://Example.com/", "view-source:HTTPS://Example.com/"),
        ("file:///Users/me/notes.html", "view-source:file:///Users/me/notes.html"),
    ])
    func pageOpensItsSource(url: String, source: String) {
        #expect(ViewSource.address(for: url) == source)
    }

    @Test(arguments: [
        "", "about:blank", "view-source:https://example.com/", "easel://8F2C", "chrome://settings",
        "data:text/html,hi", "javascript:alert(1)", "https", "example.com",
    ])
    func noSourceToShow(url: String) {
        #expect(ViewSource.address(for: url) == nil)
    }
}
