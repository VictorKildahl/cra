import CoreGraphics
import Foundation

/// Eligibility and particle geometry for music notes above playing favorites.
/// Site list and emitter values: Arc 1.172.1, 10 Nov 2026; see
/// docs/arc-reverse-engineering.md, "Music notes on a playing favorite".
public enum MusicNotes {
    /// Music hosts and their subdomains; ordinary youtube.com videos are excluded.
    public static let sites = ["bandcamp.com", "music.apple.com", "music.youtube.com", "nts.live",
                               "pandora.com", "soundcloud.com", "spotify.com", "tidal.com"]

    public static func isMusicSite(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased(), !host.isEmpty else { return false }
        return sites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Use immediate sound state so notes stop before the speaker's 2 s audible hold ends.
    public static func plays(url: String, soundPlaying: Bool, muted: Bool) -> Bool {
        soundPlaying && !muted && isMusicSite(url)
    }

    // MARK: The emitter

    public enum Shape: Sendable, CaseIterable {
        /// One eighth note.
        case single
        /// Two notes under a beam.
        case beamed
    }

    /// Particles emitted per second for each note shape.
    public static func birthRate(_ shape: Shape) -> Float {
        switch shape {
        case .single: 1.4
        case .beamed: 1
        }
    }

    /// Notes grow as they rise and fade over their lifetime.
    public static let lifetime: Float = 2
    public static let scale: CGFloat = 0
    public static let scaleRange: CGFloat = 0.2
    public static let scaleSpeed: CGFloat = 1
    public static let alphaRange: Float = 0.15
    public static let alphaSpeed: Float = -0.5
    /// Straight up at 20 pt a second (±5), within a 60° cone.
    public static let velocity: CGFloat = 20
    public static let velocityRange: CGFloat = 5
    public static let emissionLongitude: CGFloat = .pi / 2
    public static let emissionRange: CGFloat = .pi / 3

    /// A fixed-size bitmap keeps small notes sharp and lets growing notes soften at 2x.
    public static let spritePixels = 12

    /// Keep the drawn notes softer on light tiles: black at 30 %, white at 80 % on dark tiles.
    /// The light tint is fitted to the contributor's comparison (docs/arc-reverse-engineering.md).
    public static func ink(dark: Bool) -> (white: CGFloat, alpha: CGFloat) {
        dark ? (1, 0.8) : (0, 0.3)
    }

    // MARK: Placement

    /// Notes are born inside a circle of this radius.
    public static let emitterRadius: CGFloat = 6
    /// The circle's centre is this far above the icon's: on the top edge of a 16 pt icon.
    public static let lift: CGFloat = 8
    /// The notes' view reaches this far past the tile on every side.
    public static let reach: CGFloat = 30
    /// Notes over the top row are cut where the URL field ends, this far above the tiles.
    public static let overhang: CGFloat = 8

    /// The notes' view over a tile's cell, the emitter at its centre. Top-left coordinates.
    public static func field(over cell: CGRect) -> CGRect {
        cell.insetBy(dx: -reach, dy: -reach).offsetBy(dx: 0, dy: -lift)
    }
}
