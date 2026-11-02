# Hidden sidebar regression checks

Run `bash scripts/test-floating-sidebar.sh` on macOS. The test compiles the production
floating-sidebar controller with lightweight theme/layout stubs. It uses an offscreen
disposable AppKit panel, does not install the pointer poll, and does not post input events.

Checks cover the shared reveal strip (the 10 pt margin left of the page, plus 4 pt outside the window), window bounds, matching leave slack,
held-button retention outside those bounds and dismissal after release,
only the key window (or one of its own child windows being key) revealing (GitHub #82),
re-entry during a hide animation, repeated reversals, anchoring while a hide is in
flight, and immediate dismissal while an animated hide is pending. The tests wait
for real AppKit animation completions; they do not establish physical hover behavior.

In an isolated CraDev profile, verify:

- Hide the sidebar with Command-S and move into the 10 pt margin left of the page, or
  just outside the window. It should reveal there, and not over the page.
- Move beyond the floating sidebar's right edge and quickly return to the gutter,
  repeatedly. The latest reveal should stay visible and interactive.
- Press Command-S while the floating sidebar is entering or leaving. It should
  anchor correctly, without disappearing after the old animation completes.
- The sidebar should stay open while the pointer crosses its right margin and
  should dismiss after leaving the shared 24pt slack or the browser window.
- While holding a mouse button for a window drag, tab reorder or context gesture,
  move beyond those bounds. Automatic hover dismissal must wait until release;
  explicit hide, toggle and window actions must still work.
- Open a second window over the first, both with the sidebar hidden, and touch the front
  window's left edge. Only the front (key) window's sidebar should come out. As in Arc, a
  window that isn't key stays put even where its edge is uncovered (GitHub #82).
- Verify both compact and full toolbars. Page clicks outside the gutter and
  full-screen page behavior should remain unchanged.
