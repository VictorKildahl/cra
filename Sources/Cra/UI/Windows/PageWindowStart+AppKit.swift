import AppKit
import CraCEF

/// PageWindowStart's AppKit side (the rule is CraCore's): Cra's windows as they are now, handed to
/// the bridge, which moves each new page window there before Chromium shows it (#354).
extension PageWindowStart {
    @MainActor static func install() {
        CraCEFRuntime.setPageWindowStartHandler { size in
            MainActor.assumeIsolated { frame(size, among: windows) ?? .zero }
        }
    }

    /// Browser windows and Little Windows, front to back, then the ones not on screen.
    @MainActor private static var windows: [Window] {
        // A panel that is key (the command bar, a Peek) belongs to the window it is attached to.
        func root(_ window: NSWindow) -> NSWindow {
            var w = window
            while let parent = w.parent { w = parent }
            return w
        }
        let inUse = (NSApp.keyWindow ?? NSApp.mainWindow).map(root)
        var seen = Set<ObjectIdentifier>()
        return (NSApp.orderedWindows + NSApp.windows).compactMap { w in
            guard seen.insert(ObjectIdentifier(w)).inserted, w.parent == nil,
                  w.windowController is MainWindowController || w.windowController is LittleWindowController else { return nil }
            return Window(frame: w.frame, isInUse: w === inUse, isOnScreen: w.isVisible && w.isOnActiveSpace)
        }
    }
}
