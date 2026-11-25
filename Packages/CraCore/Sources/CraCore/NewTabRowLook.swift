/// How the sidebar's "+ New Tab" row is drawn. Under the pointer it is an ordinary hovered row, a shade darker
/// with its muted ink, as in Arc 1.174.1 (the reporter's capture on a light yellow theme: sidebar 242/224/155,
/// hovered row 233/216/149, black ≈ 4 %; the plus black 0.50). Cra painted it white with the primary ink,
/// the selected tab's look (#788). That look is right only while ⌘T's bar is open, when Arc draws the row as the
/// open one: the selected tab's fill, shadow and ink (#47).
public struct NewTabRowLook: Equatable {
    public enum Fill: Equatable { case none, hover, selected }
    public enum Ink: Equatable { case primary, secondary }

    public let fill: Fill
    public let ink: Ink
    /// The selected row's shadow.
    public let lifted: Bool

    public init(hovered: Bool, barOpen: Bool) {
        if barOpen {
            (fill, ink, lifted) = (.selected, .primary, true)
        } else {
            (fill, ink, lifted) = (hovered ? .hover : .none, .secondary, false)
        }
    }
}
