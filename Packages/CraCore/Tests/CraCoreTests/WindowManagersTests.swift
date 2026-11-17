import CraCore
import Testing

/// X, 17 Nov 2026: Raycast's window management shortcuts resized other browsers but not Little
/// Cra, a non-activating panel that AppKit reports as a system dialog.
struct WindowManagersTests {
    @Test func windowManagersHandleStandardWindowsTheyCanMoveAndResize() {
        // The browser window, and a Little Window.
        #expect(WindowManagers.handles(.init(subrole: "AXStandardWindow", canMove: true, canResize: true)))
        // What AppKit says a non-activating panel is, the Little Window before the fix.
        #expect(!WindowManagers.handles(.init(subrole: "AXSystemDialog", canMove: true, canResize: true)))
        #expect(!WindowManagers.handles(.init(subrole: "AXDialog", canMove: true, canResize: true)))
        #expect(!WindowManagers.handles(.init(subrole: "AXFloatingWindow", canMove: true, canResize: true)))
        // A window of a fixed size (the empty Little Window card) is not one to tile.
        #expect(!WindowManagers.handles(.init(subrole: "AXStandardWindow", canMove: true, canResize: false)))
        // A docked page or sidebar window is a group inside its window (#391).
        #expect(!WindowManagers.handles(.init(role: "AXGroup", subrole: nil, canMove: true, canResize: true)))
    }
}
