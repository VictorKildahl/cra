import CraCore
import Foundation
import Testing

/// A boost's site icon on Library ▸ Boosts, read from the site's home page.
struct SiteIconTests {
    static let base = URL(string: "https://arc.net/")!

    @Test func theLargestBitmapComesFirstThenFaviconIco() {
        let html = """
        <head><link rel="icon" href="/icon.svg" type="image/svg+xml"><link rel='icon' sizes='32x32' href='/i32.png'>
        <LINK REL="apple-touch-icon" sizes="180x180" href="https://cdn.arc.net/touch.png?v=1&amp;x=2"><link rel=stylesheet href=/a.css></head>
        """
        #expect(SiteIcon.candidates(html: html, base: Self.base).map(\.absoluteString) == [
            "https://cdn.arc.net/touch.png?v=1&x=2", "https://arc.net/i32.png", "https://arc.net/icon.svg", "https://arc.net/favicon.ico",
        ])
    }

    @Test func aPageWithoutIconsHasFaviconIco() {
        #expect(SiteIcon.candidates(html: "<html></html>", base: Self.base).map(\.absoluteString) == ["https://arc.net/favicon.ico"])
    }

    @Test func shortcutIconAndRelativePathsCount() {
        let html = #"<link rel="shortcut icon" href="static/fav.ico"><link rel="icon" href="javascript:alert(1)">"#
        #expect(SiteIcon.candidates(html: html, base: URL(string: "https://github.com/a/")!).map(\.absoluteString)
                == ["https://github.com/a/static/fav.ico", "https://github.com/favicon.ico"])
    }
}
