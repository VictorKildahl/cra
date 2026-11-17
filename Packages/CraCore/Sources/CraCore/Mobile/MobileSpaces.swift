import Foundation

/// The Mac's sidebar as the iPhone shows it: Arc Search's Spaces view lists each Space's pinned
/// tabs and folders, then its Today tabs, one Space per page. Read from the `sidebar.json` the
/// Mac app syncs (`SettingsSync`); the phone opens things from it and does not write it.
public enum MobileSpaces {
    public struct Row: Equatable, Identifiable {
        public enum Kind: Equatable {
            case tab(url: String)
            /// A folder, open (its rows follow, one deeper) or shut.
            case folder(open: Bool)
            /// The line between the pinned part and Today.
            case todayHeader
        }

        public var id: UUID
        public var kind: Kind
        public var title: String
        /// How deep inside folders the row sits.
        public var depth: Int
    }

    public struct SpaceView: Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// The Space's emoji, or empty when it uses a symbol.
        public var emoji: String
        public var symbol: String?
        /// The theme's colours as "#RRGGBB".
        public var colors: [String]
        public var rows: [Row]
    }

    /// Every Space in the Mac's order, with its pinned tabs and folders, then its Today tabs, as
    /// Arc Search lists them: favorites left out, folders shut unless listed in `openFolders`
    /// (the sidebar keeps no open state; Arc Search opens one on a tap). Blank-window spaces are
    /// left out.
    public static func spaces(in document: SidebarDocument, openFolders: Set<UUID> = []) -> [SpaceView] {
        let items = Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byID = Dictionary(document.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = document.spaceOrder.compactMap { byID[$0] } + document.spaces.filter { !document.spaceOrder.contains($0.id) }

        func rows(under parent: UUID, depth: Int) -> [Row] {
            guard let container = items[parent] else { return [] }
            return container.children.flatMap { id -> [Row] in
                guard let item = items[id] else { return [] }
                switch item.data {
                case .tab(let tab):
                    let title = item.title ?? (tab.savedTitle.isEmpty ? (URL(string: tab.url)?.host ?? tab.url) : tab.savedTitle)
                    return [Row(id: id, kind: .tab(url: tab.url), title: title, depth: depth)]
                case .folder:
                    let open = openFolders.contains(id)
                    let folder = Row(id: id, kind: .folder(open: open), title: item.title ?? "Folder", depth: depth)
                    return [folder] + (open ? rows(under: id, depth: depth + 1) : [])
                case .split, .container:
                    // A split's tabs are its children: listed one by one.
                    return rows(under: id, depth: depth)
                }
            }
        }

        return ordered.filter { $0.standaloneWindowID == nil }.map { space in
            let pinned = rows(under: space.pinnedContainerID, depth: 0)
            let today = rows(under: space.todayContainerID, depth: 0)
            let header = today.isEmpty ? [] : [Row(id: space.todayContainerID, kind: .todayHeader, title: "Today", depth: 0)]
            return SpaceView(id: space.id, title: space.title, emoji: space.emoji, symbol: space.symbol,
                             colors: space.theme.colors, rows: pinned + header + today)
        }
    }

    /// Reads a synced `sidebar.json`, with the Mac's dates as it writes them (ISO 8601 text,
    /// `JSONStore` and `SettingsSyncService`).
    public static func document(from data: Data) -> SidebarDocument? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SidebarDocument.self, from: data)
    }
}

extension MobileSpaces {
    /// The Spaces sheet's colour and its text: the Space's first colour softened a third of the
    /// way to white, and white text where that comes out dark enough (Arc Search's purple Space,
    /// #a687c8 in TidBITS' screenshot, has white text).
    public struct SheetStyle: Equatable {
        public var fill: String
        public var lightText: Bool

        public init(fill: String, lightText: Bool) {
            self.fill = fill
            self.lightText = lightText
        }
    }

    public static func sheetStyle(colors: [String]) -> SheetStyle? {
        guard let first = colors.first, let c = HexColor.components(first) else { return nil }
        func softened(_ v: Double) -> Double { v + (1 - v) * 0.35 }
        let (r, g, b) = (softened(c.r), softened(c.g), softened(c.b))
        let fill = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        return SheetStyle(fill: fill, lightText: (HexColor.luminance(fill) ?? 1) < 0.62)
    }
}

/// "Favorite in App": the sites the phone keeps under the empty search field. `favorites.json`.
public struct MobileFavorites: Codable, Equatable {
    public struct Site: Codable, Equatable, Identifiable {
        public var url: String
        public var title: String
        public var id: String { url }

        public init(url: String, title: String) {
            self.url = url
            self.title = title
        }
    }

    public var sites: [Site] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sites = try c.decodeIfPresent([Site].self, forKey: .sites) ?? []
    }

    private enum CodingKeys: String, CodingKey { case sites }

    /// A page counts as the favorite of its address without tracking parameters or fragment.
    static func key(_ url: String) -> String {
        var clean = CleanURL.withoutTrackers(url)
        if let hash = clean.firstIndex(of: "#") { clean = String(clean[..<hash]) }
        return clean.hasSuffix("/") ? String(clean.dropLast()) : clean
    }

    public func contains(_ url: String) -> Bool {
        sites.contains { Self.key($0.url) == Self.key(url) }
    }

    /// Adds the page, or removes it when it is already a favorite. Returns whether it is one now.
    @discardableResult
    public mutating func toggle(url: String, title: String) -> Bool {
        if contains(url) {
            sites.removeAll { Self.key($0.url) == Self.key(url) }
            return false
        }
        sites.append(Site(url: url, title: title.isEmpty ? (URL(string: url)?.host ?? url) : title))
        return true
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard sites.indices.contains(source), (0..<sites.count).contains(destination) else { return }
        sites.insert(sites.remove(at: source), at: destination)
    }

    /// What shows under the empty search field: the first four, as in Arc Search.
    public func shown(limit: Int = MobileSearchSheet.visibleRows) -> [Site] {
        Array(sites.prefix(limit))
    }
}

