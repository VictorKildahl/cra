// Renders Arc's icon set with Cra's C (brand/arc-icons/<id>.svg, 1024 × 1024 on Apple's icon grid) into
// resources/app-icons/<id>.png at 512 px with its transparency, as brand/arc-icons/README.md says. WebKit draws the
// SVG filters (shadows, blurs, glows) and masks.
//   swift scripts/make-arc-icons.swift [id …]      all nine without ids
//   swift scripts/make-arc-icons.swift --out <dir> [id …]   writes there instead (to compare)
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
var args = Array(CommandLine.arguments.dropFirst())
var outDir = root.appendingPathComponent("resources/app-icons")
if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
    outDir = URL(fileURLWithPath: args[i + 1])
    args.removeSubrange(i...(i + 1))
}
let all = ["original", "candy", "hologram", "neon", "fluted-glass", "schoolbook", "colorful", "canary", "early-birds"]
let ids = args.isEmpty ? all : args

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
    var queue: [String]
    init(_ ids: [String]) { queue = ids }

    func next() {
        guard let id = queue.first else { exit(0) }
        let svg = try! String(contentsOf: root.appendingPathComponent("brand/arc-icons/\(id).svg"), encoding: .utf8)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        // Only the <svg> tag's own size: the clip rectangles inside have the same attributes.
        let tag = svg.range(of: #"width="1024" height="1024""#)!
        let sized = svg.replacingCharacters(in: tag, with: #"style="display:block;width:100vw;height:100vw""#)
        view.loadHTMLString("<!doctype html><html><body style='margin:0;background:transparent;overflow:hidden'>\(sized)</body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = queue.removeFirst()
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: 512 / Double(webView.window?.backingScaleFactor ?? 2))
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("\(id): \(error?.localizedDescription ?? "no image")")
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let out = outDir.appendingPathComponent("\(id).png")
            try! rep.representation(using: .png, properties: [:])!.write(to: out)
            print("wrote \(out.path) (\(rep.pixelsWide) px)")
            self.next()
        }
    }
}

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 256, height: 256), styleMask: .borderless, backing: .buffered, defer: false)
window.backingType = .buffered
let renderer = Renderer(ids)
window.contentView = renderer.view
window.orderBack(nil)
renderer.next()
app.run()
