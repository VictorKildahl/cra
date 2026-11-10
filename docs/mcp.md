# Agents in Cra (MCP)

Cra can let the agents you already run, like Claude Code or Cursor, use the browser as it is:
your tabs, spaces and signed-in sessions, through the
[Model Context Protocol](https://modelcontextprotocol.io). Cra runs no model and calls no AI
service itself. The agent you connect reads what it opens, under that agent's own data rules.

It is off until you turn it on: **Settings ▸ Advanced ▸ Allow local agents to control Cra**,
then **Copy MCP Configuration** and add that entry to the agent's MCP settings. For Claude Code:

    claude mcp add cra -- "/Applications/Cra.app/Contents/MacOS/Cra" --mcp "$HOME/Library/Application Support/Cra/mcp.sock"

Keep Cra running. Copy the configuration again after moving the app or changing profiles.
CraDev has its own profile and socket.

The first time an agent connects, Cra asks: **Let "Claude Code" use Cra?** with the app it runs
in. Until you answer, its calls are refused with a message to wait. Cra remembers the answer per
agent (its name and the code-signing team of the program that started it, so an update doesn't
ask again) in `mcp.json` in the data folder. Settings ▸ Advanced lists the agents you answered;
**Forget** asks again next time and closes the agent's open connections.

## How an agent works in Cra

An agent works next to you, not on your screen. Every tool works on hidden tabs, in covered
or minimised windows and with Cra in the background:

- `tab_open` opens a tab like a ⌘-clicked link: in the today list of the current space (or the
  space named by `space`), loading, unread and not selected. Cra doesn't come forward.
  `select=true` also shows it in its window; `activate=true` brings Cra to the front.
- The first time a client works in a page, Cra turns on DevTools focus emulation for it, so the
  page runs as a focused, visible page: input lands, animations run, and screenshots work.
  When the last client disconnects (or MCP is turned off) those pages go back to normal.
- A sleeping tab wakes in the background when a tool needs it, and a tab an agent works in
  counts as used, so tab sleeping and freezing wait as they would after you looked at it.
- `tabs_list` lists your tabs in sidebar order with their space, section (favorites, pinned,
  today) and folder. `active` marks the tab on screen in the window you used last;
  `selected` marks each window's shown tab.
- `tab_close` closes today tabs, as ⌘W does (Reopen Closed Tab brings one back). Pinned tabs,
  favorites and tabs in a split stay.

Private tabs and Little Windows are never listed or reachable, even with a known ID. Agents
work only in web pages (http and https): Chrome's settings and password pages, extension pages,
DevTools and local files are listed (`webPage: false`) but refused, and clicks or typing into an
extension's frame inside a page (a password manager's menu) are refused too.

## Tools

| Tool | What it does |
| --- | --- |
| `tabs_list` | Your tabs in sidebar order, plus this connection's windowless pages |
| `tab_open` | Open an HTTP(S) page in the background (`space`, `select`, `activate`, `windowless`) |
| `tab_show` | Select a tab in its window; `activate=true` also brings Cra forward |
| `tab_close` | Close a today tab |
| `page_read` | Visible text in pages of up to 20,000 UTF-16 units, and up to 50 links |
| `page_snapshot` | Accessibility tree with stable refs, including same-site iframes and open shadow roots; `interactive` and `query` narrow it |
| `page_screenshot` | Viewport JPEG (at most 1280 px) of any tab, hidden ones included, with its size for x/y |
| `page_navigate`, `page_history`, `page_wait` | Navigate, back/forward/reload, wait for a URL, text or element state |
| `page_click` | Click a ref, selector or x/y; `button` left/right/middle, `clickCount` 1–3, `modifiers` |
| `page_hover`, `page_scroll` | Pointer moves and wheel scrolling at a ref, selector or x/y |
| `page_type` | Type text, into a target or wherever focus is (rich editors, iframes) |
| `page_fill` | Replace a field's or editor's content |
| `page_press` | A named key or any one character with modifiers, so ⌘K, ⌘A, ⇧Tab |
| `page_select` | Choose a `<select>` option by value or by its visible label |
| `page_dialog` | Accept or dismiss an alert, confirm, prompt or Leave Site? |
| `page_console` | Console messages, uncaught exceptions and browser messages |
| `page_drag`, `page_upload` | Native HTML or pointer drags; choose files for a file input |
| `page_pdf` | Print to a new private PDF in the profile's `mcp-exports` folder |
| `page_download`, `download_status`, `download_cancel` | Signed-in downloads in a windowless tab |
| `page_evaluate` | JavaScript, only with **Let agents run JavaScript in pages** on (off by default) |

