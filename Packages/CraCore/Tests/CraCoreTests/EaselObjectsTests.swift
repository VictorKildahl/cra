import CraCore
import Foundation
import Testing

/// Arc 1.172's easel objects beyond pictures, text and outlines: palette colours, layering, link
/// cards, captures that can show the live page, and undo (EaselObjects.swift, EaselHistory.swift).
struct EaselObjectsTests {
    @Test func shapesTakeArcsColoursFromThePalette() {
        #expect(Easel.defaultShade(.rectangle) == .lightGreen && Easel.defaultShade(.ellipse) == .red)
        #expect(Easel.defaultShade(.arrow(from: .init(0, 0), to: .init(1, 1))) == .lightBlue)
        #expect(Easel.defaultShade(.freehand([])) == .black && Easel.defaultShade(.image(file: "a.png")) == nil)
        // Arc 1.172.2 starts on Vibrant.
        #expect(Easel.hex(.red, palette: nil, dark: true) == "#F53714" && Easel.hex(.red, palette: .chill, dark: true) == "#D74807")
        #expect(Easel.hex(.lightGreen, palette: nil, dark: true) == "#34E895" && Easel.Palette.menu.map(\.title) == ["Vibrant", "Chill"])
        #expect(Easel.hex(.lightGreen, palette: .chill, dark: false) == "#D0D87F")
        // Black is the ink: white on a dark canvas, as Arc's colour assets have it.
        #expect(Easel.hex(.black, palette: .chill, dark: true) == "#FFFFFF" && Easel.hex(.white, palette: .chill, dark: true) == "#000000")
        #expect(Easel.isDisplayP3(.lightGreen) && Easel.isDisplayP3(.lightBlue) && !Easel.isDisplayP3(.red))
        #expect(Easel.Shade.allCases.count == 11 && Set(Easel.pickerRows.joined()) == Set(Easel.Shade.allCases))
    }

    /// Arc 1.172.2: a click with the rectangle or ellipse tool places a 200 pt shape centred there.
    @Test func aClickPlacesArcsShapeADragDrawsOne() {
        #expect(Easel.shape(.rectangle, from: .init(500, 500), to: .init(501, 502))?.frame == .init(x: 400, y: 400, width: 200, height: 200))
        #expect(Easel.shape(.ellipse, from: .init(300, 300), to: .init(300, 300))?.kind == .ellipse)
        #expect(Easel.shape(.rectangle, from: .init(0, 0), to: .init(50, 30))?.frame == .init(x: 0, y: 0, width: 50, height: 30))
        #expect(Easel.shape(.arrow, from: .init(0, 0), to: .init(1, 1)) == nil)
        #expect(Easel.isVideo("https://www.youtube.com/watch?v=x") && Easel.isVideo("https://youtu.be/x") && !Easel.isVideo("https://example.com"))
    }

    @Test func bringToFrontAndSendToBackRestack() {
        let a = Easel.Item(kind: .rectangle, frame: .init(x: 0, y: 0, width: 100, height: 100))
        let b = Easel.Item(kind: .ellipse, frame: .init(x: 50, y: 50, width: 100, height: 100))
        let c = Easel.Item(kind: .rectangle, frame: .init(x: 60, y: 60, width: 10, height: 10))
        var e = Easel(items: [a, b, c])
        e.bringToFront(a.id)
        #expect(e.items.map(\.id) == [b.id, c.id, a.id] && e.isFront(a.id))
        #expect(e.item(at: .init(65, 65))?.id == a.id)
        e.sendToBack(a.id)
        #expect(e.items.map(\.id) == [a.id, b.id, c.id] && e.isBack(a.id))
        e.sendToBack(UUID())
        #expect(e.items.map(\.id) == [a.id, b.id, c.id])
    }

    @Test func aCopyIsANewItemOffset() {
        let a = Easel.Item(kind: .arrow(from: .init(0, 0), to: .init(10, 10)), frame: .init(x: 0, y: 0, width: 10, height: 10))
        let c = Easel.copy(of: a)
        #expect(c.id != a.id && c.frame.x == 20 && c.kind == .arrow(from: .init(20, 20), to: .init(30, 30)))
    }

    /// Pasted items come from the pasteboard, which any app can write: their pictures must be plain
    /// names in the easel's folder, never a path out of it.
    @Test func pastedPicturesMustBePlainNames() {
        #expect(Easel.isPlainFileName("6B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F.png"))
        for bad in ["", "../../.ssh/id_rsa", "/etc/hosts", ".hidden", "a/b.png", "..", "x:y", String(repeating: "a", count: 200)] {
            #expect(!Easel.isPlainFileName(bad), "\(bad)")
        }
        let link = Easel.Item(kind: .link(.init(url: "https://e.org", image: "a.img", icon: "b.img")), frame: .init(x: 0, y: 0, width: 1, height: 1))
        #expect(Easel.files(of: link) == ["a.img", "b.img"] && Easel.files(of: Easel.Item(kind: .rectangle, frame: link.frame)).isEmpty)
    }

