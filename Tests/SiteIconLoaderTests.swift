import AppKit

/// SiteIconLoader against a site on 127.0.0.1: a tab that never loaded gets its site's icon in the
/// background, and the engine's icon still wins.
@main
enum SiteIconLoaderTests {
    private static var checks = 0
    private static let orange = [255, 128, 0], blue = [0, 0, 255]

    /// Every site is 127.0.0.1 and the cache keeps icons on disk, so scripts/test-site-icons.sh runs each
    /// test in a process and data folder of its own: `--list` names them, an argument runs one.
    static let tests: [(String, @MainActor () async -> Void)] = [
        ("fetch", anUnopenedTabGetsItsSitesIconAndTheEnginesReplacesIt),
        ("race", anIconThatArrivesDuringTheFetchStays),
        ("svg", anSVGIconIsDrawnSmall),
        ("large", anIconTooLargeToDownloadIsSkipped),
        ("failed", aSiteThatFailsIsNotAskedAgain),
        ("incognito", anIncognitoSpaceAsksNothing),
        ("unreachable", aSiteThatCantBeReachedIsAskedOnce),
        ("deadline", aSiteThatHangsLetsGoAtTheDeadline),
        ("candidates", onlyThePagesBestIconsAreTried),
        ("redirect", aLocalSitesRedirectIsFollowed),
        ("bomb", anIconClaimingAHugeSizeIsSkipped),
        ("pdf", aPDFIsNoIcon),
        ("resolve", aNameIsJudgedByTheAddressesItResolvesTo),
    ]

    static func main() async {
        let arg = CommandLine.arguments.dropFirst().first
        if arg == "--list" { print(tests.map(\.0).joined(separator: " ")); return }
        guard let test = tests.first(where: { $0.0 == arg })?.1 else { print("FAIL: no test named \(arg ?? "")"); exit(1) }
        // The local site writes to connections the loader dropped.
        signal(SIGPIPE, SIG_IGN)
        // A fetch that never ends would hang the suite: fail it instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) { print("FAIL: \(arg ?? "") timed out"); exit(1) }
        await test()
        print("SiteIconLoader \(arg ?? ""): \(checks) checks passed")
    }

    private static func expect(_ ok: Bool, _ what: String) {
        checks += 1
        if !ok { print("FAIL: \(what)"); exit(1) }
    }

    /// A sidebar tab on `url` with no icon of its own yet.
    private static func tab(_ url: String, incognito: Bool = false) -> SiteIconQueue.Row {
        .init(url: url, iconKey: FaviconKey.key(for: url), incognito: incognito)
    }

