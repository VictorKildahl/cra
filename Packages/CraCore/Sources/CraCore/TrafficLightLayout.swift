import Foundation

/// Where the browser window's traffic lights go (issue #445). Arc moves the group to its taller
/// title row but keeps the system's spacing between the buttons: on macOS 26 its lights are 23 pt
/// apart from x 13 (AX frames 16 pt wide at 12/35/58, docs/arc-reverse-engineering.md), which is
/// AppKit's own pitch there. macOS 15 spaces them 20 pt apart, so a fixed pitch is wrong on one of
/// them: Cra's 24 pt left Sequoia's buttons 10 pt apart instead of 6.
public enum TrafficLightLayout {
    /// The close button's left edge in the browser window and the floating sidebar.
    public static let leading: Double = 13

    /// The buttons' left edges, given where AppKit put them (close, minimize, zoom, any that
    /// exist): the same gaps, shifted so the first starts at `leading`.
    public static func originsX(system: [Double], leading: Double = leading) -> [Double] {
        guard let first = system.first else { return [] }
        return system.map { leading + $0 - first }
    }
}
