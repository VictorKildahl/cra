import AppKit

// What the Picture in Picture files call elsewhere in the app, for scripts/test-pip-overlay.sh.

enum CraLog {
    static func note(_ message: String) {}
}

/// The test's data folder (CRA_DATA_DIR, set by the script), where the overlay keeps the frame
/// it leaves the window at (`PictureInPictureChrome.remember`).
enum AppPaths {
    static func file(_ name: String) -> URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(name)
    }
}

final class ArcTooltipAnchorView: NSView {
    var text = ""
    static func attach(to control: NSView, help: String) -> ArcTooltipAnchorView { ArcTooltipAnchorView() }
}

/// A test copy that stays behind the user's apps (CRA_TEST_BACKGROUND): this harness's windows don't.
enum HitchMonitor {
    static let background = false
}