    /// Asks for `url`'s icon and waits for the fetch to end.
    @MainActor private static func fetch(_ loader: SiteIconLoader, _ url: String, into cache: FaviconCache) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            loader.want(tab(url), into: cache) { done.resume() }
        }
    }

    @MainActor private static func anUnopenedTabGetsItsSitesIconAndTheEnginesReplacesIt() async {
        let site = await LocalSite(pages: [
            "/": .html(#"<html><head><link rel="icon" sizes="128x128" href="/static/orange.png"></head></html>"#),
            "/static/orange.png": .png(png(orange, side: 128)),
        ])
        let cache = FaviconCache(), loader = SiteIconLoader()
        let url = "http://127.0.0.1:\(site.port)/some/page"
        let key = FaviconKey.key(for: url)!
        expect(cache.image(forKey: key) == nil, "the tab starts with no icon")
        await fetch(loader, url, into: cache)
        let fetched = cache.image(forKey: key)
        expect(fetched.map(color) == orange, "the home page's declared icon is stored under the site's key: \(String(describing: fetched.map(color))) \(site.paths)")
        expect(fetched.map { max($0.size.width, $0.size.height) <= 64 } == true, "a fetched icon is at most 64 px")
        expect(site.paths == ["/", "/static/orange.png"], "the page and its icon, from the tab's own origin: \(site.paths)")
        expect(!site.heads.contains { $0.lowercased().contains("\ncookie:") }, "no cookies are sent")

        // The page loads: BrowserManager.didLoadFavicon stores the engine's icon under the site and the tab.
        let engine = png(blue, side: 32).flatMap(NSImage.init(data:))!
        let tabKey = FaviconKey.key(site: key, tabID: UUID())
        cache.store(engine, forKey: key)
        cache.store(engine, forKey: tabKey)
        loader.want(tab(url), into: cache)
        await nextTurn()
        expect(cache.image(forKey: tabKey) === engine && cache.image(forKey: key) === engine, "the engine's icon replaces the fetched one")
        expect(site.paths.count == 2, "a site is asked once a launch")
    }

    @MainActor private static func anIconThatArrivesDuringTheFetchStays() async {
        let site = await LocalSite(pages: ["/favicon.ico": .png(png(orange, side: 16))])
        let cache = FaviconCache(), loader = SiteIconLoader()
        let url = "http://127.0.0.1:\(site.port)/"
        let engine = png(blue, side: 16).flatMap(NSImage.init(data:))!
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            loader.want(tab(url), into: cache) { done.resume() }
            // The tab loads before the fetch starts.
            cache.store(engine, forKey: "127.0.0.1")
        }
        expect(site.paths.contains("/favicon.ico"), "the fetch ran")
        expect(cache.image(forKey: "127.0.0.1") === engine, "a fetch never replaces an icon stored meanwhile")
    }

    /// crash-zen-favicon-size: an SVG may declare any size, and drawing it at that size ran out of memory.
    @MainActor private static func anSVGIconIsDrawnSmall() async {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="100000"><rect width="100000" height="100000" fill="green"/></svg>"#
        let site = await LocalSite(pages: [
            "/": .html(#"<link rel="icon" type="image/svg+xml" href="/icon.svg">"#),
            "/icon.svg": .init(type: "image/svg+xml", body: Data(svg.utf8)),
        ])
        let cache = FaviconCache(), loader = SiteIconLoader()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        let icon = cache.image(forKey: "127.0.0.1")
        expect(icon != nil, "an SVG icon is stored")
        expect(icon.map { max($0.size.width, $0.size.height) <= 64 } == true, "an SVG is drawn at most 64 px: \(String(describing: icon?.size))")
    }

    @MainActor private static func anIconTooLargeToDownloadIsSkipped() async {
        var huge = png(orange, side: 16)!
        huge.append(Data(count: SiteIconLoader.iconLimit))
        let site = await LocalSite(pages: [
            "/": .html(#"<link rel="icon" sizes="512x512" href="/huge.png">"#),
            "/huge.png": .png(huge),
            "/favicon.ico": .png(png(blue, side: 16)),
        ])
        let cache = FaviconCache(), loader = SiteIconLoader()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        expect(cache.image(forKey: "127.0.0.1").map(color) == blue,
               "an icon past the download limit is skipped for the next")
    }

    @MainActor private static func aSiteThatFailsIsNotAskedAgain() async {
        let site = await LocalSite(pages: [:])
        let cache = FaviconCache(), loader = SiteIconLoader()
        let url = "http://127.0.0.1:\(site.port)/"
        await fetch(loader, url, into: cache)
        expect(cache.image(forKey: "127.0.0.1") == nil, "nothing is stored")
        let asked = site.paths.count
        loader.want(tab(url), into: cache)
        await nextTurn()
        expect(asked == 2 && site.paths.count == asked, "a failed site is not asked again this launch: \(site.paths)")
    }

    @MainActor private static func anIncognitoSpaceAsksNothing() async {
        let site = await LocalSite(pages: ["/favicon.ico": .png(png(orange, side: 16))])
        let cache = FaviconCache(), loader = SiteIconLoader()
        loader.want(tab("http://127.0.0.1:\(site.port)/", incognito: true), into: cache) { expect(false, "no fetch ends") }
        await nextTurn()
        expect(site.paths.isEmpty && cache.image(forKey: "127.0.0.1") == nil, "an incognito tab's site is not contacted")
    }

    @MainActor private static func aSiteThatCantBeReachedIsAskedOnce() async {
        let site = await LocalSite(pages: ["/": .init(type: "text/html", body: Data(), reply: .drop), "/favicon.ico": .png(png(orange, side: 16))])
        let cache = FaviconCache(), loader = SiteIconLoader()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        // URLSession itself retries a GET on a dropped connection.
        expect(!site.paths.contains("/favicon.ico"), "a site that drops the connection is not asked for /favicon.ico as well: \(site.paths)")
        expect(cache.image(forKey: "127.0.0.1") == nil, "nothing is stored")
    }

    @MainActor private static func aSiteThatHangsLetsGoAtTheDeadline() async {
        let site = await LocalSite(pages: ["/": .init(type: "text/html", body: Data(), reply: .hang), "/favicon.ico": .png(png(orange, side: 16))])
        let cache = FaviconCache(), loader = SiteIconLoader(deadline: .milliseconds(300))
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        expect(site.paths == ["/"] && cache.image(forKey: "127.0.0.1") == nil, "a site that never answers ends at its deadline: \(site.paths)")
    }

    @MainActor private static func onlyThePagesBestIconsAreTried() async {
        let links = (1...8).map { #"<link rel="icon" sizes="\#($0)x\#($0)" href="/i\#($0).png">"# }.joined()
        let site = await LocalSite(pages: ["/": .html(links)])
        let cache = FaviconCache(), loader = SiteIconLoader()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        expect(site.paths == ["/", "/i8.png", "/i7.png", "/i6.png", "/i5.png"], "the page and its 4 best icons, no more: \(site.paths)")
    }

    /// A local site's redirects within the Mac are followed (SiteIcon.mayFetch); CraCore's SiteIconFetchTests
    /// hold what a public site's may not reach.
    @MainActor private static func aLocalSitesRedirectIsFollowed() async {
        let site = await LocalSite(pages: [
            "/": .init(type: "text/html", body: Data(), reply: .redirect("/home/")),
            "/home/": .html(#"<link rel="icon" href="orange.png">"#),
            "/home/orange.png": .png(png(orange, side: 16)),
        ])
        let cache = FaviconCache(), loader = SiteIconLoader()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        expect(site.paths == ["/", "/home/", "/home/orange.png"], "the redirect and the icon it declares: \(site.paths)")
        expect(cache.image(forKey: "127.0.0.1").map(color) == orange, "the icon is stored")
    }

    /// Lets the main queue run what was queued on it (the loader's pump) and returns after.
    /// A name is checked by where it resolves as well as by how it reads (SiteIcon.mayConnect): "localhost"
    /// stands in for a public-looking name that points into the Mac or its network.
    @MainActor private static func aNameIsJudgedByTheAddressesItResolvesTo() async {
        expect(SiteIconLoader.addresses(of: "127.0.0.1") == ["127.0.0.1"], "a numeric address is itself")
        let here = SiteIconLoader.addresses(of: "localhost")
        expect(!here.isEmpty && here.allSatisfy { SiteIcon.isLocal(host: $0) }, "localhost resolves to the Mac: \(here)")
        let local = URL(string: "http://localhost/favicon.ico")!
        expect(!SiteIconLoader.mayConnect(local, for: URL(string: "https://example.com/")!), "a public site never connects to the Mac")
        expect(SiteIconLoader.mayConnect(local, for: URL(string: "http://127.0.0.1:3000/")!), "a local site may")
    }

    @MainActor private static func nextTurn() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { DispatchQueue.main.async { c.resume() } } }
    }

    /// A site's bytes are never decoded at the size they claim: a few KB claiming 20000 px took a GB and seconds.
    @MainActor private static func anIconClaimingAHugeSizeIsSkipped() async {
        let site = await LocalSite(pages: [
            "/": .html(#"<link rel="icon" sizes="512x512" href="/huge.png">"#),
            "/huge.png": .png(hugePNG(side: 20000)),
            "/favicon.ico": .png(png(blue, side: 16)),
        ])
        let cache = FaviconCache(), loader = SiteIconLoader()
        let start = Date()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        expect(Date().timeIntervalSince(start) < 1, "the huge icon is refused at once, not decoded: \(Date().timeIntervalSince(start)) s")
        expect(site.paths == ["/", "/huge.png", "/favicon.ico"] && cache.image(forKey: "127.0.0.1").map(color) == blue,
               "the next icon is stored instead: \(site.paths)")
    }

    /// Only bitmaps and SVG text are read: AppKit and ImageIO would also draw a site's PDF.
    @MainActor private static func aPDFIsNoIcon() async {
        let pdf = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 16, height: 16)
        let ctx = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 1, green: 128 / 255, blue: 0, alpha: 1))
        ctx.fill(box)
        ctx.endPDFPage()
        ctx.closePDF()
        let site = await LocalSite(pages: [
            "/": .html(#"<link rel="icon" sizes="64x64" href="/icon.pdf">"#),
            "/icon.pdf": .init(type: "application/pdf", body: pdf as Data),
            "/favicon.ico": .png(png(blue, side: 16)),
        ])
        // FaviconCache.png happens to refuse this PDF as well (no pixel size); the loader doesn't rely on it.
        let svg = Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)
        let bitmap = NSBitmapImageRep(data: png(blue, side: 16)!)!
        func encoded(_ type: NSBitmapImageRep.FileType) -> Data { bitmap.representation(using: type, properties: [:])! }
        // An .ico holding one PNG: its header, one directory entry (16 px, 32 bpp, size, offset 22), the PNG.
        let inner = png(blue, side: 16)!
        let ico = Data([0, 0, 1, 0, 1, 0, 16, 16, 0, 0, 1, 0, 32, 0]) + withUnsafeBytes(of: UInt32(inner.count).littleEndian) { Data($0) }
            + withUnsafeBytes(of: UInt32(22).littleEndian) { Data($0) } + inner
        for (name, data) in [("PNG", encoded(.png)), ("JPEG", encoded(.jpeg)), ("GIF", encoded(.gif)), ("BMP", encoded(.bmp)), ("ICO", ico), ("SVG", svg)] {
            expect(SiteIconLoader.isIcon(data), "\(name) is read as an icon, as ImageIO types it")
        }
        expect(!SiteIconLoader.isIcon(pdf as Data) && !SiteIconLoader.isIcon(encoded(.tiff)), "a PDF or a TIFF is no icon")
        expect((CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).contains("org.webmproject.webp"), "WebP's identifier is ImageIO's")
        let cache = FaviconCache(), loader = SiteIconLoader()
        await fetch(loader, "http://127.0.0.1:\(site.port)/", into: cache)
        expect(site.paths == ["/", "/icon.pdf", "/favicon.ico"] && cache.image(forKey: "127.0.0.1").map(color) == blue,
               "the PDF is skipped for the next icon: \(site.paths) \(String(describing: cache.image(forKey: "127.0.0.1").map(color)))")
    }

    /// A black 1-bit PNG `side` px square, a few KB of zlib (as StoreTests' iconFilesAreDecodedSmall builds it).
    private static func hugePNG(side: Int) -> Data {
        func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
        func crc32(_ d: Data) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for byte in d {
                c ^= UInt32(byte)
                for _ in 0..<8 { c = c & 1 == 1 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
            }
            return ~c
        }
        func chunk(_ type: String, _ body: Data) -> Data { let t = Data(type.utf8) + body; return be32(UInt32(body.count)) + t + be32(crc32(t)) }
        let raw = side * (1 + (side + 7) / 8)  // every row: filter byte 0, then zero bits
        let deflated = ((try? (Data(count: raw) as NSData).compressed(using: .zlib)) as Data?) ?? Data()
        // zlib wraps the deflate stream: a header, and an Adler-32 that for zeros is (n mod 65521) << 16 | 1.
        let zlib = Data([0x78, 0x01]) + deflated + be32(UInt32(raw % 65521) << 16 | 1)
        let header = be32(UInt32(side)) + be32(UInt32(side)) + Data([1, 0, 0, 0, 0])
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + chunk("IHDR", header) + chunk("IDAT", zlib) + chunk("IEND", Data())
    }

    /// A square PNG of one colour, given as 0...255 components.
    private static func png(_ rgb: [Int], side: Int) -> Data? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(deviceRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255, blue: CGFloat(rgb[2]) / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// The colour of an image's middle, as 0...255 components.
    private static func color(_ image: NSImage) -> [Int] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return pixel.prefix(3).map(Int.init)
    }
}

