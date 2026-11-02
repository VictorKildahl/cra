import Foundation

/// Which browser window a page sent to a space opens in: a Little Window's "Open in"
/// pick or ⌃⌘N (GitHub #92).
///
/// Arc 1.171 (2 Nov, two windows on Victor and JYSK, the Victor one used last): picking
/// JYSK in Little Arc's spaces popover opened the page in the JYSK window and brought that
/// window forward, and the Victor window kept its space. An offline copy with three windows
/// showed the rest: with no window on the space, the window in use last switches to it; with
/// two on it, the one in use last wins, else the frontmost; a minimized one is unminimized.
public enum SpaceWindow {
    /// `windows`: the normal (not incognito) browser windows, front to back, minimized ones
    /// included, each with the space it shows. `lastUsed`: the normal window in use last.
    public static func window(for space: UUID, windows: [(id: UUID, space: UUID)], lastUsed: UUID) -> UUID {
        if windows.contains(where: { $0.id == lastUsed && $0.space == space }) { return lastUsed }
        return windows.first { $0.space == space }?.id ?? lastUsed
    }
}
