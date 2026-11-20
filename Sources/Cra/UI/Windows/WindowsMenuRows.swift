import AppKit

/// `cra://debug?windowsMenu=<label>`: the windows AppKit lists in the Window menu, which is also the list the
/// Dock icon's menu shows above New Window. Rows are the menu's items that bring a window forward (their target
/// is the window). The main window is "main", a Little Window or Peek "little", anything else its title, marked
/// "hidden" when it can't be seen (Chrome's windows at alpha 0) and "docked" when it is a child of another window.
enum WindowsMenuRows {
    static func readout(_ label: String, main: NSWindow?, little: [NSWindow]) -> String {
        let windows = (NSApp.windowsMenu?.items ?? []).compactMap { $0.target as? NSWindow }
        let names = windows.map { w in
            w === main ? "main" : little.contains { $0 === w } ? "little"
                : "\"\(w.title)\"" + (w.alphaValue == 0 ? " hidden" : "") + (w.parent != nil ? " docked" : "")
        }
        return "windows menu \(label): \(names.count) [\(names.joined(separator: ", "))]"
    }
}
