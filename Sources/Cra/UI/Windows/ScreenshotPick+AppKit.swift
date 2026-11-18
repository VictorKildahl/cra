import AppKit

/// ScreenshotPick's AppKit side (the rule is CraCore's, GitHub #346, #539).
extension ScreenshotPick {
    /// `cra://debug?screenshotPick=x,y` (`&target=little` for the newest Little Window): the window
    /// a screenshot app's "window under the pointer" takes at that point of `window` (from its top
    /// left), read from the window list it reads. Over a page that is `window`, whose card draws
    /// the page. Only Cra's windows count: a test copy runs behind other apps. Read as a
    /// ScreenCaptureKit picker reads it, without sharing state or alpha (an `SCWindow` has
    /// neither): a window left out of capture is still the one such a picker takes, and its
    /// capture is blank (#346 on the engine, #539 in a Little Window).
    @MainActor static func readout(of window: NSWindow?, named name: String, at p: CGPoint) -> String {
        guard let window else { return "screenshot pick: no window" }
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = list.compactMap { d -> Window? in
            guard (d[kCGWindowOwnerPID as String] as? Int) == pid, let number = d[kCGWindowNumber as String] as? Int,
                  let bounds = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return .init(number: number, frame: frame, layer: d[kCGWindowLayer as String] as? Int ?? 0,
                         alpha: d[kCGWindowAlpha as String] as? Double ?? 1,
                         shared: (d[kCGWindowSharingState as String] as? Int ?? 1) != 0)
        }
        guard let me = mine.first(where: { $0.number == window.windowNumber }) else { return "screenshot pick: window not listed" }
        let pick = self.window(at: CGPoint(x: me.frame.minX + p.x, y: me.frame.minY + p.y), in: mine, readsSharing: false)
        let picked = pick.map { $0.number == window.windowNumber ? name : "window \($0.number) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none"
        return "screenshot pick at \(Int(p.x)),\(Int(p.y)): \(picked)"
    }
}
