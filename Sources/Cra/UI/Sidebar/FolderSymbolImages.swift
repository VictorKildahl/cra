import AppKit
import CoreText

extension FolderSymbol {
    var title: String {
        switch self {
        case .star: return "Star"
        case .bookmark: return "Bookmark"
        case .heart: return "Heart"
        case .bolt: return "Lightning"
        case .triangle: return "Triangle"
        case .asterisk: return "Asterisk"
        case .bell: return "Bell"
        case .lightbulb: return "Lightbulb"
        case .chat: return "Chat"
        case .people: return "People"
        case .tools: return "Tools"
        case .egg: return "Egg"
        case .circle: return "Circle"
        case .moon: return "Moon"
        case .planet: return "Planet"
        case .leaf: return "Leaf"
        case .cloud: return "Cloud"
        case .paw: return "Paw"
        case .cutlery: return "Cutlery"
        case .airplane: return "Airplane"
        case .music: return "Music"
        case .video: return "Video"
        case .code: return "Code"
        case .skull: return "Skull"
        }
    }

    var image: NSImage { Self.images[self]! }

    private var character: String {
        switch self {
        case .star: return "\u{f53b}"
        case .bookmark: return "\u{f193}"
        case .heart: return "\u{f33d}"
        case .bolt: return "\u{f2e3}"
        case .triangle: return "\u{f598}"
        case .asterisk: return "\u{f3f7}"
        case .bell: return "\u{f42d}"
        case .lightbulb: return "\u{f1a8}"
        case .chat: return "\u{f1f3}"
        case .people: return "\u{f451}"
        case .tools: return "\u{f262}"
        case .egg: return "\u{f29b}"
        case .circle: return "\u{f29e}"
        case .moon: return "\u{f40f}"
        case .planet: return "\u{f472}"
        case .leaf: return "\u{f373}"
        case .cloud: return "\u{f23b}"
        case .paw: return "\u{f448}"
        case .cutlery: return "\u{f4e1}"
        case .airplane: return "\u{f109}"
        case .music: return "\u{f415}"
        case .video: return "\u{f5a4}"
        case .code: return "\u{f24d}"
        case .skull: return "\u{f52c}"
        }
    }

    private static let font: NSFont = {
        guard let url = Bundle.main.url(forResource: "Ionicons", withExtension: "ttf", subdirectory: "fonts"),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else {
            preconditionFailure("Missing or invalid Ionicons font")
        }
        return CTFontCreateWithGraphicsFont(font, 16, nil, nil) as NSFont
    }()

    private static let images: [FolderSymbol: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { symbol in
        let text = NSAttributedString(string: symbol.character, attributes: [.font: font, .foregroundColor: NSColor.black])
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        return (symbol, image)
    })
}
