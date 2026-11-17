import AppKit

/// Keeps a user-set Space name from making an AppKit menu wider than Arc's menus. Every menu
/// gives the name the same allowance; fixed action words around it do not consume that space.
/// The complete title remains available as a tooltip.
@MainActor
enum SpaceMenuTitle {
    struct Value {
        let title: String
        let fullTitle: String
        let displayedName: String

        var toolTip: String? { title == fullTitle ? nil : fullTitle }
    }

    /// Arc 1.172 keeps 24 characters of a long Space name before the ellipsis ("HomeHomeHomeHomeHomeHome…",
    /// about 222 pt, in Spaces ▸ on a 2x capture, PR #481). Keep a rendered-width backstop as well, so
    /// 24 unusually wide characters still cannot stretch a menu without bound.
    static let maximumDisplayedNameLength = 24
    static let maximumDisplayedNameWidth: CGFloat = 260

    static func plain(_ title: String) -> Value { named(title) }

    static func named(_ name: String, prefix: String = "", suffix: String = "") -> Value {
        let fullTitle = prefix + name + suffix
        guard name.count > maximumDisplayedNameLength || width(name) > maximumDisplayedNameWidth else {
            return Value(title: fullTitle, fullTitle: fullTitle, displayedName: name)
        }
        let displayedName = clipped(name)
        return Value(title: prefix + displayedName + suffix, fullTitle: fullTitle, displayedName: displayedName)
    }

    static func apply(_ value: Value, to item: NSMenuItem) {
        item.title = value.title
        item.toolTip = value.toolTip
    }

    private static func clipped(_ name: String) -> String {
        var low = 0, high = min(name.count, maximumDisplayedNameLength)
        while low < high {
            let middle = (low + high + 1) / 2
            if width(String(name.prefix(middle)) + "…") <= maximumDisplayedNameWidth {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return String(name.prefix(low)) + "…"
    }

    private static func width(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }
}
