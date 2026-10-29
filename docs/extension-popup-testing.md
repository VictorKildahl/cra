# Extension popup regression checks

Run `scripts/test-extension-popup.sh`. It needs Swift and Node.js, but no Chromium
download, signed app, browser profile, or password vault. The checks cover:

- Popup growth preserves the button's right and bottom anchor; display-edge clamping
  works with negative screen coordinates and keeps oversized windows reachable.
- A drag is local to the current opening; a fresh opening returns to its anchor.
- A cancellation candidate must be a new target for the requested extension and popup
  path. A fragment route does not make it a different popup.
- URL matching alone cannot authorize closing: the cleanup expression checks the
  target's extension origin and Chrome's `getViews({type: 'popup'})` membership. A normal
  extension tab with the same URL remains open. Missing APIs fail closed.
- A real scheduled reply timeout completes once. Late and duplicate replies cannot
  resume a continuation twice, successful calls cancel their deadline, and late attach
  cleanup runs once.

## Runtime matrix

Use an isolated `CRA_DATA_DIR` and a disposable extension fixture before testing a
password manager. Unit checks do not establish that Chromium's actual popup lifecycle
or native window ownership behaves correctly.

1. Right-click and Control-click a pinned extension in both the full toolbar and compact
   sidebar. Choose a monochrome or custom icon and verify both surfaces render it.
2. Open from different points inside the button, the Extensions menu, and the extension's
   shortcut. The right edge should use the same button position.
3. Move or resize the browser while the popup is loading. On appearance it should use
   current geometry. Moving/resizing after presentation should dismiss it.
4. Drag the popup, dismiss it, and reopen it. It should start at the button again. Allow
   the popup's page to grow and verify the right edge stays fixed unless a screen edge
   requires clamping.
5. Change tabs, navigate the source tab, or close its window while the popup is loading.
   The request must not present a popup for an obsolete context. Keep a normal extension
   tab with the same URL open during cancellation; that tab must remain open.
6. Open two extensions rapidly, repeat a click during startup, use multiple browser
   windows/displays, and test an action without a popup. Check that the request ends and
   no unrelated native window is reparented.
7. Test no selected tab separately: the existing fallback is an extension page, which
   does not establish the same `activeTab` behavior as Chrome's genuine action popup.

## Limits

The shell still discovers popup windows using a native-window heuristic; it does not
have a protocol-proven target-to-NSWindow mapping. The guarded cleanup only closes
verified extension popup targets. Dynamic `action.setPopup()` paths, same-URL document
reloads, and an engine-created popup appearing after a request has expired need further
runtime coverage and stronger ownership hooks.

Reply deadlines and the overall startup deadline run on the main queue. They bound
missing asynchronous replies while that queue runs; they cannot interrupt a synchronous
pipe write or other main-thread block in the CEF bridge. The new CEF codecs3 build fixes
the upstream two-second browser-info wait independently of these shell changes.
