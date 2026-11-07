import CoreGraphics
import CraCore
import Testing

/// The Boost code panel's eyedropper (Arc 1.172.1's selector picker).
struct BoostPickerTests {
    @Test func readsTheHeldClick() throws {
        let json = ##"{"this":"#a","related":"li.item","relatedCount":3,"x":40,"y":10,"viewportWidth":800}"##
        let pick = try #require(BoostPicker.parse(json))
        #expect(pick == BoostPicker.Pick(this: "#a", related: "li.item", relatedCount: 3, x: 40, y: 10, viewportWidth: 800))
        #expect(BoostPicker.parse("") == nil, "no click yet")
        #expect(BoostPicker.parse("null") == nil)
    }

    @Test func arcsMenuInArcsOrder() {
        #expect(BoostPicker.Action.allCases.map(\.title) == ["Copy selector for this", "Copy selector for related", "Zap all related elements"])
    }

    @Test func relatedNeedsSomethingLikeIt() {
        let alone = BoostPicker.Pick(this: "#solo", related: "#solo", relatedCount: 1, x: 0, y: 0, viewportWidth: 100)
        let many = BoostPicker.Pick(this: "#a", related: "li.item", relatedCount: 3, x: 0, y: 0, viewportWidth: 100)
        #expect(BoostPicker.Action.allCases.map { $0.isEnabled(for: alone) } == [true, false, false])
        #expect(BoostPicker.Action.allCases.allSatisfy { $0.isEnabled(for: many) })
        #expect(BoostPicker.Action.copyThis.selector(for: many) == "#a")
        #expect(BoostPicker.Action.zapRelated.selector(for: many) == "li.item")
    }

    @Test func theMenuOpensWhereTheClickWas() {
        // A page zoomed to 125 %: 800 CSS px across a 1000 pt view.
        let pick = BoostPicker.Pick(this: "a", related: "a", relatedCount: 1, x: 80, y: 40, viewportWidth: 800)
        #expect(pick.point(inViewWidth: 1000) == CGPoint(x: 100, y: 50))
        let unknown = BoostPicker.Pick(this: "a", related: "a", relatedCount: 1, x: 80, y: 40, viewportWidth: 0)
        #expect(unknown.point(inViewWidth: 1000) == CGPoint(x: 80, y: 40))
    }
}
