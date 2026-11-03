import CraCore
import Testing

struct PinnedNavigationTests {
    @Test func anotherHostOpensANewTab() {
        #expect(PinnedNavigation.typedURLOpensNewTab("http://away.lvh.me:47139/a.html", from: "http://pin.lvh.me:47139/c.html"))
        #expect(!PinnedNavigation.typedURLOpensNewTab("http://pin.lvh.me:47139/away1.html", from: "http://pin.lvh.me:47139/c.html"))
        #expect(!PinnedNavigation.typedURLOpensNewTab("https://GitHub.com/o/r", from: "https://github.com/"), "hosts compare without case")
        #expect(PinnedNavigation.typedURLOpensNewTab("https://www.google.com/search?q=x", from: "https://github.com/"), "a search leaves the site")
        #expect(!PinnedNavigation.typedURLOpensNewTab("not a url", from: "https://github.com/"))
    }

    @Test func peekFollowsTheHost() {
        #expect(PinnedNavigation.linkLeavesHost("http://away.lvh.me:47139/away2.html", from: "http://pin.lvh.me:47139/c.html"))
        #expect(!PinnedNavigation.linkLeavesHost("http://pin.lvh.me:47139/away1.html", from: "http://pin.lvh.me:47139/c.html"))
        #expect(!PinnedNavigation.linkLeavesHost("mailto:a@b.c", from: "https://github.com/"))
    }
}
