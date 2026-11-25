import Foundation

/// Share Easel… (byearc's "Easels: a shareable canvas"). Arc kept a shared easel on arc.net and
/// copied its link ("Copied Easel URL"); anyone could view it in any browser and only Arc could edit
/// it. Cra has no server, so the easel travels in the link itself, as a shared folder does
/// (`FolderShareLink`): its items as JSON with its pictures in it, deflated, base64url'd, after the `#`
/// of `crabrowser.app/easel#…`. Browsers never send the part after `#` to a server, so the site only
/// serves a static page that draws the easel in the reader's browser (cra-website `src/app/easel`),
/// and nothing about the easel is stored anywhere. The page's Open in Cra button is the same payload
/// after `cra-easel:`, which adds a copy to the reader's Cra after asking.
///
/// Pictures make a link long, so they go in shrunk: each step makes them smaller until the link
/// fits `linkLimit`, and when even the smallest doesn't fit they are left out (a capture keeps its
/// page as a link card, a link card its words). Nothing else is ever dropped.
///
/// The format is a promise: links people have already sent must keep opening. A change adds a new
/// `v`, it never changes what version 1 means.
///
///     {"v":1,"t":"Trip","i":[{"k":"text","f":[120,160,300,40],"s":"Hi","z":20},
///                            {"k":"picture","f":[…],"m":0}],"m":["<base64 JPEG>"]}
public enum EaselShareLink {
    public static let prefix = Sharing.base + "/easel#"
    /// What Open in Cra opens: macOS hands it to Cra, which asks before adding anything.
    public static let installScheme = "cra-easel"
    public static let version = 1
    /// The longest link Share Easel… makes, in characters. Browsers take far longer addresses
    /// (Chromium 2 MB), but chat apps and mail cut long ones.
    public static let linkLimit = 400_000
    /// The longest side, in pixels, pictures are shrunk to, one step after another.
    public static let pictureSteps = [1280, 800, 512, 320]
    /// A site icon is small whatever the step.
    public static let iconSide = 64
    /// What a hand-made link can make Cra or the site unpack.
    public static let maxJSONBytes = 8_000_000
    public static let maxItems = 2_000
    public static let maxPoints = 5_000
    public static let maxTextLength = 20_000
    public static let titleLimit = 200
    /// A coordinate this far off the canvas is a broken link, not an easel.
    static let maxCoordinate = 1_000_000.0

    /// How the pictures went in.
    public enum PictureFit: Equatable, Sendable {
        /// At the largest step (or there were none).
        case full
        /// Smaller than the largest step, to fit the link.
        case shrunk
        /// Left out: even the smallest step was too long.
        case dropped
    }

    /// What `picture` is asked for: the file next to the easel, and how big.
    public struct PictureRequest: Hashable, Sendable {
        public var file: String
        /// The longest side in pixels.
        public var side: Int
        /// A site icon: kept as PNG, so its transparency stays.
        public var isIcon: Bool
    }

    /// An easel read back from a link: what to add, with the pictures it names by file.
    public struct Received: Equatable, Sendable {
        public var easel: Easel
        /// The pictures by the file names the items use (fresh names, `<uuid>.jpg` or `.png`).
        public var pictures: [String: Data]
    }

    // MARK: Sharing

    /// The link for `easel`, or nil when it has nothing on it. `picture` encodes a picture next to
    /// the easel's file at the size asked (JPEG, or PNG for an icon); nil leaves that picture out.
    public static func link(for easel: Easel, picture: (PictureRequest) -> Data?) -> (link: String, fit: PictureFit)? {
        guard !easel.items.isEmpty else { return nil }
        for (n, side) in pictureSteps.enumerated() {
            guard let payload = payload(for: easel, side: side, picture: picture) else { return nil }
            let link = prefix + payload.text
            if link.count <= linkLimit { return (link, n == 0 || !payload.hadPictures ? .full : .shrunk) }
            if !payload.hadPictures { return nil }
        }
        guard let payload = payload(for: easel, side: nil, picture: picture), prefix.count + payload.text.count <= linkLimit else { return nil }
        return (prefix + payload.text, .dropped)
    }

    /// The Open in Cra address for a share link, or nil when it isn't one.
    public static func installLink(for link: String) -> String? {
        guard link.hasPrefix(prefix) else { return nil }
        return installScheme + ":" + link.dropFirst(prefix.count)
    }

