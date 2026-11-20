import Foundation

/// How many closed tabs the archive keeps (Library ▸ Archived Tabs, ⇧⌘T, ⌘T). It kept 2,000 and dropped
/// the oldest without a word: one Clear Today on a 5,000-tab Today lost 3,000 of them (GitHub #614).
/// 10,000 is about 4.5 MB of archive.json (≈450 bytes an entry), written off the main thread after
/// changes and read once at launch.
public enum ArchiveLimit {
    public static let kept = 10_000

    /// How many of the oldest entries go when the archive holds `count`.
    public static func overflow(_ count: Int) -> Int { max(0, count - kept) }
}
