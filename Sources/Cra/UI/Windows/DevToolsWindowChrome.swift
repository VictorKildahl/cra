import AppKit

/// How Chromium's DevTools window is dressed. CEF hands it over as a window of its own, 10 pt
/// square in a corner of the screen; Cra hangs it on the window whose page it inspects, over
/// that page's area (a pane of the browser window, a Little Window, a Peek), or, when the
/// frontend's "Undock into separate window" is picked, lets it go as an ordinary window.
@MainActor
enum DevToolsWindowChrome {
    /// Strips the window to its content, ready to be a child window over a page's area.
    /// Not resizable: the edge zone outside a resizable window would take drags meant for the
    /// frontend's splitter (undocking makes it resizable again).
    static func dock(_ w: NSWindow) {
        w.styleMask.remove([.titled, .resizable])
        w.styleMask.insert(.fullSizeContentView)
        ChromiumWindowCorners.setSquare(true, for: w)
        ChromiumChildHover.setDocked(true, for: w)
        w.styleMask.remove([.closable, .miniaturizable])
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(type)?.isHidden = true }
        w.hasShadow = false
        w.isMovable = false
        w.isMovableByWindowBackground = false
        w.isOpaque = false
        w.backgroundColor = .clear
    }

    /// A normal titled window, like Chrome's undocked "DevTools - <address>", centred a little off
    /// `parent` (the frontend draws under a real title bar; `dock` strips all of this again).
    static func undock(_ w: NSWindow, over parent: NSWindow, pageURL: String?) {
        w.styleMask.remove(.fullSizeContentView)
        w.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        ChromiumWindowCorners.setSquare(false, for: w)
        ChromiumChildHover.setDocked(false, for: w)
        w.titlebarAppearsTransparent = false
        w.titleVisibility = .visible
        if let url = pageURL, !url.isEmpty {
            w.title = "DevTools - " + url.replacingOccurrences(of: "^[a-z]+://", with: "", options: .regularExpression)
        }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(type)?.isHidden = false }
        w.hasShadow = true
        w.isMovable = true
        w.isOpaque = true
        w.backgroundColor = .windowBackgroundColor
        if let cv = w.contentView {
            cv.layer?.cornerRadius = 0
            cv.layer?.masksToBounds = false
        }
        let f = parent.frame
        let size = NSSize(width: min(1100, f.width * 0.8), height: min(760, f.height * 0.8))
        w.setFrame(NSRect(x: f.midX - size.width / 2 + 40, y: f.midY - size.height / 2 - 20, width: size.width, height: size.height), display: true)
    }

    /// CEF's frame view keeps a frameless window's content view at full window size, so an
    /// undocked window's title bar covers the top of the frontend. This script, run in the
    /// frontend, moves its layout down by the title bar's height instead (`w` nil, docked: by 0).
    static func titleBarInsetScript(for w: NSWindow?) -> String {
        let inset = w.map { max(0, $0.frame.height - $0.contentLayoutRect.height) } ?? 0
        let css = inset > 0 ? "body{margin-top:\(Int(inset))px!important;height:calc(100% - \(Int(inset))px)!important}" : ""
        return "(function(){var s=document.getElementById('cra-titlebar-inset');"
            + "if(!s){s=document.createElement('style');s.id='cra-titlebar-inset';document.head.appendChild(s);}"
            + "s.textContent='\(css)';})();"
    }
}
