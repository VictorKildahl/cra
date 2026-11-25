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

/// Where a site's icon may be fetched from: a public site's page or redirect never reaches the Mac
/// itself or the local network, which only a local site of the user's own may.
struct SiteIconFetchTests {
    @Test func localHostsAreThoseOfTheMacAndItsNetwork() {
        for host in ["localhost", "LOCALHOST.", "dev.localhost", "router", "printer.local", "127.0.0.1", "127.1", "2130706433", "0x7f000001",
                     "10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.1.1", "100.64.0.1", "100.127.255.255", "169.254.169.254", "0.0.0.0",
                     "::1", "[::1]", "::", "fc00::1", "fd12:3456::1", "fe80::1", "fe80::1%en0", "::ffff:192.168.1.1", "::ffff:7f00:1"] {
            #expect(SiteIcon.isLocal(host: host), "\(host)")
        }
        for host in ["example.com", "github.com", "172.32.0.1", "172.15.0.1", "100.128.0.1", "192.169.0.1", "8.8.8.8", "11.0.0.1",
                     "2606:4700::1111", "::ffff:8.8.8.8", "local.example.com", "localhost.example.com"] {
            #expect(!SiteIcon.isLocal(host: host), "\(host)")
        }
    }

    @Test func aPublicSiteFetchesOnlyPublicAddresses() {
        let origin = URL(string: "https://example.com/")!
        for url in ["https://cdn.example.net/i.png", "http://example.com/favicon.ico"] {
            #expect(SiteIcon.mayFetch(URL(string: url)!, for: origin), "\(url)")
        }
        for url in ["http://192.168.1.1/apply.cgi?x=1", "http://127.0.0.1:8080/", "http://localhost/", "http://[::1]/", "http://nas.local/",
                    "http://169.254.169.254/latest/meta-data/", "http://intranet/", "file:///etc/passwd", "ftp://example.com/i.png"] {
            #expect(!SiteIcon.mayFetch(URL(string: url)!, for: origin), "\(url)")
        }
    }

    @Test func aPublicNameThatResolvesIntoTheNetworkIsRefused() {
        let origin = URL(string: "https://example.com/")!
        #expect(SiteIcon.mayConnect(to: ["93.184.215.14", "2606:2800:21f:cb07:6820:80da:af6b:8b2c"], for: origin))
        #expect(SiteIcon.mayConnect(to: [], for: origin))
        for addresses in [["192.168.1.1"], ["93.184.215.14", "10.0.0.1"], ["127.0.0.1"], ["::1"], ["fe80::1%en0"], ["169.254.169.254"]] {
            #expect(!SiteIcon.mayConnect(to: addresses, for: origin), "\(addresses)")
        }
        #expect(SiteIcon.mayConnect(to: ["127.0.0.1", "::1"], for: URL(string: "http://localhost:3000/")!))
    }

    @Test func aLocalSiteMayFetchLocallyAndPublicly() {
        let origin = URL(string: "http://localhost:3000/")!
        for url in ["http://localhost:3000/favicon.ico", "http://127.0.0.1:5173/i.png", "https://cdn.example.net/i.png"] {
            #expect(SiteIcon.mayFetch(URL(string: url)!, for: origin), "\(url)")
        }
    }
}

/// Which formats a site's icon is read in: those favicons come in, not every format ImageIO parses.
struct SiteIconFormatTests {
    @Test func faviconFormatsAreRead() {
        for type in ["public.png", "public.jpeg", "com.compuserve.gif", "com.microsoft.ico", "org.webmproject.webp", "com.microsoft.bmp"] {
            #expect(SiteIcon.isIcon(imageType: type, data: Data()), "\(type)")
        }
        #expect(SiteIcon.isIcon(imageType: nil, data: Data("<svg/>".utf8)), "SVG text, which ImageIO doesn't type")
    }

    @Test func otherFormatsAreNot() {
        for type in ["com.adobe.pdf", "com.adobe.raw-image", "com.canon.cr2-raw-image", "com.adobe.photoshop-image", "org.nema.dicom",
                     "com.ilm.openexr-image", "public.tiff", "public.heic", "com.apple.icns", "com.apple.pict", "public.jpeg-xl"] {
            #expect(!SiteIcon.isIcon(imageType: type, data: Data()), "\(type)")
        }
        #expect(!SiteIcon.isIcon(imageType: "com.adobe.raw-image", data: Data("<svg/>".utf8)), "a typed file is never read as SVG")
        #expect(!SiteIcon.isIcon(imageType: nil, data: Data("%PDF-1.7".utf8)))
    }
}

/// Which bytes from a site are read as an SVG icon: SVG text, not a PDF or a web page.
struct SiteIconSVGTests {
    @Test func svgTextIsAnSVG() {
        for text in [#"<svg xmlns="http://www.w3.org/2000/svg"/>"#, "\u{FEFF}  \n<svg viewBox='0 0 1 1'></svg>",
                     #"<?xml version="1.0"?><!DOCTYPE svg><!-- logo --><svg xmlns="http://www.w3.org/2000/svg"/>"#] {
            #expect(SiteIcon.isSVG(Data(text.utf8)), "\(text)")
        }
    }

    @Test func otherBytesAreNot() {
        let late = "<?xml version=\"1.0\"?>" + String(repeating: " ", count: 5000) + "<svg/>"
        for text in ["%PDF-1.7\n", "<html><svg/></html>", "<?xml version=\"1.0\"?><rss/>", "<svgx/>", late, "", "   "] {
            #expect(!SiteIcon.isSVG(Data(text.utf8)), "\(text.prefix(30))")
        }
        #expect(!SiteIcon.isSVG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), "a PNG")
    }
}
