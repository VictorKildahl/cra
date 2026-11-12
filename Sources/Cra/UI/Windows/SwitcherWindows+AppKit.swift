import AppKit

extension SwitcherWindows {
    /// `cra://debug?switcherWindows=<label>`: the windows a window switcher lists for Cra (#401),
    /// from what the app's accessibility element answers for AXWindows (NSApp's
    /// `accessibilityWindows`, so no accessibility permission is needed). The main window is
    /// "main", a Little Window or Peek "little", anything else its size.
    static func readout(_ label: String, main: NSWindow?, little: [NSWindow]) -> String {
        var names: [String] = []
        for case let element as NSObject in NSApp.accessibilityWindows() ?? [] {
            guard let e = element as? NSAccessibilityProtocol else { continue }
            let window = Window(role: e.accessibilityRole()?.rawValue, subrole: e.accessibilitySubrole()?.rawValue,
                                hasCloseButton: e.accessibilityCloseButton() != nil,
                                hasMinimizeButton: e.accessibilityMinimizeButton() != nil)
            guard lists(window) else { continue }
            let w = element as? NSWindow
            if let w, w === main { names.append("main") }
            else if let w, little.contains(where: { $0 === w }) { names.append("little") }
            else {
                let f = e.accessibilityFrame()
                names.append("\(Int(f.width))x\(Int(f.height))")
            }
        }
        return "switcher windows \(label): \(names.count) [\(names.joined(separator: ", "))]"
    }
}

