import CoreGraphics

/// How many pinned extensions the toolbar hides so the address keeps its whole width. Arc
/// 1.171's toolbar works out `numberOfExtensionsThatFit` (with `urlDomainHasRoom`) and drops
/// pins from the front of the list, the ones farthest from its right end: with ten pins it
/// showed the last seven in a 1100 pt window and the last two at 800 pt, the URL whole and
/// centred both times (live, 4 Nov 2026). The hidden ones stay in the Extensions menu.
public enum ToolbarExtensionFit {
    /// `widths`: the pinned buttons, in pin order. `room(hiddenWidth)`: the space the address
    /// gets once that much of the pins' width is gone. `needed`: the address's whole width.
    public static func hiddenCount(widths: [CGFloat], needed: CGFloat, room: (CGFloat) -> CGFloat) -> Int {
        var hidden = 0, freed: CGFloat = 0
        while hidden < widths.count, room(freed) < needed {
            freed += widths[hidden]
            hidden += 1
        }
        return hidden
    }
}

/// What a narrow toolbar leaves out so the address keeps room, after Arc 1.171's `…HasRoom`
/// flags (`numberOfExtensionsThatFit`, `refreshHasRoom`, `settingsHasRoom`). Measured live on
/// two- and three-pane splits (GitHub #178, 4 Nov 2026): ↻ stays at 387–392 pt panes and is gone
/// at 350–359 pt, with the domain cut short; the Site Control Center stays down to 325 pt and is
/// gone at 292 pt (and at 215 pt, Arc 1.170). So the pins go first, from the front; then ↻ while
/// the address still doesn't fit whole; the sliders only once the address would be squeezed
/// below `minimum`.
public enum ToolbarRoom {
    public struct Plan: Equatable, Sendable {
        public var hiddenPins: Int
        public var hidesReload: Bool
        public var hidesSettings: Bool

        public init(hiddenPins: Int = 0, hidesReload: Bool = false, hidesSettings: Bool = false) {
            (self.hiddenPins, self.hidesReload, self.hidesSettings) = (hiddenPins, hidesReload, hidesSettings)
        }
    }

    /// Cra's address room at Arc's last pane with the sliders (325 pt: 114) and its first without
    /// (292 pt: 82), split down the middle.
    public static let minimumAddress: CGFloat = 100

    /// `room`: the address's space with every button shown; each hidden button adds its width.
    /// `reload` / `settings`: those buttons' widths, nil when the bar has none.
    public static func plan(pins: [CGFloat], reload: CGFloat?, settings: CGFloat?, needed: CGFloat,
                            room: CGFloat, minimum: CGFloat = minimumAddress) -> Plan {
        var plan = Plan()
        plan.hiddenPins = ToolbarExtensionFit.hiddenCount(widths: pins, needed: needed) { room + $0 }
        var space = room + pins.prefix(plan.hiddenPins).reduce(0, +)
        if space < needed, let reload {
            plan.hidesReload = true
            space += reload
        }
        if space < min(needed, minimum), let settings {
            plan.hidesSettings = true
        }
        return plan
    }
}
