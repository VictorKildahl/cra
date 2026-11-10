import AppKit
import CraCEF

/// What a window hands the page commands that both kinds of window run (#333): the page in front
/// (a browser window's open tab, or a Little Window's or Peek's own page), the window that holds it
/// and that window's toast.
@MainActor
protocol PageCommandHost: AnyObject {
    var commandBrowser: CraBrowser? { get }
    /// The page's address and title; nil when the window shows no page.
    var commandPage: (url: String, title: String)? { get }
    var commandWindow: NSWindow? { get }
    /// Where the page sits on screen: Share's list hangs from its top centre.
    var commandPageScreenRect: NSRect? { get }
    func showCommandToast(_ text: String, action: ShinyToast.Action?)
}

/// Share…, Copy URL as Quote, Save Page As, the two page captures and Jump to Selection, on the
/// page of the window in front. A Little Window in front runs them on its own page, not on the tab
/// of the browser window behind it (#333).
@MainActor
enum PageCommands {
    /// File ▸ Share…'s list, kept while it is open.
    private static var sharePicker: NSSharingServicePicker?

    /// File ▸ Share… (GitHub #279): the system's whole share list for the page in front (Arc's has
    /// Add to Reading List, AirDrop, Mail, Notes, Copy, Edit Extensions…), hanging from the top
    /// centre of the page as Arc 1.172.1 shows it.
    static func share(_ host: PageCommandHost) {
        guard let url = host.commandPage.flatMap({ URL(string: $0.url) }),
              let window = host.commandWindow, let content = window.contentView else { return }
        let page = host.commandPageScreenRect.map { content.convert(window.convertFromScreen($0), from: nil) } ?? content.bounds
        let top = content.isFlipped ? page.minY : page.maxY
        let anchor = NSRect(x: page.midX - 1, y: content.isFlipped ? top : top - 1, width: 2, height: 1)
        let picker = NSSharingServicePicker(items: [url])
        sharePicker = picker
        picker.show(relativeTo: anchor, of: content, preferredEdge: content.isFlipped ? .maxY : .minY)
    }

