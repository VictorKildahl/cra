import Foundation

/// Arc's ⌘E, "Open pinned extensions picker." (#709): held ⌘ and E opens the Site Control Center with its first
/// extension tile ringed; each E after it, ⌘ still held, rings the next tile in the grid's order (pinned in toolbar
/// order, then the rest by name); letting go of ⌘ closes the Site Control Center and opens the ringed extension's
/// popup, as a click on its tile does. Measured in Arc 1.172 (23 Nov 2026, held ⌘ with taps 0.25 s apart: 1st,
/// 2nd, 3rd tile; one press and let go: the first extension's popup). Past the last tile Cra starts at the first
/// again. Opened another way (the sliders button, the menu, the command bar), no tile is ringed.
public struct ExtensionPicker: Equatable, Sendable {
    /// The presses of the shortcut so far, the opening one included.
    public private(set) var presses = 1

    public init() {}

    public mutating func press() {
        presses += 1
    }

    /// The ringed tile among `count` extensions, nil when there are none.
    public func picked(among count: Int) -> Int? {
        count > 0 ? (presses - 1) % count : nil
    }

    /// What a press of the Open Extensions shortcut does.
    public enum Press: Equatable, Sendable {
        /// Opens the Site Control Center and rings the first extension (⌘ held: the picker).
        case openPicking
        /// Rings the next extension (⌘ still held since the opening press).
        case step
        /// Opens (or closes) the Site Control Center as its button does.
        case toggle
    }

    /// `commandHeld`: the press came from the keyboard with ⌘ down. `picking`: a picker is up, ⌘ not let go since.
    public static func press(commandHeld: Bool, picking: Bool) -> Press {
        if picking { return .step }
        return commandHeld ? .openPicking : .toggle
    }
}
