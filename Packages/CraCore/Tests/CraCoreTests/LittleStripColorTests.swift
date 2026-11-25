import CraCore
import Testing

/// The Little Window's strip takes the page's colour as soon as the page has painted.
struct LittleStripColorTests {
    /// The background stands in from the moment the engine reports it, before the corner is read.
    @Test
    func theBackgroundStandsInUntilTheCornerIsRead() {
        var color = LittleStripColor()
        color.committed()
        color.background("")
        #expect(color.hex == "")
        color.background("#D32F2F")
        #expect(color.hex == "#D32F2F")
        color.sampled("#1A73E8")
        #expect(color.hex == "#1A73E8")
    }

    /// A background reported after the reading (a page that changes its background) leaves the reading.
    @Test
    func theReadingIsKeptUntilTheNextPage() {
        var color = LittleStripColor()
        color.sampled("#1A73E8")
        color.background("#FFFFFF")
        #expect(color.hex == "#1A73E8")
        color.committed()
        color.background("#FFFFFF")
        #expect(color.hex == "#FFFFFF")
    }
}