    /// Arc's Edit ▸ Copy URL as Quote (⌃⇧⌘C): the page's selection in quotes with a link that
    /// scrolls to it (CleanURL.quote; Arc's own link goes through arc.net).
    static func copyURLAsQuote(_ host: PageCommandHost) {
        guard let b = host.commandBrowser, let url = host.commandPage?.url else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak host] result, _ in
            MainActor.assumeIsolated {
                let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = (value?["result"] as? [String: Any])?["value"] as? String ?? ""
                guard let quote = CleanURL.quote(text, url: url) else { host?.showCommandToast("Select Text to Copy as a Quote", action: nil); return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(quote, forType: .string)
                host?.showCommandToast("Copied URL as Quote", action: nil)
            }
        }
    }

    /// Arc's File ▸ Save Page As (⇧⌘S): Chrome's two formats, a single-file web archive or the
    /// page's HTML.
    static func savePageAs(_ host: PageCommandHost) {
        guard let b = host.commandBrowser, let window = host.commandWindow, let page = host.commandPage else { return }
        let panel = NSSavePanel()
        let format = SavePageFormat(panel: panel)
        panel.accessoryView = format.view
        let base = page.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = (base.isEmpty ? "Page" : base) + ".mhtml"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak host] response in
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
                        host?.showCommandToast("Couldn’t Save the Page", action: nil)
                        return
                    }
                    host?.showCommandToast("Page Saved", action: nil)
                }
            }
        }
    }

    /// Arc's "Capture the full page": the whole document, beyond the viewport, as a PNG.
    static func captureFullPage(_ host: PageCommandHost) {
        guard let b = host.commandBrowser else { return }
        host.showCommandToast("Capture in Progress", action: nil)
        // Both completions come on the main queue.
        b.sendDevToolsMethod("Page.getLayoutMetrics", params: "{}") { [weak host] result, error in
            guard let result, let m = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
                  let size = (m["cssContentSize"] ?? m["contentSize"]) as? [String: Any],
                  let w = size["width"] as? Double, let h = size["height"] as? Double else {
                MainActor.assumeIsolated { host.map { finishCapture($0, nil, error: error) } }
                return
            }
            let params = #"{"format":"png","captureBeyondViewport":true,"clip":{"x":0,"y":0,"width":\#(w),"height":\#(min(h, 16384)),"scale":1}}"#
            b.sendDevToolsMethod("Page.captureScreenshot", params: params) { shot, error in
                MainActor.assumeIsolated { host.map { finishCapture($0, shot, error: error) } }
            }
        }
    }

    /// Arc's File ▸ Capture in Portrait Mode: the page laid out at a phone's width (390 × 844 pt,
    /// the layout a site gives an iPhone 15) and captured at 3x, then put back as it was.
    static func capturePortrait(_ host: PageCommandHost) {
        guard let b = host.commandBrowser else { return }
        host.showCommandToast("Capture in Progress", action: nil)
        let metrics = #"{"width":390,"height":844,"deviceScaleFactor":3,"mobile":true}"#
        b.sendDevToolsMethod("Emulation.setDeviceMetricsOverride", params: metrics) { [weak host] _, error in
            MainActor.assumeIsolated {
                guard error == nil else { host.map { finishCapture($0, nil, error: error) }; return }
                // A layout pass and a paint at the new width before the shot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png"}"#) { shot, error in
                        b.sendDevToolsMethod("Emulation.clearDeviceMetricsOverride", params: "{}") { _, _ in }
                        MainActor.assumeIsolated { host.map { finishCapture($0, shot, error: error) } }
                    }
                }
            }
        }
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Jump to Selection (⌘J): the page scrolls its selection into view.
    static func jumpToSelection(_ browser: CraBrowser?) {
        browser?.executeJavaScript("(()=>{const s=getSelection();if(!s.rangeCount)return;const n=s.getRangeAt(0).startContainer;"
            + "(n.nodeType===1?n:n.parentElement)?.scrollIntoView({block:'center'});})()")
    }

    /// As Arc does with a capture: the image goes on the clipboard with the shutter sound, and
    /// the toast's Save puts it in a file. Finder stays where it is (GitHub #90).
    private static func finishCapture(_ host: PageCommandHost, _ shot: String?, error: String?) {
        guard let shot, let o = try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any],
              let b64 = o["data"] as? String, let png = Data(base64Encoded: b64), NSImage(data: png) != nil else {
            NSLog("Cra: capture failed: %@", error ?? "no data")
            host.showCommandToast("Capture Failed", action: nil)
            return
        }
        copyCapture(png)
        CaptureSound.play()
        host.showCommandToast("Screenshot Copied to Clipboard", action: ShinyToast.Action(title: "Save") { [weak host] in
            guard let host, let window = host.commandWindow else { return }
            saveCapture(png, over: window, host: host)
        })
    }

    static func copyCapture(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// The toast's Save: Arc's "Save Capture Image" panel, in Downloads.
    static func saveCapture(_ png: Data, over window: NSWindow, host: PageCommandHost) {
        let panel = NSSavePanel()
        panel.title = "Save Capture Image"
        panel.nameFieldStringValue = captureFileName()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak host] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                NSLog("Cra: saving a capture failed: %@", error.localizedDescription)
                host?.showCommandToast("Failed to Save Capture", action: nil)
            }
        }
    }

    static func captureFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Cra Capture \(f.string(from: Date())).png"
    }
}

/// Save Page As's Format pop-up (Chrome's "Web Page, Single File" and "Web Page, HTML Only");
/// switching it swaps the name's extension.
@MainActor
private final class SavePageFormat: NSObject {
    let view: NSView
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var panel: NSSavePanel?
    var singleFile: Bool { popup.indexOfSelectedItem == 0 }

    init(panel: NSSavePanel) {
        self.panel = panel
        let label = NSTextField(labelWithString: "Format:")
        popup.addItems(withTitles: ["Web Page, Single File", "Web Page, HTML Only"])
        let row = NSStackView(views: [label, popup])
        row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        view = row
        super.init()
        popup.target = self
        popup.action = #selector(changed)
    }

    @objc private func changed() {
        guard let panel else { return }
        let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = name + (singleFile ? ".mhtml" : ".html")
    }
}

extension MainWindowController: PageCommandHost {
    var commandBrowser: CraBrowser? { currentBrowser }
    var commandPage: (url: String, title: String)? {
        guard let item = selectedTabID.flatMap({ store.item($0) }), let tab = item.tab else { return nil }
        return (tab.url, item.displayTitle)
    }
    var commandWindow: NSWindow? { window }
    var commandPageScreenRect: NSRect? { browsers.visibleRuntime.flatMap(pageScreenRect) }
    func showCommandToast(_ text: String, action: ShinyToast.Action?) { showToast(text, action: action) }
}

extension LittleWindowController: PageCommandHost {
    var commandBrowser: CraBrowser? { browser }
    var commandPage: (url: String, title: String)? {
        hasPage ? (currentURL, browser?.currentTitle ?? state.title) : nil
    }
    var commandWindow: NSWindow? { window }
    var commandPageScreenRect: NSRect? {
        guard let view = browser?.containerView, let w = view.window, w === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
        return w.convertToScreen(view.convert(view.bounds, to: nil))
    }
    func showCommandToast(_ text: String, action: ShinyToast.Action?) { showToast(text, action: action) }
}
