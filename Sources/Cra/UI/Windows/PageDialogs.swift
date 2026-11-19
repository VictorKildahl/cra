import AppKit
import CraCEF

/// For scenarios (`cra://debug?pageDialogs=<label>`): every window Chromium shows for a page, as a
/// user would find it. Those are the dialogs and bubbles Chromium hangs on a profile's (never seen)
/// Browser window: alert, confirm, prompt, "Leave site?", the HTTP sign-in prompt, the screen-share
/// picker, a device chooser, "Save password?". A page's popups (a date picker) and the colour panel
/// (`<input type=color>`) count too, and the AppKit alerts Chrome shows for "Leave site?". Each line gives its size, where it sits (CraCore
/// PageDialogPlacement: on the page, the window, a sliver or off), whether it is in front there among
/// Cra's windows, and what it says: its text, buttons and fields, read through accessibility.
/// `press=<title>` presses that button and `fill=<a,b>` types into its fields in order, both the way
/// VoiceOver does, so no pointer or key goes anywhere.
@MainActor
enum PageDialogs {
    /// The windows, front to back. Not `NSApp.orderedWindows`: it leaves panels out, and Chrome's
    /// "Leave site?" alert is one.
    static func windows() -> [NSWindow] {
        frontToBack().filter { w in
            guard w.isVisible, w.alphaValue > 0, !CraCEFRuntime.isPageWindow(w) else { return false }
            let cls = NSStringFromClass(type(of: w))
            if cls == "RenderWidgetPopupWindow" { return true }
            if w is NSColorPanel { return true }
            // Chrome's app-modal dialogs ("Leave site?", "Reload site?") are AppKit alerts of their own.
            if cls == "_NSAlertPanel" { return true }
            return cls == ChromiumDialog.windowClass && w.parent.map { CraCEFRuntime.isPageWindow($0) } == true
        }
    }

    static func readout(_ label: String, page: NSView?, window: NSWindow?, press: String?, fill: [String]?) -> String {
        let pageRect = page.flatMap { v in v.window.map { $0.convertToScreen(v.convert(v.bounds, to: nil)) } }
        let shown = windows()
        var lines = shown.map { line(label, $0, page: pageRect, window: window?.frame ?? .zero) }
        lines.append("page dialogs \(label): n=\(shown.count)")
        if let fill, let w = shown.first {
            let fields = elements(in: w.contentView).filter { $0.accessibilityRole() == .textField }
            for (field, text) in zip(fields, fill) { field.setAccessibilityValue(text) }
            lines.append("page dialogs \(label): filled \(min(fields.count, fill.count)) of \(fields.count)")
        }
        if let press {
            let button = shown.lazy.compactMap { w in elements(in: w.contentView).first { isButton($0, titled: press) } }.first
            button?.accessibilityPerformPress()
            lines.append("page dialogs \(label): \(button == nil ? "no button \(press)" : "pressed \(press)")")
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ label: String, _ w: NSWindow, page: CGRect?, window: CGRect) -> String {
        let cls = NSStringFromClass(type(of: w))
        let kind = w is NSColorPanel ? "colors" : cls == "RenderWidgetPopupWindow" ? "popup" : cls == "_NSAlertPanel" ? "alert" : "chrome"
        let at = PageDialogPlacement.of(w.frame, page: page, window: window)
        let all = elements(in: w.contentView)
        let text = all.filter { $0.accessibilityRole() == .staticText }
            .compactMap { ($0.accessibilityValue() as? String) ?? $0.accessibilityLabel() }
            .map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }.filter { !$0.isEmpty }
        let buttons = all.filter { $0.accessibilityRole() == .button }.compactMap { $0.accessibilityTitle() ?? $0.accessibilityLabel() }.filter { !$0.isEmpty }
        let fields = all.filter { $0.accessibilityRole() == .textField }.count
        return "page dialog \(label): \(kind) \(Int(w.frame.width))x\(Int(w.frame.height)) at=\(at.rawValue) front=\(inFront(w) ? 1 : 0)"
            + " text=\(text.joined(separator: "|")) buttons=\(buttons.joined(separator: "|")) fields=\(fields)"
    }

    /// Whether it is the first of Cra's windows at its centre that shows and takes clicks.
    private static func inFront(_ w: NSWindow) -> Bool {
        let centre = CGPoint(x: w.frame.midX, y: w.frame.midY)
        let first = frontToBack().first { $0.isVisible && $0.alphaValue > 0 && !$0.ignoresMouseEvents && $0.frame.contains(centre) }
        return first === w
    }

    /// Cra's windows on screen, panels included, in the window server's order, front first.
    private static func frontToBack() -> [NSWindow] {
        (NSWindow.windowNumbers(options: []) ?? []).compactMap { NSApp.window(withWindowNumber: $0.intValue) }
    }

    private static func isButton(_ e: NSAccessibilityProtocol, titled title: String) -> Bool {
        e.accessibilityRole() == .button && (e.accessibilityTitle() == title || e.accessibilityLabel() == title)
    }

    /// The window's accessibility tree, depth first.
    private static func elements(in root: Any?) -> [NSAccessibilityProtocol] {
        var out: [NSAccessibilityProtocol] = []
        func walk(_ element: Any?, _ depth: Int) {
            guard depth < 40, let e = element as? NSAccessibilityProtocol else { return }
            out.append(e)
            for child in e.accessibilityChildren() ?? [] { walk(child, depth + 1) }
        }
        walk(root, 0)
        return out
    }
}