Arguments are checked before anything happens, and a refused call says why (`page_click needs
a target: ref, selector or x/y.`).

### Finding things

`page_snapshot` returns the page's elements with refs. A ref points at one node and never moves
to another: if the page replaces the node, the ref is stale and the tool says so; take a new
snapshot. Big pages are cut off at 600 elements; `interactive=true` keeps only controls and
headings, and `query` keeps elements whose name has those words (or whose role is that word).
Refs work for nodes in open shadow roots and in iframes from the same site as the page.

Anything else (a cross-site iframe, a canvas, a custom widget without a name) is reached by
position: take `page_screenshot`, then pass `x`/`y` in pixels of that image to `page_click`,
`page_hover` or `page_scroll`. One image pixel is one CSS pixel unless the viewport is wider
than 1280; the screenshot's text part says the scale. A click by position reports what was
there (`target`) and the main document's trusted events; events inside a cross-site frame
can't be seen, so the result says to check with a screenshot.

Editable values and their accessibility children are left out of snapshots, and point
descriptions never include a field's value. Labels and other page text can still hold
personal data. Everything a page returns is marked untrusted.

### Input

Input goes through Chromium's own input path (DevTools `Input.dispatchMouseEvent`,
`Input.dispatchKeyEvent` and `Input.insertText`), so pages see trusted events. Cra never clicks
from JavaScript, sets a field's value or dispatches synthetic DOM events. An isolated world finds
targets and counts the trusted events that arrived.

- **Clicks** move the pointer on a short eased path (60–240 ms) and hold the button for
  30–70 ms. With a ref or selector the target must be visible, enabled and uncovered (Cra
  looks through shadow roots), and it must not move while the button is down. A right-click
  reaches the page's `contextmenu` handler, but no native menu opens over your screen.
- **Typing** up to 100 pieces goes in key by key (8–25 ms holds, 6–30 ms gaps), so search boxes
  and autocompletes react as they would to you. Longer text, up to 20,000 characters, goes in
  as committed text per line, like a paste, in well under a second. `\n` is the Enter key: a
  new line in a textarea or editor, a submit in a one-line field. Text into an input,
  textarea or plain editable element is checked against the expected value; into a rich
  editor, the editor must show the typed text; into a cross-site frame, nothing can be checked.
- **Keys** with ⌘ on the Mac run Chromium's editing commands where the Mac has one (⌘A selects
  all, ⌘Z undoes, ⌥⌫ deletes a word), and are page shortcuts otherwise (⌘K).
- **Selects** use focus and the select's own type-ahead, never its popup: Cra types the
  shortest unique start of the option's label. When options share a start, the page sees a
  change event for each option passed on the way, and the result says how many.
- **Dialogs**: while a JavaScript dialog is open the page waits for it, so every other tool on
  that tab returns at once with the dialog's text, and `tabs_list` shows it. The click or key
  that opened one returns `dialog_opened`. Answer it with `page_dialog`.

An error may follow input that partly happened; the result says so ("Input may be partial").
Read the page before trying again; never replay blindly. If the page navigates during input,
the result is `navigation_observed`.

### Windowless pages

`tab_open` with `windowless=true` makes a 1280×800 page outside the sidebar, in the space's
profile (HttpOnly cookies included). It belongs to its connection, closes when that connection
does (at most eight at once) and is needed only for `page_download`. It has no extensions, no
native browser UI and no permission prompts: new media and permission requests, external app
links and popups are refused, JavaScript dialogs are suppressed and file pickers cancelled
(use `page_upload`). `tab_show` refuses it.

### Files