extension MobileSpaces {
    /// The Spaces sheet in dark mode, every colour "#RRGGBB".
    public struct DarkSheetStyle: Equatable {
        /// The sheet, top to bottom.
        public var top: String
        public var bottom: String
        /// The Space icons' bar along the bottom.
        public var bar: String
        /// The Space's name, and the rows' text.
        public var title: String
        public var text: String
        /// The close button's disc; its cross takes `top`.
        public var closeDisc: String
        /// A folder's front, its back (with the tab), and the edge round both.
        public var folderFront: String
        public var folderBack: String
        public var folderEdge: String
    }

    /// Arc Search in dark mode draws a Space's sheet in shades of the Space's colour whose
    /// perceived lightness is the same whatever the colour. Victor's screenshots of 13 Nov show it
    /// for a yellow Space and Arc's default blue one: in OKLCH the sheet's top is L 0.32 in both,
    /// its bottom 0.32, the close disc 0.515, the rows' text 0.97, a folder's front 0.47 and its
    /// edge 0.95, each with a small fixed chroma (a folder's front as vivid as the colour allows at
    /// its lightness). The name, the bar and a folder's back are the yellow Space's (a themed Space;
    /// the blue one is Arc's no-theme default, a little dimmer there). Only the hue is the Space's: its most colourful
    /// colour's, turned by what the yellow Space showed (the bottom a little warmer). A grey
    /// Space stays grey.
    public static func darkSheetStyle(colors: [String]) -> DarkSheetStyle? {
        let shades = colors.compactMap(HexColor.components).map(OKLCH.init)
        guard let base = shades.max(by: { $0.c < $1.c }) else { return nil }
        let tint: Double = base.c < 0.01 ? 0 : 1
        func shade(_ l: Double, _ c: Double, _ turn: Double) -> String {
            OKLCH(l: l, c: c * tint, h: base.h + turn).hex
        }
        return DarkSheetStyle(
            top: shade(0.322, 0.038, 11),
            bottom: shade(0.321, 0.049, -9),
            bar: shade(0.404, 0.08, -4.5),
            title: shade(0.927, 0.092, 12.5),
            text: shade(0.97, 0.024, 11),
            closeDisc: shade(0.515, 0.048, 6),
            folderFront: shade(0.47, 0.3, 4.5),
            folderBack: shade(0.794, 0.162, 2),
            folderEdge: shade(0.948, 0.065, 8.5))
    }

    /// OKLCH: perceived lightness 0...1, chroma, hue in degrees. Colours outside sRGB lose chroma
    /// until they fit.
    struct OKLCH {
        var l: Double, c: Double, h: Double

        init(l: Double, c: Double, h: Double) { (self.l, self.c, self.h) = (l, c, h) }

        init(_ rgb: (r: Double, g: Double, b: Double)) {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let r = linear(rgb.r), g = linear(rgb.g), b = linear(rgb.b)
            let lc = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let mc = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let sc = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            l = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc
            let a = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc
            let bb = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
            c = (a * a + bb * bb).squareRoot()
            h = (atan2(bb, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        }

        private static func rgb(l: Double, c: Double, h: Double) -> (Double, Double, Double) {
            let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
            let lc = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
            let mc = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
            let sc = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
            return (4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
                    -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
                    -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)
        }

        var hex: String {
            var chroma = c
            var value = Self.rgb(l: l, c: chroma, h: h)
            func fits(_ v: (Double, Double, Double)) -> Bool { [v.0, v.1, v.2].allSatisfy { $0 >= -0.0005 && $0 <= 1.0005 } }
            while !fits(value), chroma > 0 {
                chroma = max(0, chroma - 0.002)
                value = Self.rgb(l: l, c: chroma, h: h)
            }
            func byte(_ v: Double) -> Int {
                let clamped = min(1, max(0, v))
                let encoded = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
                return Int((encoded * 255).rounded())
            }
            return String(format: "#%02X%02X%02X", byte(value.0), byte(value.1), byte(value.2))
        }
    }

    /// Hue in degrees, saturation and lightness 0...1.
    struct HSL {
        var h: Double, s: Double, l: Double

        init(h: Double, s: Double, l: Double) { (self.h, self.s, self.l) = (h, s, l) }

        init(_ c: (r: Double, g: Double, b: Double)) {
            let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b)
            l = (high + low) / 2
            let d = high - low
            guard d > 0 else { (h, s) = (0, 0); return }
            s = d / (1 - abs(2 * l - 1))
            switch high {
            case c.r: h = 60 * ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6)
            case c.g: h = 60 * ((c.b - c.r) / d + 2)
            default: h = 60 * ((c.r - c.g) / d + 4)
            }
            if h < 0 { h += 360 }
        }

        var hex: String {
            let c = (1 - abs(2 * l - 1)) * s
            let hh = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
            let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
            let (r, g, b): (Double, Double, Double)
            switch hh {
            case ..<1: (r, g, b) = (c, x, 0)
            case ..<2: (r, g, b) = (x, c, 0)
            case ..<3: (r, g, b) = (0, c, x)
            case ..<4: (r, g, b) = (0, x, c)
            case ..<5: (r, g, b) = (x, 0, c)
            default: (r, g, b) = (c, 0, x)
            }
            let m = l - c / 2
            func byte(_ v: Double) -> Int { Int(((v + m) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }
    }
}
