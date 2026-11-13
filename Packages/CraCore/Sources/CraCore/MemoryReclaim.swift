import Foundation

/// Closing tabs leaves Chromium's browser process holding the memory they freed: its allocator
/// keeps the empty pages for reuse (renderers give theirs back when they go to the background,
/// the browser process never does). Once the tab count has settled, Cra asks Chromium to return
/// them (Cra.reclaimMemory), but not while the user is typing or clicking: the reclaim walks
/// every partition under its locks.
public enum MemoryReclaim {
    /// Quiet time after the last page closed before reclaiming.
    public static let settle: TimeInterval = 5
    /// Input this recent puts the reclaim off by `retry`.
    public static let quietInput: TimeInterval = 1
    public static let retry: TimeInterval = 2

    public static func runsNow(secondsSinceInput: TimeInterval) -> Bool {
        secondsSinceInput >= quietInput
    }
}
