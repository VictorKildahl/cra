import Foundation

/// Arc's rules for which profile a space is on (Arc 1.171, watched in a fresh copy, 3 Nov 2026).
/// A space never gets cookies of its own by itself: every space is on Default until one is moved
/// onto another profile, and spaces on the same profile share their sign-ins.
public enum SpaceProfiles {
    /// New Space… preselects the profile of the space it was opened from ("Profile, Work" from a
    /// space on Work, "Profile, Default" from one on Default). A profile that is gone is Default.
    public static func forNewSpace(from focused: Space?, profiles: [BrowserProfile]) -> UUID? {
        guard let id = focused?.profileID, profiles.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}
