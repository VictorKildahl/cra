import CraCore
import Testing

struct LittleWindowLinksTests {
    /// GitHub #599: a link in a Little Window that asked for a new tab opened one more Little Window
    /// each time. It loads in the window, as a Shift-click does.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/599"))
    func newTabLinkLoadsInTheWindow() {
        #expect(LittleWindowLinks.loadsInWindow("https://example.com/a", shiftClick: false, newTab: true))
        #expect(LittleWindowLinks.loadsInWindow("http://127.0.0.1:8080/page.html?n=2", shiftClick: false, newTab: true))
        #expect(LittleWindowLinks.loadsInWindow("file:///tmp/a.html", shiftClick: false, newTab: true))
    }

    /// Arc 1.171: a Shift-click loads in the Little Arc (any address, as before).
    @Test func shiftClickLoadsInTheWindow() {
        #expect(LittleWindowLinks.loadsInWindow("https://example.com/", shiftClick: true, newTab: false))
        #expect(LittleWindowLinks.loadsInWindow("about:blank", shiftClick: true, newTab: false))
    }

    /// A page a script fills in later keeps its opener as a pop-up; a plain click navigates as usual.
    @Test func otherLinksAreNotTaken() {
        #expect(!LittleWindowLinks.loadsInWindow("about:blank", shiftClick: false, newTab: true))
        #expect(!LittleWindowLinks.loadsInWindow("javascript:void(0)", shiftClick: false, newTab: true))
        #expect(!LittleWindowLinks.loadsInWindow("not a url", shiftClick: false, newTab: true))
        #expect(!LittleWindowLinks.loadsInWindow("https://example.com/", shiftClick: false, newTab: false))
    }
}
