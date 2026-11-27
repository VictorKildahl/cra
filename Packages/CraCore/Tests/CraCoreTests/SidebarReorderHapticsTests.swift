import CraCore
import Testing

/// The tick while a sidebar row is dragged (issue #883): one each time the drag is offered a new
/// place, whatever kind of row it is, as in Arc.
struct SidebarReorderHapticsTests {
    /// Offers the places in turn; returns how many ticks they asked for.
    private func ticks(_ places: [String?], from start: String? = nil) -> Int {
        var haptics = SidebarReorderHaptics<String>(place: start)
        return places.filter { haptics.offer($0) }.count
    }

    /// A folder dragged down past two rows is offered two new slots: two ticks. Before #883 only a
    /// tab offering to combine into a split ticked, so a folder was silent.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/883"))
    func eachNewPlaceTicks() {
        #expect(ticks(["after stay", "after other"]) == 2)
        #expect(ticks(["into Reading", "split with stay", "after stay"]) == 3)
    }

    /// Moving within the same place (the pointer moves inside one row's half) doesn't tick again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/883"))
    func theSamePlaceTicksOnce() {
        #expect(ticks(["after stay", "after stay", "after stay"]) == 1)
        #expect(ticks(["after stay"], from: "after stay") == 0)
    }

    /// Over its own place the row has nowhere to go: no tick, and back to a place ticks again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/883"))
    func nowhereIsSilentAndComingBackTicks() {
        #expect(ticks([nil, nil]) == 0)
        #expect(ticks(["after stay", nil, "after stay"]) == 2)
    }
}
