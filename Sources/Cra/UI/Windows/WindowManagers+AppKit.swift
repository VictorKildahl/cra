import AppKit

extension WindowManagers {
    /// `cra://debug?windowManagers=<label>`: for each of the app's accessibility windows, whether
    /// a window manager's shortcuts move and resize it, read by attribute name as the
    /// accessibility server asks (no accessibility permission needed). The main window is
    /// "main", a Little Window "little", anything else its size; sorted, so the order of the
    /// windows doesn't matter.
    static func readout(_ label: String, main: NSWindow?, little: [NSWindow]) -> String {
        var rows: [String] = []
        for case let w as NSWindow in NSApp.accessibilityWindows() ?? [] {
            let window = Window(role: w.accessibilityAttributeValue(.role) as? String,
                                subrole: w.accessibilityAttributeValue(.subrole) as? String,
                                canMove: w.accessibilityIsAttributeSettable(.position),
                                canResize: w.accessibilityIsAttributeSettable(.size))
            let name = w === main ? "main" : little.contains { $0 === w } ? "little" : "\(Int(w.frame.width))x\(Int(w.frame.height))"
            rows.append("\(name)=\(handles(window) ? "yes" : "no(\(window.subrole ?? "-"))")")
        }
        return "window managers \(label): \(rows.sorted().joined(separator: " "))"
    }
}
