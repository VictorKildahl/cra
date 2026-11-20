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
}

/// A Little Window opened from another app leaves Cra's browser window where it was (#607). Arc's
/// Little Arc comes up alone; Cra's browser window rose over the app the link came from, on its own
/// display, as Cra came forward and Chrome's hidden window followed the page into the Little Window.
/// Cra notes the window that was just in front of the browser window and puts it back behind it.
public enum LittleWindowRaise {
    /// Other apps' normal windows in front of window `number` that overlap it.
    public static func othersOver(_ number: Int, in stack: [StackedWindow], pid: Int32) -> Int {
        guard let i = stack.firstIndex(where: { $0.number == number }) else { return 0 }
        let mine = stack[i]
        return stack[..<i].filter { $0.pid != pid && $0.layer == 0 && $0.bounds.intersects(mine.bounds) }.count
    }

    public static func othersOver(_ number: Int, in info: [[String: Any]], pid: Int32 = getpid()) -> Int {
        othersOver(number, in: StackedWindow.stack(from: info), pid: pid)
    }

    /// The other app's normal window just in front of window `number`, over it: the one it goes back
    /// behind once the Little Window is up. Nil when nothing of another app's covers it (it was in
    /// front, so rising takes nothing from anyone).
    public static func anchor(for number: Int, in stack: [StackedWindow], pid: Int32) -> Int? {
        guard let i = stack.firstIndex(where: { $0.number == number }) else { return nil }
        let mine = stack[i]
        return stack[..<i].last { $0.pid != pid && $0.layer == 0 && $0.bounds.intersects(mine.bounds) }?.number
    }

    /// Whether window `number` rose in front of `anchor`, and so goes back behind it. Not when either
    /// is gone from the screen (closed, minimized, another Space).
    public static func rose(_ number: Int, over anchor: Int, in stack: [StackedWindow]) -> Bool {
        guard let mine = stack.firstIndex(where: { $0.number == number }),
              let theirs = stack.firstIndex(where: { $0.number == anchor }) else { return false }
        return mine < theirs
    }
}
