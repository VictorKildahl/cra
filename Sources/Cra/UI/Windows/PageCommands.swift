import AppKit
import CraCEF

/// Commands on one page, shared by the browser window (the tab on screen) and a Little Window (its
/// own page, #333). Each takes the browser, the window a sheet hangs from and how to toast.
@MainActor
enum PageCommands {
    typealias Toast = (_ text: String, _ action: ShinyToast.Action?) -> Void

    /// Arc's Edit ▸ Copy URL as Quote (⌃⇧⌘C): the page's selection in quotes with a link that
    /// scrolls to it (CleanURL.quote; Arc's own link goes through arc.net).
    static func copyURLAsQuote(browser b: CraBrowser, url: String, toast: @escaping Toast) {
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { result, _ in
            MainActor.assumeIsolated {
                let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = (value?["result"] as? [String: Any])?["value"] as? String ?? ""
                guard let quote = CleanURL.quote(text, url: url) else { toast("Select Text to Copy as a Quote", nil); return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(quote, forType: .string)
                toast("Copied URL as Quote", nil)
            }
        }
    }

    /// Arc's File ▸ Save Page As (⇧⌘S): Chrome's two formats, a single-file web archive or the
    /// page's HTML.
    static func savePageAs(browser b: CraBrowser, title: String, over window: NSWindow, toast: @escaping Toast) {
        let panel = NSSavePanel()
        let format = SavePageFormat(panel: panel)
        panel.accessoryView = format.view
        let base = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = (base.isEmpty ? "Page" : base) + ".mhtml"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let dest = panel.url else { return }
            let single = format.singleFile
            let (method, params) = single
                ? ("Page.captureSnapshot", #"{"format":"mhtml"}"#)
                : ("Runtime.evaluate", #"{"expression":"'<!DOCTYPE html>\n'+document.documentElement.outerHTML","returnByValue":true}"#)
            b.sendDevToolsMethod(method, params: params) { result, error in
                MainActor.assumeIsolated {
                    let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    let text = single ? o?["data"] as? String : (o?["result"] as? [String: Any])?["value"] as? String
                    guard let text, (try? Data(text.utf8).write(to: dest, options: .atomic)) != nil else {
                        NSLog("Cra: save page failed: %@", error ?? "no data")
                        toast("Couldn’t Save the Page", nil)
                        return
                    }
                    toast("Page Saved", nil)
                }
            }
        }
    }

    /// Arc's "Capture the full page": the whole document, beyond the viewport, as a PNG.
    static func captureFullPage(browser b: CraBrowser, over window: NSWindow, toast: @escaping Toast) {
        toast("Capture in Progress", nil)
        // Both completions come on the main queue.
        b.sendDevToolsMethod("Page.getLayoutMetrics", params: "{}") { result, error in
            guard let result, let m = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
                  let size = (m["cssContentSize"] ?? m["contentSize"]) as? [String: Any],
                  let w = size["width"] as? Double, let h = size["height"] as? Double else {
                MainActor.assumeIsolated { finishCapture(nil, error: error, over: window, toast: toast) }
                return
            }
            let params = #"{"format":"png","captureBeyondViewport":true,"clip":{"x":0,"y":0,"width":\#(w),"height":\#(min(h, 16384)),"scale":1}}"#
            b.sendDevToolsMethod("Page.captureScreenshot", params: params) { shot, error in
                MainActor.assumeIsolated { finishCapture(shot, error: error, over: window, toast: toast) }
            }
        }
    }

    /// Arc's File ▸ Capture in Portrait Mode: the page laid out at a phone's width (390 × 844 pt,
    /// the layout a site gives an iPhone 15) and captured at 3x, then put back as it was.
    static func capturePortrait(browser b: CraBrowser, over window: NSWindow, toast: @escaping Toast) {
        toast("Capture in Progress", nil)
        let metrics = #"{"width":390,"height":844,"deviceScaleFactor":3,"mobile":true}"#
        b.sendDevToolsMethod("Emulation.setDeviceMetricsOverride", params: metrics) { _, error in
            MainActor.assumeIsolated {
                guard error == nil else { finishCapture(nil, error: error, over: window, toast: toast); return }
                // A layout pass and a paint at the new width before the shot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png"}"#) { shot, error in
                        b.sendDevToolsMethod("Emulation.clearDeviceMetricsOverride", params: "{}") { _, _ in }
                        MainActor.assumeIsolated { finishCapture(shot, error: error, over: window, toast: toast) }
                    }
                }
            }
        }
    }

    /// As Arc does with a capture: the image goes on the clipboard with the shutter sound, and
    /// the toast's Save puts it in a file. Finder stays where it is (GitHub #90).
    private static func finishCapture(_ shot: String?, error: String?, over window: NSWindow, toast: @escaping Toast) {
        guard let shot, let o = try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any],
              let b64 = o["data"] as? String, let png = Data(base64Encoded: b64), NSImage(data: png) != nil else {
            NSLog("Cra: capture failed: %@", error ?? "no data")
            toast("Capture Failed", nil)
            return
        }
        copyCapture(png)
        CaptureSound.play()
        toast("Screenshot Copied to Clipboard", ShinyToast.Action(title: "Save") { [weak window] in
            guard let window else { return }
            saveCapture(png, over: window) { toast($0, nil) }
        })
    }

    static func copyCapture(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// The toast's Save: Arc's "Save Capture Image" panel, in Downloads.
    static func saveCapture(_ png: Data, over window: NSWindow, failed: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Save Capture Image"
        panel.nameFieldStringValue = captureFileName()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                NSLog("Cra: saving a capture failed: %@", error.localizedDescription)
                failed("Failed to Save Capture")
            }
        }
    }

    static func captureFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Cra Capture \(f.string(from: Date())).png"
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Jump to Selection (⌘J): the page scrolls its selection into view.
    static func jumpToSelection(browser b: CraBrowser) {
        b.executeJavaScript("(()=>{const s=getSelection();if(!s.rangeCount)return;const n=s.getRangeAt(0).startContainer;"
            + "(n.nodeType===1?n:n.parentElement)?.scrollIntoView({block:'center'});})()")
    }
}
