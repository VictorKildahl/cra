import AppKit

// What PictureInPictureChrome.swift takes from CraCEF, for scripts/test-pip-overlay.sh.

@MainActor
public enum CraCEFRuntime {
    /// Over another app's full-screen Space too (#206): nothing to do without Chromium.
    public static func floatOverFullScreenSpaces(_ window: NSWindow) {}
}