    /// The payload for one step: `side` nil leaves every picture out.
    private static func payload(for easel: Easel, side: Int?, picture: (PictureRequest) -> Data?) -> (text: String, hadPictures: Bool)? {
        var pictures: [Data] = []
        var indexOf: [PictureRequest: Int] = [:]
        func add(_ file: String?, icon: Bool) -> Int? {
            guard let side, let file, Easel.isPlainFileName(file) else { return nil }
            let request = PictureRequest(file: file, side: icon ? iconSide : side, isIcon: icon)
            if let i = indexOf[request] { return i }
            guard let data = picture(request), !data.isEmpty else { return nil }
            pictures.append(data)
            indexOf[request] = pictures.count - 1
            return pictures.count - 1
        }
        var hadPictures = false
        let items: [WireItem] = easel.items.compactMap { item in
            var w = WireItem(k: "", f: item.frame.wire)
            w.c = item.color.flatMap(hexColor)
            w.sh = item.shade?.rawValue
            w.alt = item.altText.flatMap { clip($0, limit: 1_000) }
            switch item.kind {
            case .text(let s, let size):
                (w.k, w.s, w.z, w.st, w.fw) = ("text", String(s.prefix(maxTextLength)), round1(size), item.style?.rawValue, item.fixedWidth == true ? true : nil)
            case .rectangle: w.k = "rect"
            case .ellipse: w.k = "ellipse"
            case .arrow(let a, let b): (w.k, w.a) = ("arrow", [a.x, a.y, b.x, b.y].map(round1))
            case .freehand(let pts): (w.k, w.pts) = ("draw", pts.prefix(maxPoints).flatMap { [round1($0.x), round1($0.y)] })
            case .image(let file):
                hadPictures = true
                guard let m = add(file, icon: false) else { return nil }
                (w.k, w.m) = ("picture", m)
            case .link(let l):
                guard let url = webURL(l.url) else { return nil }
                if l.image != nil || l.icon != nil { hadPictures = true }
                (w.k, w.u, w.ti, w.su) = ("link", url, l.title.flatMap { clip($0) }, l.summary.flatMap { clip($0, limit: 1_000) })
                (w.m, w.ic) = (add(l.image, icon: false), add(l.icon, icon: true))
            case .capture(let c):
                hadPictures = true
                let url = webURL(c.url)
                if let m = add(c.image, icon: false) {
                    (w.k, w.m, w.u, w.ti) = ("capture", m, url, c.title.flatMap { clip($0) })
                } else if let url {
                    // Without its picture a capture is still the page it came from.
                    (w.k, w.u, w.ti) = ("link", url, c.title.flatMap { clip($0) })
                } else { return nil }
            }
            return w
        }
        guard !items.isEmpty else { return nil }
        let wire = Wire(v: version, t: clip(easel.title) ?? "Untitled Easel", ts: easel.titleStyle?.rawValue,
                        tz: easel.titleSize.map(round1), p: easel.palette?.rawValue, i: items,
                        m: pictures.isEmpty ? nil : pictures.map { $0.base64EncodedString() })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = try? encoder.encode(wire), let deflated = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        return (FolderShareLink.base64URL(deflated), hadPictures)
    }

    // MARK: Receiving

    /// Whether `url` is an easel to add (`cra-easel:…`). Then it is dealt with by Cra and must not load or open.
    public static func isInstallLink(_ url: String) -> Bool {
        url.lowercased().hasPrefix(installScheme + ":")
    }