/// An HTTP/1.1 site on 127.0.0.1 that serves `pages` by path, 404 otherwise, and records each request.
final class LocalSite: @unchecked Sendable {
    struct Page {
        /// What the site does once it has read the request: answers, redirects to a path, closes the
        /// connection, or keeps it open.
        enum Reply: Equatable { case answer, redirect(String), drop, hang }
        var type: String
        var body: Data
        var reply = Reply.answer
        static func html(_ s: String) -> Page { Page(type: "text/html", body: Data(s.utf8)) }
        static func png(_ d: Data?) -> Page { Page(type: "image/png", body: d ?? Data()) }
    }

    private let pages: [String: Page]
    private let lock = NSLock()
    private var requests: [(path: String, head: String)] = []
    let port: UInt16

    var paths: [String] { lock.withLock { requests.map(\.path) } }
    var heads: [String] { lock.withLock { requests.map(\.head) } }

    init(pages: [String: Page]) async {
        self.pages = pages
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) == 0 && listen(fd, 16) == 0 && getsockname(fd, $0, &size) == 0 }
        }
        guard bound else { print("FAIL: the local site did not start: errno \(errno)"); exit(1) }
        port = UInt16(bigEndian: addr.sin_port)
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                guard c >= 0 else { continue }
                serve(c)
            }
        }
    }

    private func serve(_ c: Int32) {
        defer { close(c) }
        var got = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while got.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = read(c, &buffer, buffer.count)
            guard n > 0 else { return }
            got.append(contentsOf: buffer[..<n])
        }
        let head = String(decoding: got, as: UTF8.self)
        let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        lock.withLock { requests.append((path, head)) }
        let page = pages[path]
        if page?.reply == .drop { return }
        if page?.reply == .hang {
            while read(c, &buffer, buffer.count) > 0 {}
            return
        }
        var status = page == nil ? "404 Not Found" : "200 OK"
        if case .redirect(let to)? = page?.reply { status = "302 Found\r\nLocation: \(to)" }
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(page?.type ?? "text/plain")\r\nContent-Length: \(page?.body.count ?? 0)\r\nConnection: close\r\n\r\n".utf8)
        out.append(page?.body ?? Data())
        out.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(c, raw.baseAddress! + sent, raw.count - sent)
                guard n > 0 else { return }
                sent += n
            }
        }
    }
}
