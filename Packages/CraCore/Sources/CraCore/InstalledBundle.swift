import Foundation

/// Cra.app replaced on disk while this copy of it runs: `brew upgrade --greedy`, `brew reinstall`, or a newer
/// copy put over it by hand. Sparkle never does this (it installs once Cra has quit). Chrome starts every new
/// page's process from the bundle on disk, and Cra keeps Chrome's code sign clone off (engine -15,
/// crash-code-sign-clone-cleanup-after-update), so once the bundle on disk is a release on another Chrome, its
/// engine's `Versions/<chrome>` folder is gone and every new page ends in "Aw, Snap!" (launch failed) until Cra
/// restarts. Chrome says "Relaunch to update" for this; Cra says it with Arc's update banner, "An update is
/// ready! Click to restart", as it does for an update Sparkle downloaded.
public enum InstalledBundle {
    /// A bundle's CFBundleShortVersionString and CFBundleVersion.
    public struct Version: Equatable, Sendable {
        public let short: String
        public let build: String

        public init(short: String, build: String) {
            self.short = short
            self.build = build
        }

        /// From an Info.plist's bytes; nil when they aren't one or lack either key (a bundle half copied).
        public init?(infoPlist data: Data) {
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let short = plist["CFBundleShortVersionString"] as? String, !short.isEmpty,
                  let build = plist["CFBundleVersion"] as? String, !build.isEmpty
            else { return nil }
            self.init(short: short, build: build)
        }
    }

    /// The version to offer a restart into: the one on disk once it is another build than the one running.
    /// Nil while it is the same, and while there is none to read (the bundle moved away, deleted or mid-copy),
    /// since restarting then would start nothing.
    public static func replacement(running: Version, onDisk: Version?) -> String? {
        guard let onDisk, onDisk != running else { return nil }
        return onDisk.short
    }
}
