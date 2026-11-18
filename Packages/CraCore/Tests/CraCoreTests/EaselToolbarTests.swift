import CoreGraphics
import CraCore
import Testing

/// Arc's Easel toolbar (Arc 1.173.1, 17 Nov 2026): the tools' keys, where the buttons sit and
/// what each shows under the pointer.
struct EaselToolbarTests {
    @Test func eachToolHasArcsKey() {
        #expect(Easel.Tool.allCases.map(\.key) == ["v", "i", "t", "o", "r", "a", "p"])
        #expect(Easel.Tool.picked(byKey: "r") == .rectangle)
        #expect(Easel.Tool.picked(byKey: "O") == .ellipse)
        #expect(Easel.Tool.picked(byKey: "v") == .pointer)
        #expect(Easel.Tool.picked(byKey: "p") == .freehand)
    }

    @Test func aShortcutOrAnotherKeyPicksNoTool() {
        #expect(Easel.Tool.picked(byKey: "r", command: true) == nil)
        #expect(Easel.Tool.picked(byKey: "a", control: true) == nil)
        #expect(Easel.Tool.picked(byKey: "p", option: true) == nil)
        #expect(Easel.Tool.picked(byKey: "x") == nil)
        #expect(Easel.Tool.picked(byKey: "") == nil && Easel.Tool.picked(byKey: "rr") == nil)
    }

    @Test func thePointersButtonShowsNoLetter() {
        #expect(Easel.Tool.pointer.keyHint == nil)
        #expect(Easel.Tool.freehand.keyHint == "p")
    }

    @Test func buttonsSitWhereArcsDo() {
        typealias L = EaselToolbarLayout
        #expect(L.rect(of: .tool(.pointer)) == CGRect(x: 4, y: 4, width: 36, height: 36))
        #expect(L.rect(of: .tool(.image)).minX == 42)
        #expect(L.rect(of: .tool(.freehand)) == CGRect(x: 232, y: 4, width: 36, height: 36))
        // Duplicate after a 5 pt gap with the line in its middle; 4 pt to the bar's end.
        #expect(L.rect(of: .duplicate).minX == 273)
        #expect(L.divider == CGRect(x: 270, y: 4, width: 1, height: 36))
        #expect(L.width == 313 && L.height == 44)
    }

    @Test func aPointFindsItsButton() {
        typealias L = EaselToolbarLayout
        #expect(L.item(at: CGPoint(x: 20, y: 20)) == .tool(.pointer))
        #expect(L.item(at: CGPoint(x: 250, y: 20)) == .tool(.freehand))
        #expect(L.item(at: CGPoint(x: 290, y: 20)) == .duplicate)
        // Between two buttons, in the divider's gap and on the bar's rim: nothing.
        #expect(L.item(at: CGPoint(x: 41, y: 20)) == nil)
        #expect(L.item(at: CGPoint(x: 270.5, y: 20)) == nil)
        #expect(L.item(at: CGPoint(x: 20, y: 2)) == nil)
    }

    @Test func aButtonUnderThePointerShowsItsFillAndLetter() {
        typealias L = EaselToolbarLayout
        let over = L.look(of: .tool(.freehand), picked: .pointer, hovered: .tool(.freehand))
        #expect(over == L.Look(fill: .hovered, hint: "p"))
        #expect(L.look(of: .tool(.arrow), picked: .pointer, hovered: .tool(.freehand)) == L.Look(fill: .none, hint: nil))
        #expect(L.look(of: .duplicate, picked: .pointer, hovered: .duplicate) == L.Look(fill: .hovered, hint: nil))
        #expect(L.look(of: .duplicate, picked: .pointer, hovered: nil) == L.Look(fill: .none, hint: nil))
    }

    @Test func thePickedToolKeepsItsFillAndShowsItsLetter() {
        typealias L = EaselToolbarLayout
        #expect(L.look(of: .tool(.rectangle), picked: .rectangle, hovered: nil) == L.Look(fill: .picked, hint: "r"))
        #expect(L.look(of: .tool(.rectangle), picked: .rectangle, hovered: .tool(.rectangle)) == L.Look(fill: .picked, hint: "r"))
        // The pointer, picked or under the pointer, has no letter.
        #expect(L.look(of: .tool(.pointer), picked: .pointer, hovered: nil) == L.Look(fill: .picked, hint: nil))
        #expect(L.look(of: .tool(.pointer), picked: .rectangle, hovered: .tool(.pointer)) == L.Look(fill: .hovered, hint: nil))
    }
}
