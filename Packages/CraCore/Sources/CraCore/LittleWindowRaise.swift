import CoreGraphics
import Foundation

/// A window in the window server's list (CGWindowListCopyWindowInfo, front to back).
public struct StackedWindow: Equatable {
    public var number: Int
    public var pid: Int32
    public var layer: Int
    /// From the top left of the main display, as the window server gives it.
    public var bounds: CGRect

    public init(number: Int, pid: Int32, layer: Int = 0, bounds: CGRect) {
        self.number = number
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
    }

    #if os(macOS)
    /// The window server's description of each window, front to back; entries it can't read are left out.
    public static func stack(from info: [[String: Any]]) -> [StackedWindow] {
        info.compactMap { w in
            guard let number = (w[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return StackedWindow(number: number, pid: pid, layer: layer, bounds: bounds)
        }
    }
    #endif
}

/// A Little Window opened from another app leaves Cra's browser window where it was (#607). macOS raises an app's main
/// window as it comes forward for a link, so Cra's browser window rose over the app the link came from, on its own
/// display, as the Little Window came up on another one. Arc 1.173.1 does the same (docs/arc-parity.md); Cra doesn't, on
/// purpose (Victor, 20 Nov 2026). Cra notes the window that was just in front of the browser window and puts it back
/// behind it, as the link arrives and again as the Little Window comes up.
public enum LittleWindowRaise {
    /// Other apps' normal windows in front of window `number` that overlap it.
    public static func othersOver(_ number: Int, in stack: [StackedWindow], pid: Int32) -> Int {
        guard let i = stack.firstIndex(where: { $0.number == number }) else { return 0 }
        let mine = stack[i]
        return stack[..<i].filter { $0.pid != pid && $0.layer == 0 && $0.bounds.intersects(mine.bounds) }.count
    }

    #if os(macOS)
    // The window server's list exists only on the Mac (the iPhone app builds CraCore too).
    public static func othersOver(_ number: Int, in info: [[String: Any]], pid: Int32 = getpid()) -> Int {
        othersOver(number, in: StackedWindow.stack(from: info), pid: pid)
    }
    #endif

    /// The other app's normal window just in front of window `number`, over it: the one it goes back
    /// behind once the Little Window is up. Nil when nothing of another app's covers it (it was in
    /// front, so rising takes nothing from anyone).
    public static func anchor(for number: Int, in stack: [StackedWindow], pid: Int32) -> Int? {
        guard let i = stack.firstIndex(where: { $0.number == number }) else { return nil }
        let mine = stack[i]
        return stack[..<i].last { $0.pid != pid && $0.layer == 0 && $0.bounds.intersects(mine.bounds) }?.number
    }

    /// Whether window `number` goes back behind `anchor`: while both are on screen. Not by whether it rose: the window
    /// server's list catches up with AppKit's raise only later, so a check of the order missed it and the browser
    /// window stayed in front until the Little Window had grown in. Ordered behind the window just in front of it, it stays where
    /// it was. Not when either is gone from the screen (closed, minimized, another Space).
    /// `isKey` with `clickedIfKey` (the Little Window has had the keys): the browser window was clicked meanwhile, is in
    /// use and stays in front. Before the Little Window has had them, a key browser window is key only because Cra came
    /// forward (AppKit hands the keys back to the window that had them) and goes back all the same; skipping it left
    /// it in front until the Little Window had grown in.
    public static func goesBack(_ number: Int, behind anchor: Int, in stack: [StackedWindow],
                                isKey: Bool = false, clickedIfKey: Bool = false) -> Bool {
        if isKey && clickedIfKey { return false }
        return stack.contains { $0.number == number } && stack.contains { $0.number == anchor }
    }
}
