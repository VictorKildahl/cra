# Window dragging regression checks

Run against a development build with its own `CRA_DATA_DIR`. Do not use the daily
profile for this test.

## Automated checks

```sh
swiftc Sources/Cra/UI/Windows/WindowDragGesture.swift Tests/WindowDragGestureTests.swift -o .build/window-drag-tests
.build/window-drag-tests
swiftc Sources/Cra/UI/Windows/WindowDragGesture.swift Tests/NativeWindowDragTests.swift -o .build/native-window-drag-tests
.build/native-window-drag-tests
```

The first executable checks click jitter, original-event handoff, suppression of the
URL action after a drag, and recovery when AppKit consumes mouse-up. The second
creates offscreen test windows to verify that only a movable top-level browser
window is eligible and that a gesture cannot change its target if the sidebar
reattaches while a press is in flight. It does not post input events or start a
native drag.

## Manual acceptance

Use a mouse or trackpad for these checks. An automation tool that cannot move an
ordinary native macOS title bar cannot establish whether Cra's native drag works.

| Target | Expected behavior |
| --- | --- |
| Empty full-toolbar space | Drag moves the entire browser window; a click does not open the URL editor. |
| Empty attached sidebar header | Drag moves the entire browser window. |
| Displayed toolbar URL or attached compact URL pill | A click edits the URL; dragging moves the browser without opening the URL editor on release. |
| Empty-tab search placeholder | Click opens the command bar; dragging moves the browser. |
| Empty header or toolbar, double-click | Uses the macOS title-bar double-click action. |
| Inactive browser | The first drag works without requiring an activation click first. |
| Navigation, extension and sidebar buttons | Keep their own actions and do not start a window drag. |
| Tab rows | Reordering moves tabs, not the browser window. |
| Floating sidebar header or URL pill | Must **not** move or detach the sidebar panel. Moving the owner from this separate panel is deliberately disabled until a supported owner-event path is verified. Use the main toolbar or top margin to move the browser. |
| Full-screen browser | A URL drag does not attempt to move the window or trigger the URL click action. |

After each window move, verify that the sidebar and Chromium content remain attached
and that buttons and tabs still respond. Test a second display where available.

The floating sidebar is currently a separate child `NSPanel`. Calling
`performDrag(with:)` on it can move it independently even with `isMovable = false`.
All header and URL drag paths therefore validate the target before invoking AppKit;
they do not manufacture a mouse event for another window's coordinate system.
