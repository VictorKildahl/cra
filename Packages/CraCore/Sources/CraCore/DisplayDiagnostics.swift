import Foundation

/// A display as Help ▸ Export Diagnostics lists it. Pages that never paint on macOS 27 (#80)
/// match a Chromium report tied to displays running at different refresh rates, so each
/// display gives its rate and the list says when they differ. No display names: a Sidecar or
/// AirPlay display is named after the user's device.
public struct DisplayDiagnostics: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var scale: Int
    /// The fastest rate, and the slowest a variable-rate (ProMotion) display drops to; the
    /// same on a fixed-rate display.
    public var maximumHz: Int
    public var minimumHz: Int
    public var builtIn: Bool
    /// The one with the menu bar.
    public var main: Bool

    public init(width: Int, height: Int, scale: Int, maximumHz: Int, minimumHz: Int, builtIn: Bool, main: Bool) {
        self.width = width
        self.height = height
        self.scale = scale
        self.maximumHz = maximumHz
        self.minimumHz = minimumHz
        self.builtIn = builtIn
        self.main = main
    }

    /// From NSScreen's refresh intervals (seconds per frame); 0 means unknown.
    public static func hz(interval: Double) -> Int {
        interval > 0 ? Int((1 / interval).rounded()) : 0
    }

    /// "built-in 1800x1169@2x, 120 Hz (variable from 24), main"
    public var line: String {
        var s = "\(builtIn ? "built-in" : "external") \(width)x\(height)@\(scale)x, \(maximumHz) Hz"
        if minimumHz > 0, minimumHz < maximumHz { s += " (variable from \(minimumHz))" }
        if main { s += ", main" }
        return s
    }

    /// Displays that each run at their own top rate.
    public static func mixedRates(_ displays: [DisplayDiagnostics]) -> Bool {
        Set(displays.map(\.maximumHz).filter { $0 > 0 }).count > 1
    }

    /// The summary's "Displays:" block, one display a line.
    public static func summary(_ displays: [DisplayDiagnostics]) -> String {
        guard !displays.isEmpty else { return "Displays: none" }
        let head = "Displays: \(displays.count)\(mixedRates(displays) ? ", mixed refresh rates" : "")"
        return ([head] + displays.map { "  " + $0.line }).joined(separator: "\n")
    }
}
