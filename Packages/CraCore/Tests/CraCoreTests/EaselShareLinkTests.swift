import CraCore
import Foundation
import Testing

/// Share Easel…: the easel travels in the link, after the #, so crabrowser.app stores nothing.
/// These pin what goes in, how pictures shrink to fit, what a hand-made link can't do, and the
/// version-1 format links already sent rely on.
struct EaselShareLinkTests {
    /// JPEG and PNG as their first bytes say, padded to `size`.
    private func jpeg(_ size: Int = 64, fill: UInt8 = 1) -> Data { Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: fill, count: max(0, size - 4))) }
    private func png(_ size: Int = 64) -> Data { Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 2, count: max(0, size - 8))) }

    private func easel() -> Easel {
        var e = Easel(title: "Trip ideas")
        e.titleStyle = .serif
        e.titleSize = 40
        e.palette = .chill
        var text = Easel.Item(kind: .text("Copenhagen\nin May", size: 24), frame: .init(x: 120, y: 160, width: 300, height: 60))
        text.style = .mono
        text.fixedWidth = true
        text.shade = .purple
        var rect = Easel.Item(kind: .rectangle, frame: .init(x: 10.04, y: 20, width: 200, height: 100))
        rect.shade = .lightGreen
        let ellipse = Easel.Item(kind: .ellipse, frame: .init(x: 0, y: 0, width: 50, height: 50), color: "#ff0000")
        let arrow = Easel.Item(kind: .arrow(from: .init(1, 2), to: .init(30, 40)), frame: .init(x: 1, y: 2, width: 29, height: 38))
        let stroke = try! #require(Easel.freehand([.init(5, 5), .init(6, 7.25), .init(9, 9)]))
        var picture = Easel.Item(kind: .image(file: "a.png"), frame: .init(x: 400, y: 400, width: 320, height: 200))
        picture.altText = "The harbour"
        let link = Easel.Item(kind: .link(.init(url: "https://visit.example/cph", title: "Visit", summary: "A guide", image: "og.jpg", icon: "icon.png")),
                              frame: .init(x: 0, y: 700, width: 459, height: 324))
        let capture = Easel.Item(kind: .capture(.init(url: "https://map.example/", title: "Map", image: "cap.png",
                                                      viewport: .init(1280, 800), scroll: .init(0, 300), area: .init(x: 0, y: 0, width: 400, height: 300), live: true)),
                                 frame: .init(x: 600, y: 700, width: 400, height: 300))
        e.items = [text, rect, ellipse, arrow, stroke, picture, link, capture]
        return e
    }

    /// Pictures as the app encodes them: the same bytes for one file at one size.
    private func pictures(_ r: EaselShareLink.PictureRequest) -> Data? {
        r.isIcon ? png() : jpeg(r.side / 10, fill: UInt8(r.file.count))
    }

    @Test func sharesEveryKindAndReadsItBackAsANewEasel() throws {
        let original = easel()
        let shared = try #require(EaselShareLink.link(for: original, picture: pictures))
        #expect(shared.fit == .full)
        #expect(shared.link.hasPrefix("https://crabrowser.app/easel#"))
        // Nothing readable before the #: the server sees only /easel.
        #expect(!shared.link.contains("?"))
        let back = try #require(EaselShareLink.easel(from: shared.link))
        let e = back.easel
        #expect(e.id != original.id)
        #expect(e.title == "Trip ideas" && e.titleStyle == .serif && e.titleSize == 40 && e.palette == .chill)
        #expect(e.items.count == 8)
        #expect(Set(e.items.map(\.id)).isDisjoint(with: original.items.map(\.id)))

        guard case .text(let s, let size) = e.items[0].kind else { Issue.record("not text"); return }
        #expect(s == "Copenhagen\nin May" && size == 24)
        #expect(e.items[0].style == .mono && e.items[0].fixedWidth == true && e.items[0].shade == .purple)
        #expect(e.items[1].kind == .rectangle && e.items[1].shade == .lightGreen)
        // Points go to a tenth.
        #expect(e.items[1].frame == .init(x: 10, y: 20, width: 200, height: 100))
        #expect(e.items[2].kind == .ellipse && e.items[2].color == "#FF0000")
        #expect(e.items[3].kind == .arrow(from: .init(1, 2), to: .init(30, 40)))
        #expect(e.items[4].kind == .freehand([.init(5, 5), .init(6, 7.3), .init(9, 9)]))

        guard case .image(let file) = e.items[5].kind else { Issue.record("not a picture"); return }
        #expect(file.hasSuffix(".jpg") && file != "a.png")
        #expect(back.pictures[file] == jpeg(128, fill: 5))
        #expect(e.items[5].altText == "The harbour")

        guard case .link(let l) = e.items[6].kind else { Issue.record("not a link"); return }
        #expect(l.url == "https://visit.example/cph" && l.title == "Visit" && l.summary == "A guide")
        #expect(back.pictures[try #require(l.image)] == jpeg(128, fill: 6))
        #expect(back.pictures[try #require(l.icon)] == png())
        #expect(l.icon?.hasSuffix(".png") == true)

        // A capture keeps its picture and its page; where on the page it was doesn't travel.
        guard case .capture(let c) = e.items[7].kind else { Issue.record("not a capture"); return }
        #expect(c.url == "https://map.example/" && c.title == "Map")
        #expect(c.viewport == nil && c.area == nil && c.live == nil)
        #expect(back.pictures[c.image] == jpeg(128, fill: 7))
        #expect(back.pictures.count == 4)
    }

    @Test func picturesShrinkUntilTheLinkFitsThenGo() throws {
        let original = easel()
        // Incompressible pictures, 300 bytes per pixel of side: 1280 doesn't fit, 800 does.
        func noisy(_ r: EaselShareLink.PictureRequest) -> Data? {
            var g = SystemRandomNumberGenerator()
            return Data([0xFF, 0xD8, 0xFF] + (0..<(r.side * 100)).map { _ in UInt8.random(in: 0...255, using: &g) })
        }
        let shrunk = try #require(EaselShareLink.link(for: original, picture: noisy))
        #expect(shrunk.fit == .shrunk)
        #expect(shrunk.link.count <= EaselShareLink.linkLimit)
        let back = try #require(EaselShareLink.easel(from: shrunk.link))
        #expect(back.pictures.values.allSatisfy { $0.count == 800 * 100 + 3 || $0.count == EaselShareLink.iconSide * 100 + 3 })

        // Too big at every step: the pictures go, the rest stays; the capture is its page's link card.
        let dropped = try #require(EaselShareLink.link(for: original) { Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: 3)) + noisyBytes($0.side * 1_300) })
        #expect(dropped.fit == .dropped)
        let bare = try #require(EaselShareLink.easel(from: dropped.link))
        #expect(bare.pictures.isEmpty)
        #expect(bare.easel.items.count == 7)
        guard case .link(let l) = bare.easel.items[5].kind, case .link(let c) = bare.easel.items[6].kind else { Issue.record("not links"); return }
        #expect(l.image == nil && l.icon == nil && l.title == "Visit")
        #expect(c.url == "https://map.example/" && c.title == "Map")
    }

    private func noisyBytes(_ n: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    @Test func anEmptyEaselHasNoLink() {
        #expect(EaselShareLink.link(for: Easel(), picture: pictures) == nil)
        // Only pictures, and none could be read: nothing to share.
        var e = Easel()
        e.items = [Easel.Item(kind: .image(file: "gone.png"), frame: .init(x: 0, y: 0, width: 10, height: 10))]
        #expect(EaselShareLink.link(for: e) { _ in nil } == nil)
    }

    @Test func openInCraCarriesTheSameEasel() throws {
        let shared = try #require(EaselShareLink.link(for: easel(), picture: pictures))
        let install = try #require(EaselShareLink.installLink(for: shared.link))
        #expect(install.hasPrefix("cra-easel:"))
        #expect(EaselShareLink.isInstallLink(install) && EaselShareLink.isInstallLink("CRA-EASEL:abc"))
        #expect(!EaselShareLink.isInstallLink(shared.link))
        let a = try #require(EaselShareLink.easel(from: install)), b = try #require(EaselShareLink.easel(from: "cra-easel://" + install.dropFirst(10)))
        #expect(a.easel.items.map(\.kind).count == 8 && b.easel.title == a.easel.title)
        #expect(EaselShareLink.installLink(for: "https://crabrowser.app/folder#abc") == nil)
    }

    // MARK: Version 1, as links already sent hold it

    /// The easel behind `versionOneLink`: a text, a shape, a picture (a 4-byte JPEG) and a link card.
    static func versionOneEasel() -> (Easel, (EaselShareLink.PictureRequest) -> Data?) {
        var e = Easel(title: "Board")
        e.palette = .chill
        var shape = Easel.Item(kind: .ellipse, frame: .init(x: 10, y: 20, width: 30, height: 40))
        shape.shade = .purple
        e.items = [Easel.Item(kind: .text("Hello", size: 24), frame: .init(x: 0, y: 0, width: 80, height: 30)), shape,
                   Easel.Item(kind: .image(file: "p.jpg"), frame: .init(x: 50, y: 50, width: 64, height: 48)),
                   Easel.Item(kind: .link(.init(url: "https://example.com/a", title: "Example")), frame: .init(x: 0, y: 100, width: 459, height: 324))]
        return (e, { _ in Data([0xFF, 0xD8, 0xFF, 0xD9]) })
    }

    /// The website's src/lib/easel-link.test.ts reads this same string (cra-website): if either side
    /// fails, links people already sent stop opening.
    static let versionOneLink = "https://crabrowser.app/easel#Nc7BCsIwEATQf5nzYrY1iga8CIJXz9JDqZFGUxvaVIrSf3ejFkKYXV6GvOFgzm9c5WZi2jAtuSDcYRDtGEHoJR6t963kF0yuJ_r5jClPnPT8QpQLvU2PahnD0AVvMfsVk5y1Jr35--CqOHTJNzA8O6aMpXS1pWWu_9K7x11YlN_iMJZN6iUMMtUxht4oZX_bRdU2qsRUfDvPUNubyk-7HWQRhFe18z41Sd63ZXeR_ITJpg8"

    @Test func versionOneLinkIsPinned() throws {
        let (easel, pictures) = Self.versionOneEasel()
        let made = try #require(EaselShareLink.link(for: easel, picture: pictures))
        #expect(made.link == Self.versionOneLink)
        let back = try #require(EaselShareLink.easel(from: Self.versionOneLink))
        #expect(back.easel.title == "Board" && back.easel.palette == .chill && back.easel.items.count == 4)
        #expect(back.easel.items[1].shade == .purple && back.pictures.values.first == Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    private func pack(_ json: String) -> String {
        let deflated = try! (Data(json.utf8) as NSData).compressed(using: .zlib) as Data
        return "https://crabrowser.app/easel#" + deflated.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    @Test func readsAVersion1LinkWrittenByHand() throws {
        let pic = jpeg(16).base64EncodedString()
        let back = try #require(EaselShareLink.easel(from: pack("""
        {"v":1,"t":"Board","p":"vibrant","tz":30,"i":[
         {"k":"text","f":[0,0,100,20],"s":"Hi","z":20,"st":"wide","c":"#00ff00"},
         {"k":"rect","f":[1,2,3,4],"sh":"red"},
         {"k":"draw","f":[0,0,1,1],"pts":[0,0,1,1]},
         {"k":"picture","f":[0,0,8,8],"m":0,"alt":"pic"},
         {"k":"link","f":[0,0,459,324],"u":"https://a.example/","ti":"A","m":0},
         {"k":"capture","f":[0,0,8,8],"u":"https://b.example/","m":0}],
         "m":["\(pic)"]}
        """)))
        #expect(back.easel.title == "Board" && back.easel.palette == .vibrant && back.easel.titleSize == 30)
        #expect(back.easel.items.count == 6)
        #expect(back.easel.items[0].style == .wide && back.easel.items[0].color == "#00FF00")
        #expect(back.easel.items[1].shade == .red)
        // One picture used three times is one file.
        #expect(back.pictures.count == 1 && back.pictures.values.first == jpeg(16))
    }

    @Test func aHandMadeLinkCantSneakAnythingIn() throws {
        let pic = jpeg(16).base64EncodedString()
        let gif = Data("GIF89a......".utf8).base64EncodedString()
        let back = try #require(EaselShareLink.easel(from: pack("""
        {"v":1,"t":"   ","i":[
         {"k":"link","f":[0,0,1,1],"u":"javascript:alert(1)"},
         {"k":"link","f":[0,0,1,1],"u":"file:///etc/passwd"},
         {"k":"capture","f":[0,0,1,1],"u":"cra://settings","m":0},
         {"k":"picture","f":[0,0,1,1],"m":7},
         {"k":"picture","f":[0,0,1,1],"m":1},
         {"k":"text","f":[1e300,0,1,1],"s":"far","z":12},
         {"k":"text","f":[0,0,-5,1],"s":"negative","z":12},
         {"k":"text","f":[0,0,1,1],"s":"huge","z":9000},
         {"k":"arrow","f":[0,0,1,1],"a":[1,2,3]},
         {"k":"draw","f":[0,0,1,1],"pts":[1,2,3]},
         {"k":"script","f":[0,0,1,1]},
         {"k":"rect","f":[0,0,1,1],"c":"red; background:url(x)","sh":"neon"}],
         "m":["\(pic)","\(gif)"]}
        """)))
        #expect(back.easel.title == "Untitled Easel")
        #expect(back.easel.items.count == 2)
        // A capture from a page that isn't on the web is just its picture.
        guard case .image(let f) = back.easel.items[0].kind else { Issue.record("not a picture"); return }
        #expect(back.pictures[f] == jpeg(16))
        #expect(back.easel.items[1].kind == .rectangle && back.easel.items[1].color == nil && back.easel.items[1].shade == nil)

        #expect(EaselShareLink.easel(from: pack(#"{"v":2,"t":"Later","i":[{"k":"rect","f":[0,0,1,1]}]}"#)) == nil)
        #expect(EaselShareLink.easel(from: pack(#"{"v":1,"t":"Empty","i":[]}"#)) == nil)
        #expect(EaselShareLink.easel(from: "https://crabrowser.app/easel#not-a-link") == nil)
        #expect(EaselShareLink.easel(from: "https://crabrowser.app/folder#abc") == nil)
    }
}
