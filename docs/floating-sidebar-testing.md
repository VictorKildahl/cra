# Hidden sidebar regression checks

Run `bash scripts/test-floating-sidebar.sh` on macOS. The test compiles the production
floating-sidebar controller with lightweight theme/layout stubs. It uses an offscreen
disposable AppKit panel, does not install the pointer poll, and does not post input events.

Checks cover the shared reveal strip (Arc's: 5 pt inside the window's left edge, 4 pt outside), window bounds, matching leave slack,
held-button retention outside those bounds and dismissal after release,
re-entry during a hide animation, repeated reversals, anchoring while a hide is in
flight, and immediate dismissal while an animated hide is pending. The tests wait
for real AppKit animation completions; they do not establish physical hover behavior.

In an isolated CraDev profile, verify:

- Hide the sidebar with Command-S and move to within 5 pt of the window's left edge,
  or just outside it. It should reveal there, and not 6 pt or more into the window.
- Move beyond the floating sidebar's right edge and quickly return to the gutter,
  repeatedly. The latest reveal should stay visible and interactive.
- Press Command-S while the floating sidebar is entering or leaving. It should
  anchor correctly, without disappearing after the old animation completes.
- The sidebar should stay open while the pointer crosses its right margin and
  should dismiss after leaving the shared 24pt slack or the browser window.
- While holding a mouse button for a window drag, tab reorder or context gesture,
  move beyond those bounds. Automatic hover dismissal must wait until release;
  explicit hide, toggle and window actions must still work.
- Verify both compact and full toolbars. Page clicks outside the gutter and
  full-screen page behavior should remain unchanged.