`page_upload` takes 1–8 absolute paths of regular files (not symlinks), copies them into private
staging and selects them with `DOM.setFileInputFiles`; it doesn't submit the form. 16 MiB a file,
64 MiB a tab. Copies stay until their tab closes, its page is replaced, or MCP stops, so the page
can still read its File objects; after a crash they go the next time MCP starts.

`page_download` fetches an HTTP(S) URL through a windowless page's session and returns a
`downloadId` to poll with `download_status`. One at a time per page, at most 64 MiB, 60 seconds
and eight a page. The site's file name never chooses the path: files go into new 0700 folders
under `mcp-transfers` as 0600 files. Cancelling or disconnecting removes partial files; finished
ones stay for you or the agent. A download still running after 60 seconds closes its page;
`download_status` then says `timed_out` and how to recover.

### Console

`page_console` starts capturing on its first call for a tab (it includes what Chromium kept from
before) and returns up to the last 100 of 300 kept entries: `console.*` calls, uncaught
exceptions and browser messages such as failed requests. `level` narrows to warnings or errors;
`clear=true` empties the buffer after reading. Capture turns on DevTools' Runtime domain, which
some pages look for, so it stays off until asked.

## Access and limits

The bridge (`Cra --mcp <socket>`) talks to the running app over a Unix socket in the profile
folder, mode 0600; both ends check they run as the same macOS user. No TCP port is opened. An
exclusive lock keeps a second instance from taking a live socket. Eight clients and 32 messages
in flight per client are admitted. A socket path is limited to 104 bytes, so a data folder
deep in the file system can't run MCP (Settings shows the error).

Turning MCP on lets the agents you allow read your pages and act as you in them. It is not a
per-site permission system, and Cra doesn't ask before a purchase or a message is sent. Set
confirmations in the agent, and treat page content as untrusted: a page can contain
instructions meant for the agent. Settings shows the last tool called.

What an agent can't read: field values are left out of snapshots, page text and point
descriptions, password fields are masked in screenshots, and Chromium doesn't let a password be
copied. A script can read them, though: a click in a login form makes Chromium fill a saved
password, and JavaScript on the page can then read it. That is why `page_evaluate` is off until
you turn on **Let agents run JavaScript in pages**.

The approval prompt keeps out programs you didn't mean to connect. It isn't a wall against
software already running as you: a program like that can start an allowed agent itself, or edit
Cra's files and preferences.

Clients can use MCP 2024-11-05, 2025-03-26, 2025-06-18 or 2025-11-25. Messages are at most
1 MiB, text results 200,000 UTF-8 bytes. Input calls may run up to 100 seconds, PDFs 120,
everything else 20. A per-tab lease keeps two calls from interleaving input in one tab; other
tabs and `ping` stay responsive. `notifications/cancelled` stops an input call between events.

Not reachable: cross-site iframe content through refs (use x/y), closed shadow roots, Chrome
extension UI, permission prompts and passkey or Touch ID sheets, which stay yours to answer.

## Development checks

`scripts/test.sh` runs the CraCore tests (`MCP*Tests`) and the transport and bridge checks. The
live suites run the real app with a temporary profile and local pages, behind other apps
(`CRA_TEST_BACKGROUND=1`), so they don't need the screen:

```sh
scripts/build.sh release
python3 Tests/mcp_integration.py --app build/Cra.app   # protocol, input, refs, cancellation, restart
python3 Tests/mcp_extended.py --app build/Cra.app      # windowless pages, uploads, downloads, permissions
python3 Tests/mcp_agent.py --app build/Cra.app         # hidden tabs, editors, frames, keys, dialogs, console
```

`mcp_extended.py --with-pip` also checks Document Picture in Picture, which floats a window over
the screen. `mcp_integration.py --hold` keeps a clean playground running and prints an MCP
configuration for trying a real client against it; `Tests/mcp_sdk_smoke.py` (official MCP Python
SDK, no model) and `Tests/mcp_claude_smoke.py` (an authenticated Claude Code, sending only the
fixture's synthetic content) take that configuration. Run them after changing MCP input,
transfers, the CEF integration or browser lifecycle.
