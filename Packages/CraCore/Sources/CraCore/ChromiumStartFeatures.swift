import Foundation

/// Chromium features Cra turns on at start for the Mac it runs on, beside the engine's own list (bridge.mm).
public enum ChromiumStartFeatures {
    /// Chrome's emergency shutoff for its own window occlusion checker (WindowOcclusionCheckerMac): with it, a page is
    /// hidden only when macOS says its window is out of sight. On macOS 27 the checker leaves windows' pages white or
    /// not drawing after a window comes forward until a resize, a tab switch or a reload (crbug.com/448103577: a macOS
    /// 27.3 user's white pages stopped 10 times out of 10 with this feature on; Chrome switches it on by field trial,
    /// which Cra doesn't get). Cra's Little Windows came up white the same way on macOS 27.2.1 (GitHub #848).
    public static let occlusionShutoff = "MacOcclusionForceShutoff"

    /// The features for a Mac on `macOSMajor` (26, 27, …). macOS 26 draws as it should with the checker, which also
    /// saves the work of pages fully covered by Cra's own windows, so it keeps it.
    public static func enabled(macOSMajor: Int) -> [String] {
        macOSMajor >= 27 ? [occlusionShutoff] : []
    }

    /// The macOS major version a scenario says it is (`CRA_MACOS_MAJOR`), else the Mac's own.
    public static func macOSMajor(environment: [String: String], actual: Int) -> Int {
        environment["CRA_MACOS_MAJOR"].flatMap { Int($0) } ?? actual
    }

    /// The major version in `kern.osproductversion` ("27.2.1" → 27), which Chromium reads too (base::mac::MacOSVersion):
    /// an app linked against an older SDK is told "16" for macOS 26 by other APIs.
    public static func major(productVersion: String) -> Int? {
        productVersion.split(separator: ".").first.flatMap { Int($0) }
    }
}
