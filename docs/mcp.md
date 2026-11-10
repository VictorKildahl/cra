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

While an agent acts in a page, Cra's toast says so in the window it works in ("Claude Code is
using Cra"), with **Stop**: every agent disconnects and MCP turns off until you turn it on again.
The toast stays while the agent works and goes a few seconds after its last action; reading,
organizing tabs and notes never show it.

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
- `tab_move`, `tab_update` and `folder_create` organize the sidebar as a drag or a menu does:
  move a tab to another space, to its favorites, pinned or today section, into a folder or after
  another tab; rename, mute, put to sleep or wake it; make a folder in a space's pinned section.

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
| `page_select` | Choose an option by value or label: a `<select>`, a typeahead combobox, or a button that opens a listbox |
| `page_batch` | Up to 50 page tool calls on one tab in one request; the first failure stops the rest |
| `page_network` | Requests since capture started: method, URL with tokens hidden, type, status |
| `site_notes` | Plain-text notes the agent keeps per site, shown at the top of that site's snapshots |
| `history_search` | Your history, newest first, only with **Let agents read your history** on (off by default) |
| `tab_move`, `tab_update`, `folder_create` | Organize the sidebar (see above) |
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
from JavaScript or dispatches synthetic DOM events; the one value it sets directly is a date,
time, month, week, colour or range input (below). An isolated world finds targets and counts the
trusted events that arrived, waiting up to half a second for them.

Input is instant by default: the pointer jumps to the target and keys go in without pauses.
`humanize=true` paces it like a person: a short eased path (60–240 ms), a 30–70 ms press, keys
held 8–25 ms with 6–30 ms gaps.

- **Clicks**: with a ref or selector the target must be visible, enabled and uncovered (Cra
  looks through shadow roots), and it must not move while the button is down. A target is
  scrolled into view and given two frames to settle first. A right-click reaches the page's
  `contextmenu` handler, but no native menu opens over your screen.
- **Typing** up to 100 pieces goes in key by key, so search boxes and autocompletes react as they
  would to you. Longer text, up to 20,000 characters, goes in as committed text per line, like a
  paste. `\n` is the Enter key: a new line in a textarea or editor, a submit in a one-line field.
  Text into an input, textarea or plain editable element is checked against the expected value;
  into a rich editor, the editor must show the typed text; into a cross-site frame, nothing can
  be checked. A field the page replaces when it is clicked (Wikipedia's search box) is followed
  when focus lands on one of the same kind that shares its id, name, placeholder, label or title;
  the result says `retargeted`. Anything else is an error and nothing is typed.
- **Date, time, month, week, colour and range inputs** can't be typed into, so `page_fill` checks
  the value's format (2026-11-09, 14:30 or 2:30 PM, 2026-11, 2026-W45, #3b82f6, a number), focuses
  the field natively, sets the value, reads it back and fires `input` and `change`, as
  Playwright's fill does. A value in another format, or one the input refuses, changes nothing.
- **Keys** with ⌘ on the Mac run Chromium's editing commands where the Mac has one (⌘A selects
  all, ⌘Z undoes, ⌥⌫ deletes a word), and are page shortcuts otherwise (⌘K).
- **Selects**: a `<select>` uses focus and its own type-ahead, never its popup: Cra types the
  shortest unique start of the option's label, and the result says how many options the page saw
  on the way. A custom dropdown is typed into (a typeahead) or clicked open (a button), then the
  matching option clicked: only an option of the popup the control owns (`aria-controls`,
  `aria-owns`, `aria-activedescendant`), else the one list inside its component or on screen.
  Several or no matches are refused with what's showing.
- **Dialogs**: while a JavaScript dialog is open the page waits for it, so every other tool on
  that tab returns at once with the dialog's text, and `tabs_list` shows it. The click or key
  that opened one returns `dialog_opened`. Answer it with `page_dialog`.

An error may follow input that partly happened; the result says so ("Input may be partial").
Read the page before trying again; never replay blindly. If the page navigates during input,
the result is `navigation_observed`. A stale ref whose element the page redrew (one element with
the same role and name) is named in the error.

### What an action changed

`page_click`, `page_type`, `page_fill`, `page_press`, `page_select`, `page_drag` and `page_upload`
end with `changes`, so an agent rarely needs another snapshot: the URL and title when they
changed, the interactive elements added (with refs, ready to use), changed (with what they were)
and removed, and the writes the action sent (POST, PUT, PATCH, DELETE: method, URL with
credentials and token-like values shown as `…`, status). Cra compares the interactive snapshot
from before the action with one taken after the requests it started are answered and a new page
has loaded, at most 1.5 s. A long run of one role (a menu's 48 options) is one line. A new page
lists its controls, and the site's notes when it's another site. `changes=false` skips it.

### Batches, network, notes and history

- `page_batch` runs up to 50 page tool calls on one tab in order, each checked and run as if
  alone; the first failure stops the rest, which are reported as not run.
- `page_network` starts capturing on its first call (Cra's own DevTools session; pages can't see
  it) and returns the last 100 of up to 1,000 requests: method, redacted URL, type, status or
  failure. Headers and bodies are never read. `writesOnly` and `clear` narrow and reset it.
- `site_notes` keeps plain text per site (`host[:port]`) in `Notes/` in the data folder (0700
  folder, 0600 files, 8 KB a site) for the agent's next visit. `page_snapshot` shows them first.
  They count as page content: a page could have talked an agent into writing them. Cra never
  reads them itself.
- `history_search` reads Cra's history (web pages only, newest first), only while **Let agents
  read your history** is on.

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
python3 Tests/mcp_agent.py --app build/Cra.app         # hidden tabs, editors, frames, dialogs, changes, notes, sidebar, a probe that pages can't detect agents
```

`mcp_extended.py --with-pip` also checks Document Picture in Picture, which floats a window over
the screen. `mcp_integration.py --hold` keeps a clean playground running and prints an MCP
configuration for trying a real client against it; `Tests/mcp_sdk_smoke.py` (official MCP Python
SDK, no model) and `Tests/mcp_claude_smoke.py` (an authenticated Claude Code, sending only the
fixture's synthetic content) take that configuration. Run them after changing MCP input,
transfers, the CEF integration or browser lifecycle.
