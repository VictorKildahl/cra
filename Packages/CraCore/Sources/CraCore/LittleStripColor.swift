import Foundation

/// The page colour a Little Window's strip shows while a page loads: the page's background as soon as the engine
/// reports it, then the reading of the page's top-right corner (ToolbarSampler), which lands about 40 ms later and
/// which a later background report doesn't undo. Without the background the strip kept its default colour over a
/// page that had already painted.
public struct LittleStripColor: Equatable, Sendable {
    /// "#RRGGBB", or "" before the first page has one.
    public private(set) var hex = ""
    private var read = false

    public init() {}

    /// A new page committed: its background may stand in again until its corner is read.
    public mutating func committed() { read = false }

    /// The engine reported the page's background ("" while it has none).
    public mutating func background(_ hex: String) {
        guard !read, HexColor.components(hex) != nil else { return }
        self.hex = hex
    }

    /// The page's top-right corner was read once its load ended.
    public mutating func sampled(_ hex: String) {
        read = true
        self.hex = hex
    }
}