    @Test func onlyWebAddressesBecomeLinks() {
        #expect(Easel.webAddress(" https://example.com/a?b=1 \n") == "https://example.com/a?b=1")
        #expect(Easel.webAddress("http://x.org") == "http://x.org")
        #expect(Easel.webAddress("hello world") == nil && Easel.webAddress("file:///etc/hosts") == nil)
        #expect(Easel.webAddress("javascript:alert(1)") == nil && Easel.webAddress("https://") == nil)
        #expect(Easel.Link(url: "https://www.youtube.com/watch?v=1").host == "youtube.com")
    }

    @Test func aLiveCaptureShowsTheCapturedPartOfThePage() throws {
        let cap = Easel.Capture(url: "https://example.com", image: "c.png", viewport: .init(1200, 800), scroll: .init(0, 300),
                                area: .init(x: 100, y: 50, width: 400, height: 200))
        #expect(cap.canGoLive)
        // A card at twice the capture's size shows the page at 2x, the area on the card.
        let (page, zoom) = try #require(Easel.liveLayout(cap, in: .init(x: 0, y: 0, width: 800, height: 400)))
        #expect(zoom == 2 && page == .init(x: -200, y: -100, width: 2400, height: 1600))
        #expect(Easel.liveLayout(Easel.Capture(url: "https://example.com", image: "c.png"), in: .init(x: 0, y: 0, width: 1, height: 1)) == nil)
    }

    /// Cra 0.1.40 and older read `items` strictly: a kind they don't know would fail the whole
    /// easel. New kinds go in `cards`, and `z` puts both back in one stack.
    @Test func newKindsStayOutOfWhatOlderCraReads() throws {
        let rect = Easel.Item(kind: .rectangle, frame: .init(x: 0, y: 0, width: 10, height: 10))
        let link = Easel.Item(kind: .link(.init(url: "https://example.com", title: "Example")), frame: .init(x: 0, y: 0, width: 360, height: 104))
        let cap = Easel.Item(kind: .capture(.init(url: "https://example.com", image: "c.png", live: true)), frame: .init(x: 5, y: 5, width: 20, height: 20))
        let text = Easel.Item(kind: .text("Hi", size: 18), frame: .init(x: 0, y: 0, width: 10, height: 10))
        var e = Easel(title: "Board", items: [link, rect, cap, text])
        e.palette = .vibrant
        e.items[1].shade = .purple
        let data = try JSONEncoder().encode(e)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["items"] as? [[String: Any]])?.count == 2 && (json["cards"] as? [[String: Any]])?.count == 2)
        #expect(try JSONDecoder().decode(Easel.self, from: data) == e)

        struct OlderItem: Decodable {
            enum Kind: Decodable { case text(String, size: Double), ellipse, rectangle, arrow(from: Easel.Point, to: Easel.Point), freehand([Easel.Point]), image(file: String) }
            var id: UUID; var kind: Kind; var frame: Easel.Rect
        }
        struct OlderEasel: Decodable { var id: UUID; var title: String; var items: [OlderItem] }
        let older = try JSONDecoder().decode(OlderEasel.self, from: data)
        #expect(older.title == "Board" && older.items.map(\.id) == [rect.id, text.id])
    }

    @Test func aCardThisCraCantReadIsLeftOut() throws {
        let id = UUID()
        let file = #"{"id":"\#(id)","title":"T","items":[{"id":"\#(UUID())","kind":{"rectangle":{}},"frame":{"x":0,"y":0,"width":1,"height":1},"z":1}],"cards":[{"id":"\#(UUID())","kind":{"hologram":{}},"frame":{"x":0,"y":0,"width":1,"height":1},"z":0}],"palette":"neon"}"#
        let e = try JSONDecoder().decode(Easel.self, from: Data(file.utf8))
        #expect(e.items.count == 1 && e.items[0].kind == .rectangle && e.palette == nil)
    }

    @Test func undoAndRedoStepThroughWholeEasels() {
        var h = EaselHistory()
        var e = Easel()
        #expect(!h.canUndo && h.undo(e) == nil)
        h.record(e, "Draw")
        e.items.append(Easel.Item(kind: .rectangle, frame: .init(x: 0, y: 0, width: 10, height: 10)))
        h.record(e, "Move")
        let drawn = e
        e.items[0] = e.items[0].moved(by: .init(5, 5))
        #expect(h.undoName == "Move")
        let back = h.undo(e)!
        #expect(back == drawn && h.canRedo && h.redoName == "Move")
        #expect(h.redo(back) == e)
        // A new change after an undo drops what could be redone.
        _ = h.undo(e)
        h.record(drawn, "Delete")
        #expect(!h.canRedo)
        // The same easel recorded twice for the same change is one step.
        h.record(drawn, "Delete")
        #expect(h.undos.count == 2)
        for i in 0..<(EaselHistory.limit + 10) { h.record(Easel(title: "\(i)"), "Edit") }
        #expect(h.undos.count == EaselHistory.limit)
    }
}

