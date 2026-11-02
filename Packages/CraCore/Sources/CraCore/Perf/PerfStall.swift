import Foundation

/// A main run-loop pass long enough to notice. The mode tells a freeze from a loop the user is
/// in on purpose: a menu held open or a window dragged runs in the event-tracking mode, an
/// alert in the modal one, and neither is a frozen Cra however long it lasts.
public struct PerfStall: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 250 ms or more: a dropped beat in a video, a click that lands late.
        case stall
        /// 1 s or more: the window visibly stops.
        case long
        /// 2 s or more: the watchdog wrote a hang file while it lasted.
        case hang
    }

    /// Seconds since the session started.
    public var at: Double
    public var ms: Double
    public var kind: Kind
    /// The run-loop mode, shortened: `default`, `tracking`, `modal`, `launch` (Cra starting up,
    /// before its run loop first waits) or the mode's own name.
    public var mode: String
    /// Counted as a freeze: not a tracking or modal loop, nor start-up.
    public var freeze: Bool
    /// What Cra did just before (HitchMonitor's marks), newest last.
    public var marks: [String]
    /// The host of the page on screen, nil for incognito or none.
    public var site: String?

    public init(at: Double, ms: Double, kind: Kind, mode: String, freeze: Bool, marks: [String], site: String?) {
        self.at = at
        self.ms = ms
        self.kind = kind
        self.mode = mode
        self.freeze = freeze
        self.marks = marks
        self.site = site
    }
}

/// When a main-loop pass counts, and as what.
public struct PerfStallPolicy: Equatable, Sendable {
    public var stallMs: Double = 250
    public var longMs: Double = 1000
    public var hangMs: Double = 2000
    /// Marks this close before the end of a stall are its breadcrumbs.
    public var breadcrumbWindow: Double = 5
    public var breadcrumbLimit = 8

    public init() {}

    public func kind(ms: Double) -> PerfStall.Kind? {
        if ms >= hangMs { return .hang }
        if ms >= longMs { return .long }
        if ms >= stallMs { return .stall }
        return nil
    }

    /// AppKit's mode names, as CFRunLoopCopyCurrentMode returns them.
    public static func shortMode(_ name: String) -> String {
        switch name {
        case "kCFRunLoopDefaultMode": return "default"
        case "NSEventTrackingRunLoopMode": return "tracking"
        case "NSModalPanelRunLoopMode": return "modal"
        case "kCFRunLoopCommonModes": return "common"
        default: return name
        }
    }

    /// A menu, a drag or a modal alert keeps the run loop in its own mode on purpose; start-up has
    /// its own phases (perf.json `startup`).
    public static func isFreeze(mode: String) -> Bool { !["tracking", "modal", "launch"].contains(mode) }

    /// The stall a pass of `ms` ending at `at` makes, with the marks of the seconds before it.
    public func stall(at: Double, ms: Double, mode: String, marks: [PerfMark], site: String?) -> PerfStall? {
        guard let kind = kind(ms: ms) else { return nil }
        let short = Self.shortMode(mode)
        let since = at - ms / 1000 - breadcrumbWindow
        let crumbs = marks.filter { $0.at >= since && $0.at <= at }.suffix(breadcrumbLimit).map(\.label)
        return PerfStall(at: at, ms: ms, kind: kind, mode: short, freeze: Self.isFreeze(mode: short), marks: Array(crumbs), site: site)
    }
}

/// A breadcrumb: something Cra did, by name (HitchMonitor.mark and the scripted commands).
public struct PerfMark: Codable, Equatable, Sendable {
    public var at: Double
    public var label: String

    public init(at: Double, label: String) {
        self.at = at
        self.label = Self.clean(label)
    }

    /// Never an address: a scripted `cra://open?url=…` keeps `cra://open`, and a label is short.
    public static func clean(_ label: String) -> String {
        let cut = label.firstIndex(where: { $0 == "?" || $0 == "\n" }).map { String(label[..<$0]) } ?? label
        return String(cut.prefix(120))
    }
}
