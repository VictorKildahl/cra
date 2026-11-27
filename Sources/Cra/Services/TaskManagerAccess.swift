import AppKit

/// `cra://debug?taskManagerEnd=<title>`: Chrome's Task Manager driven through its accessibility elements (#855), so a
/// scenario ends a page the way a person does: the page's row ("Tab: <title>") picked, then End task.
@MainActor
enum TaskManagerAccess {
    static func endTask(title: String) -> String {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title.lowercased() == "task manager" }) else {
            return "no Task Manager window"
        }
        let all = elements(under: window)
        let rows = all.filter { $0.accessibilityRole() == .row }
        guard let row = rows.first(where: { label($0).hasPrefix("Tab: \(title)") }) else {
            return "no row for \(title) in \(rows.map(label))"
        }
        row.setAccessibilitySelected(true)
        guard let button = all.first(where: { $0.accessibilityRole() == .button && label($0) == "End task" }) else {
            return "no End task button"
        }
        return button.accessibilityPerformPress() ? "pressed for \(label(row))" : "End task refused"
    }

    private static func label(_ e: NSAccessibilityProtocol) -> String {
        let title = e.accessibilityTitle() ?? ""
        return title.isEmpty ? e.accessibilityLabel() ?? "" : title
    }

    private static func elements(under root: NSAccessibilityProtocol, depth: Int = 0) -> [NSAccessibilityProtocol] {
        guard depth < 40 else { return [] }
        let children = (root.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }
        return children.flatMap { [$0] + elements(under: $0, depth: depth + 1) }
    }
}