/// Arc's MetaTagParser selectors for a link card's text and picture.
struct EaselLinkMetadataTests {
    @Test func openGraphFirstThenTheTitleTag() {
        let html = """
        <html><head><title> Fallback &amp; title </title>
        <meta property="og:title" content="The &quot;Real&quot; Title">
        <meta name='description' content='Plain description'>
        <meta property="og:image" content="/img/card.png">
        </head><body><meta property="og:title" content="Ignored"></body></html>
        """
        let m = EaselLinkMetadata.parse(html: html, url: "https://example.com/post/1")
        #expect(m.title == "The \"Real\" Title" && m.summary == "Plain description" && m.image == "https://example.com/img/card.png")
        #expect(m.icon == "https://example.com/favicon.ico")
        let icons = #"<link rel="icon" href="/i.png"><link rel="apple-touch-icon" href="https://cdn.x/t.png">"#
        #expect(EaselLinkMetadata.parse(html: icons, url: "https://e.org/a").icon == "https://cdn.x/t.png")
        #expect(EaselLinkMetadata.parse(html: #"<link href="/i.png" rel="icon">"#, url: "https://e.org/a").icon == "https://e.org/i.png")
    }

    @Test func aPageWithoutOpenGraphStillHasItsTitle() {
        let m = EaselLinkMetadata.parse(html: "<title>\n  Hello\n  world </title><meta content=\"x\" property=\"og:description\">",
                                        url: "https://e.org")
        #expect(m == EaselLinkMetadata(title: "Hello world", summary: "x", image: nil, icon: "https://e.org/favicon.ico"))
        #expect(EaselLinkMetadata.parse(html: #"<meta property="og:image" content="javascript:alert(1)">"#, url: "https://e.org").image == nil)
    }
}

/// Arc's alignment guides (easel.useSnapguides).
struct EaselSnapTests {
    @Test func edgesAndCentresSnapWithinAFewPoints() {
        let other = Easel.Rect(x: 100, y: 100, width: 200, height: 100)
        // Left edge 4 pt right of the other's left: it lines up, with a vertical guide down both.
        let (f, g) = Easel.snapped(.init(x: 104, y: 300, width: 50, height: 50), to: [other])
        #expect(f.x == 100 && f.y == 300)
        #expect(g == [Easel.Guide(axis: .vertical, position: 100, from: 100, to: 350)])
        // Centre on centre, both ways.
        let (c, cg) = Easel.snapped(.init(x: 173, y: 127, width: 50, height: 50), to: [other])
        #expect(c.x == 175 && c.y == 125 && cg.count == 2)
        // Too far: nothing moves.
        let far = Easel.Rect(x: 120, y: 400, width: 50, height: 50)
        #expect(Easel.snapped(far, to: [other]) == (far, []))
        #expect(Easel.snapped(far, to: []).guides.isEmpty)
    }

    @Test func theNearestEdgeWins() {
        let a = Easel.Rect(x: 0, y: 0, width: 100, height: 10), b = Easel.Rect(x: 103, y: 50, width: 10, height: 10)
        // Its right edge at 105 is 5 pt from a's right (100) and 2 pt from b's left (103): b wins.
        let (f, _) = Easel.snapped(.init(x: 55, y: 200, width: 50, height: 10), to: [a, b])
        #expect(f.x + f.width == 103)
    }
}

/// Arc's "Set as Easel thumbnail" (customOGImageID).
struct EaselThumbnailTests {
    @Test func onlyAPictureOrCaptureThatIsStillThereStandsForTheEasel() throws {
        let pic = Easel.Item(kind: .image(file: "a.png"), frame: .init(x: 0, y: 0, width: 10, height: 10))
        let box = Easel.Item(kind: .rectangle, frame: .init(x: 0, y: 0, width: 10, height: 10))
        var e = Easel(items: [pic, box])
        #expect(e.thumbnailItem == nil)
        e.thumbnail = pic.id
        #expect(e.thumbnailItem?.id == pic.id)
        #expect(try JSONDecoder().decode(Easel.self, from: JSONEncoder().encode(e)).thumbnail == pic.id)
        e.thumbnail = box.id
        #expect(e.thumbnailItem == nil && !Easel.canBeThumbnail(.rectangle))
        e.thumbnail = pic.id
        e.items.removeFirst()
        #expect(e.thumbnailItem == nil)
    }
}