    /// Reads a share link or a `cra-easel:` address back as a new easel: new ids, every field
    /// checked (anyone can write a link by hand), pictures by new file names. nil for anything
    /// that isn't a version-1 easel with something on it.
    public static func easel(from link: String) -> Received? {
        var payload: Substring
        if link.hasPrefix(prefix) {
            payload = link.dropFirst(prefix.count)
        } else if isInstallLink(link) {
            payload = link.dropFirst(installScheme.count + 1)
            while payload.hasPrefix("/") { payload = payload.dropFirst() }
        } else { return nil }
        guard let data = FolderShareLink.data(base64URL: String(payload)),
              let json = try? (data as NSData).decompressed(using: .zlib) as Data, json.count <= maxJSONBytes,
              let wire = try? JSONDecoder().decode(Wire.self, from: json), wire.v == version
        else { return nil }
        let blobs = (wire.m ?? []).map { Data(base64Encoded: $0) }
        var files: [Int: String] = [:]
        var pictures: [String: Data] = [:]
        func file(_ index: Int?) -> String? {
            guard let index, blobs.indices.contains(index), let data = blobs[index], let ext = pictureExtension(data) else { return nil }
            if let name = files[index] { return name }
            let name = UUID().uuidString + "." + ext
            files[index] = name
            pictures[name] = data
            return name
        }
        var easel = Easel(title: wire.t.flatMap { clip($0) } ?? "Untitled Easel")
        easel.titleStyle = wire.ts.flatMap(Easel.FontStyle.init(rawValue:))
        easel.titleSize = wire.tz.flatMap { $0.isFinite && $0 >= 6 && $0 <= 400 ? $0 : nil }
        easel.palette = wire.p.flatMap(Easel.Palette.init(rawValue:))
        easel.items = (wire.i ?? []).prefix(maxItems).compactMap { w -> Easel.Item? in
            guard let frame = rect(w.f) else { return nil }
            let kind: Easel.Item.Kind
            switch w.k {
            case "text":
                guard let s = w.s, let size = w.z, size.isFinite, size >= 4, size <= 400 else { return nil }
                kind = .text(String(s.prefix(maxTextLength)), size: size)
            case "rect": kind = .rectangle
            case "ellipse": kind = .ellipse
            case "arrow":
                guard let a = w.a, a.count == 4, a.allSatisfy(isCoordinate) else { return nil }
                kind = .arrow(from: .init(a[0], a[1]), to: .init(a[2], a[3]))
            case "draw":
                guard let p = w.pts, p.count >= 2, p.count % 2 == 0, p.count <= maxPoints * 2, p.allSatisfy(isCoordinate) else { return nil }
                kind = .freehand(stride(from: 0, to: p.count, by: 2).map { Easel.Point(p[$0], p[$0 + 1]) })
            case "picture":
                guard let name = file(w.m) else { return nil }
                kind = .image(file: name)
            case "link":
                guard let url = w.u.flatMap(webURL) else { return nil }
                kind = .link(Easel.Link(url: url, title: w.ti.flatMap { clip($0) }, summary: w.su.flatMap { clip($0, limit: 1_000) },
                                        image: file(w.m), icon: file(w.ic)))
            case "capture":
                guard let name = file(w.m) else { return nil }
                // The page it came from stays (its address and title); it can't go live without
                // knowing where on the page it was, which the link doesn't carry.
                if let url = w.u.flatMap(webURL) {
                    kind = .capture(Easel.Capture(url: url, title: w.ti.flatMap { clip($0) }, image: name))
                } else {
                    kind = .image(file: name)
                }
            default: return nil
            }
            var item = Easel.Item(kind: kind, frame: frame, color: w.c.flatMap(hexColor))
            item.shade = w.sh.flatMap(Easel.Shade.init(rawValue:))
            item.altText = w.alt.flatMap { clip($0, limit: 1_000) }
            if case .text = kind {
                item.style = w.st.flatMap(Easel.FontStyle.init(rawValue:))
                item.fixedWidth = w.fw == true ? true : nil
            }
            return item
        }
        guard !easel.items.isEmpty else { return nil }
        // Only the pictures an item kept.
        let used = Set(easel.items.flatMap(Easel.files))
        return Received(easel: easel, pictures: pictures.filter { used.contains($0.key) })
    }

    /// A picture's extension from its first bytes: JPEG and PNG, what Share Easel… writes.
    static func pictureExtension(_ data: Data) -> String? {
        let head = [UInt8](data.prefix(8))
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        return nil
    }

    // MARK: Wire

    /// Short keys: they are in every link.
    struct Wire: Codable {
        var v: Int?
        var t: String?
        var ts: String?
        var tz: Double?
        var p: String?
        var i: [WireItem]?
        var m: [String]?
    }

    struct WireItem: Codable {
        /// text, rect, ellipse, arrow, draw, picture, link, capture.
        var k: String
        /// x, y, width, height.
        var f: [Double]
        var c: String?
        var sh: String?
        var alt: String?
        var s: String?
        var z: Double?
        var st: String?
        var fw: Bool?
        var a: [Double]?
        var pts: [Double]?
        /// A picture, by its place in `m`.
        var m: Int?
        var ic: Int?
        var u: String?
        var ti: String?
        var su: String?
        init(k: String, f: [Double]) { (self.k, self.f) = (k, f) }
    }

    // MARK: Helpers

    static func rect(_ f: [Double]) -> Easel.Rect? {
        guard f.count == 4, f.allSatisfy(isCoordinate), f[2] >= 0, f[3] >= 0 else { return nil }
        return Easel.Rect(x: f[0], y: f[1], width: f[2], height: f[3])
    }

    static func isCoordinate(_ v: Double) -> Bool { v.isFinite && abs(v) <= maxCoordinate }

    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    static func hexColor(_ text: String) -> String? {
        let t = text.uppercased()
        guard t.count == 7, t.hasPrefix("#"), t.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return t
    }

    static func webURL(_ text: String) -> String? { FolderShareLink.webURL(text) }

    static func clip(_ text: String, limit: Int = titleLimit) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }
}

private extension Easel.Rect {
    var wire: [Double] { [x, y, width, height].map(EaselShareLink.round1) }
}
