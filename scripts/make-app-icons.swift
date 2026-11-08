// Renders the alternate app icons in Settings ▸ General ▸ App Icon from the brand marks
// (brand/*.svg) into resources/app-icons/<id>.png, 512 px (Dock tiles top out at 128 pt), on Apple's icon grid:
// the tile is 824 of 1024 px, centred, the size the Dock gives the edge-to-edge AppIcon.icns.
// segments.png is only the picker's preview of the bundled icon.
// WebKit draws them so the ribbons' multiply blending survives (see brand/README.md).
//   swift scripts/make-app-icons.swift
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func brand(_ name: String) -> String { try! String(contentsOf: root.appendingPathComponent("brand/\(name).svg"), encoding: .utf8) }

let sand = ##"<stop offset="0" stop-color="#f2e3c4"/><stop offset="1" stop-color="#e8d3aa"/>"##
let segments = brand("cra-segments-icon")
// The mono mark's ribbons, white, with the icon's drop shadow under them.
let monoRibbons = brand("cra-segments-mono")
    .replacingOccurrences(of: #"^<svg[^>]*>"#, with: "", options: .regularExpression)
    .replacingOccurrences(of: "</svg>", with: "")
    .replacingOccurrences(of: "currentColor", with: "#fff")
let shadow = segments.range(of: #"<g opacity=".18".*?</g>"#, options: .regularExpression).map { String(segments[$0]) }!
// The four coloured ribbons (12 wide, multiplied), without the white edge under them.
let ribbons = segments.ranges(of: #/<path [^>]*stroke-width="12"[^>]*/>/#).map { String(segments[$0]) }.joined()
// Arc's family (#259): yellow, green, coral, blue become warm, magenta, orchid, blue-violet.
let violetRibbons = [("#f6c34a", "#f3b985"), ("#4fbe7e", "#e438a7"), ("#f0574f", "#c33bd1"), ("#3f6df5", "#7b5cff")]
    .reduce(ribbons) { $0.replacingOccurrences(of: $1.0, with: $1.1) }

let icons: [String: String] = [
    // Dark tile; on dark, the ribbons blend normally (brand/README.md).
    "segments": segments,
    "midnight": segments
        .replacingOccurrences(of: sand, with: ##"<stop offset="0" stop-color="#2c2e36"/><stop offset="1" stop-color="#16171b"/>"##)
        .replacingOccurrences(of: "mix-blend-mode:multiply", with: "mix-blend-mode:normal"),
    // The shadow follows the 12-wide ribbons here, not the 19-wide white edge.
    "mono": ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64"><defs><linearGradient id="t" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5a84f8"/><stop offset="1" stop-color="#2f58d8"/></linearGradient></defs><rect width="64" height="64" rx="14.3" fill="url(#t)"/><g transform="translate(3.84 3.84) scale(0.88)">"##
        + shadow.replacingOccurrences(of: #"stroke-width="19""#, with: #"stroke-width="12""#) + monoRibbons + "</g></svg>",
    // Arc's flat #100146 tile, the ribbons straight on it like mono's. Isolated, so multiply
    // darkens only where ribbons overlap; against the tile it would turn them almost black.
    "violet": ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64"><rect width="64" height="64" rx="14.3" fill="#100146"/><g transform="translate(3.84 3.84) scale(0.88)">"##
        + shadow.replacingOccurrences(of: #"stroke-width="19""#, with: #"stroke-width="12""#)
        + #"<g style="isolation:isolate">"# + violetRibbons + "</g></g></svg>",
]

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
    var queue: [(String, String)]
    init(_ icons: [String: String]) { queue = icons.sorted { $0.key < $1.key } }

    func next() {
        guard let (_, svg) = queue.first else { exit(0) }
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        // Only the <svg> tag's size: the tile <rect> has the same attributes.
        let tag = svg.range(of: #"width="64" height="64""#)!
        let sized = svg.replacingCharacters(in: tag, with: #"style="display:block;width:80.46875vw;height:80.46875vw;margin:9.765625vw""#)
        view.loadHTMLString("<!doctype html><html><body style='margin:0;background:transparent;overflow:hidden'>\(sized)</body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let (id, _) = queue.removeFirst()
        // 256 pt on the 2x backing: 512 px.
        webView.takeSnapshot(with: nil) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("\(id): \(error?.localizedDescription ?? "no image")")
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            let out = root.appendingPathComponent("resources/app-icons/\(id).png")
            try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! rep.representation(using: .png, properties: [:])!.write(to: out)
            print("wrote \(out.path) (\(rep.pixelsWide) px)")
            self.next()
        }
    }
}

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 256, height: 256), styleMask: .borderless, backing: .buffered, defer: false)
window.backingType = .buffered
let renderer = Renderer(icons)
window.contentView = renderer.view
window.orderBack(nil)
renderer.next()
app.run()
