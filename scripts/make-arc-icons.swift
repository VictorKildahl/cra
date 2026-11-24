// Renders Arc's icon set with Cra's C (brand/arc-icons/<id>.svg, 1024 × 1024 on Apple's icon grid) into
// resources/app-icons/<id>.png at 512 px with its transparency, as brand/arc-icons/README.md says. WebKit draws the
// SVG filters (shadows, blurs, glows) and masks.
//   swift scripts/make-arc-icons.swift [id …]      all nine without ids
//   swift scripts/make-arc-icons.swift --out <dir> [id …]   writes there instead (to compare)
// With --ios it renders them for the iPhone app instead: the tile alone, square to its corners (iOS cuts them
// itself, and the in-app picker rounds them less), 1024 px and opaque, into iOS/Cra/Resources/Assets.xcassets as
// alternate icons (AppIcon-<Name>, MobileAppIcon) with the 512 px pictures the in-app pickers show.
//   swift scripts/make-arc-icons.swift --ios [id …]
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
var args = Array(CommandLine.arguments.dropFirst())
var outDir = root.appendingPathComponent("resources/app-icons")
if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
    outDir = URL(fileURLWithPath: args[i + 1])
    args.removeSubrange(i...(i + 1))
}
let forIOS = args.contains("--ios")
args.removeAll { $0 == "--ios" }
let all = ["original", "candy", "hologram", "neon", "fluted-glass", "schoolbook", "colorful", "canary", "early-birds"]
let ids = args.isEmpty ? all : args

/// Each icon's name in the iPhone app's asset catalog (MobileAppIcon.alternateName).
let iosNames = ["original": "AppIcon-Original", "candy": "AppIcon-Candy", "hologram": "AppIcon-Hologram", "neon": "AppIcon-Neon",
                "fluted-glass": "AppIcon-FlutedGlass", "schoolbook": "AppIcon-Schoolbook", "colorful": "AppIcon-Colorful",
                "canary": "AppIcon-Canary", "early-birds": "AppIcon-EarlyBirds"]
/// The rounded tile every icon draws once (824 px on the grid), and the square that replaces it for iOS.
let squircle = "M100 396C100 292.4 100 240.6 120.2 201C137.9 166.2 166.2 137.9 201 120.2C240.6 100 292.4 100 396 100H628C731.6 100 783.4 100 823 120.2C857.8 137.9 886.1 166.2 903.8 201C924 240.6 924 292.4 924 396V628C924 731.6 924 783.4 903.8 823C886.1 857.8 857.8 886.1 823 903.8C783.4 924 731.6 924 628 924H396C292.4 924 240.6 924 201 903.8C166.2 886.1 137.9 857.8 120.2 823C100 783.4 100 731.6 100 628V396Z"

/// `cg` drawn without an alpha channel (App Store Connect refuses an icon with one) at `size` px, as PNG.
func opaquePNG(_ cg: CGImage, size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func writeIOS(_ id: String, _ cg: CGImage) {
    let catalog = root.appendingPathComponent("iOS/Cra/Resources/Assets.xcassets")
    let name = iosNames[id]!
    let iconSet = catalog.appendingPathComponent("\(name).appiconset")
    let preview = catalog.appendingPathComponent("\(name)-Preview.imageset")
    for folder in [iconSet, preview] { try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    try! opaquePNG(cg, size: 1024).write(to: iconSet.appendingPathComponent("AppIcon.png"))
    try! opaquePNG(cg, size: 512).write(to: preview.appendingPathComponent("icon.png"))
    let info = #"  "info" : { "author" : "xcode", "version" : 1 }"#
    try! "{\n  \"images\" : [ { \"filename\" : \"AppIcon.png\", \"idiom\" : \"universal\", \"platform\" : \"ios\", \"size\" : \"1024x1024\" } ],\n\(info)\n}\n"
        .write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    try! "{\n  \"images\" : [ { \"filename\" : \"icon.png\", \"idiom\" : \"universal\" } ],\n\(info)\n}\n"
        .write(to: preview.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(iconSet.path) and its preview")
}

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
    var queue: [String]
    init(_ ids: [String]) { queue = ids }

    func next() {
        guard let id = queue.first else { exit(0) }
        let svg = try! String(contentsOf: root.appendingPathComponent("brand/arc-icons/\(id).svg"), encoding: .utf8)
        view.navigationDelegate = self
        view.setValue(forIOS, forKey: "drawsBackground")
        // Only the <svg> tag's own size: the clip rectangles inside have the same attributes.
        let tag = svg.range(of: #"width="1024" height="1024""#)!
        var sized = svg.replacingCharacters(in: tag, with: #"style="display:block;width:100vw;height:100vw""#)
        if forIOS {
            // The iPhone's icon is the tile, square: the view shows only the tile, which loses its round.
            guard sized.components(separatedBy: squircle).count == 2 else { fatalError("\(id): no single tile to square") }
            sized = sized.replacingOccurrences(of: squircle, with: "M100 100H924V924H100Z")
                .replacingOccurrences(of: #"viewBox="0 0 1024 1024""#, with: #"viewBox="100 100 824 824""#)
        }
        // Original's tile is frosted glass (white at 51-75 %) that shows the Mac's desktop through it. An iPhone icon
        // is opaque, so there it lies on iOS's light system grey, which keeps its rim and the C's white edge visible.
        let backdrop = forIOS ? "#c7c7cc" : "transparent"
        view.loadHTMLString("<!doctype html><html><body style='margin:0;background:\(backdrop);overflow:hidden'>\(sized)</body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = queue.removeFirst()
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: (forIOS ? 1024 : 512) / Double(webView.window?.backingScaleFactor ?? 2))
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("\(id): \(error?.localizedDescription ?? "no image")")
            }
            if forIOS {
                writeIOS(id, cg)
                return self.next()
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
