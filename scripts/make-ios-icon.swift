// Renders the iOS app icon from brand/cra-segments-icon.svg into the iOS asset catalog:
// 1024 px, square and opaque, because iOS cuts the corners itself. The Mac icons come from
// scripts/make-app-icons.swift; WebKit draws both so the ribbons' multiply blending survives.
//   swift scripts/make-ios-icon.swift
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("iOS/Cra/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
var svg = try! String(contentsOf: root.appendingPathComponent("brand/cra-segments-icon.svg"), encoding: .utf8)
// A full-bleed tile: no rounded corners, the SVG as wide as the page.
svg = svg.replacingOccurrences(of: #" rx="14.3""#, with: "")
let tag = svg.range(of: #"width="64" height="64""#)!
svg.replaceSubrange(tag, with: #"style="display:block;width:100vw;height:100vw""#)

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))

    func start() {
        view.navigationDelegate = self
        view.loadHTMLString("<!doctype html><html><body style='margin:0;overflow:hidden'>\(svg)</body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: 1024 / Double(webView.window?.backingScaleFactor ?? 2))
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError(error?.localizedDescription ?? "no image")
            }
            // Redrawn without an alpha channel: App Store Connect refuses an icon that has one.
            let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
            let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
            try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! rep.representation(using: .png, properties: [:])!.write(to: out)
            print("wrote \(out.path) (\(rep.pixelsWide) px)")
            exit(0)
        }
    }
}

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 512, height: 512), styleMask: .borderless, backing: .buffered, defer: false)
let renderer = Renderer()
window.contentView = renderer.view
window.orderBack(nil)
renderer.start()
app.run()
