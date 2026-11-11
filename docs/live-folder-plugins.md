# Live folder plugins

Live folders use JavaScript providers and native sidebar rows. GitHub, GitLab and Jira ship in
`resources/live-folder-plugins`; they use the same execution and presentation API as installed
packages. Service-specific requests, parsing, filters, icons, labels and navigation triggers belong
to the package. Cra owns tabs, persistence, scheduling, profile selection and permission checks.

## Installing a package

Open **Settings → Plugins → Add Plugin…** and select a ZIP archive containing
`manifest.json`, a JavaScript entry file and an icon, either at the archive root or inside one folder. The dialog lists the sites it may load signed in as you, and says it can pass what it reads from one
to another. After you accept, the
package is copied into `LiveFolderPlugins` under Cra’s data directory. It appears in Live Folders
without rebuilding the application. **Reload Plugins** reloads edited packages; errors appear below the plugin list.
Each plugin can be enabled or disabled in this pane. Duplicate IDs are rejected; bundled packages take precedence.
Use **Remove…** to move a user package to the Trash. Built-in packages can be disabled but not removed.
Existing folders and tabs remain.

ZIP archives are limited to 10 MiB compressed,
20 MiB expanded, 4 MiB per entry and 100 entries. Encrypted archives, links, duplicate paths
and paths outside the package are rejected. Temporary files are removed on cancellation or failure.

## Jira Data Center

Add **Live Folders → Jira…** and enter your Jira base address, including a context path
or non-default port if needed (for example `https://jira.example.com:8443/jira`).
Sign in to Jira in the same Space’s Profile. The plugin uses the browser session with
[Jira Data Center REST API v2](https://developer.atlassian.com/server/jira/platform/jira-rest-api-examples/);
Jira Cloud is not currently supported by this provider.

The folder shows issues assigned to you in **To Do** and **In Progress** by default. **Reported by Me** and
**Watched by Me** can be enabled independently; these ownership filters are combined with OR.
**To Do** and **In Progress** select Jira status categories and are both enabled by default.
Leave only **In Progress** enabled to hide work that has not started. Completed issues are not included.
At least one ownership filter and one category must be enabled to show issues.
Rows show the issue key, summary and status. **Projects** lists project keys from matching
issues and lets you hide projects separately for each folder. Switching a filter refreshes
the folder; excluded issues are removed after a successful refresh without the usual retention.

## Saved folders

A folder from GitHub or GitLab keeps `liveFolder` in `sidebar.json`, with the plugin’s
configuration beside the old fields, so an older Cra still reads it as its GitHub or GitLab folder.
Any other plugin’s folder (Jira, an installed plugin) is saved under `pluginFolder`: Cra 0.1.37 and
older can’t read a `liveFolder` with another source and would set the whole file aside, while
under the new key they show a plain folder with its tabs. Fixture: `sidebar-plugin-folder.json`.

## Manifest

```json
{
  "id": "example.service",
  "name": "Example Service",
  "version": "1.0.0",
  "apiVersion": 1,
  "entry": "main.js",
  "sessionOrigins": ["https://example.com"],
  "command": {
    "title": "New Example Folder",
    "description": "Add your example items to the sidebar.",
    "triggers": ["example folder"]
  }
}
```

IDs use lowercase ASCII letters, digits, dots and hyphens. Entry paths must stay inside the package,
including after resolving symbolic links. Scripts are UTF-8, up to 2 MiB. Icons are package-local
images rendered as templates in the existing folder and tab colors.

`sessionOrigins` grants exact HTTP(S) origins: scheme, host and port. Subdomains are separate origins.
For a configurable instance, declare `sessionSetting` with the key used by `describe().setup`;
the address entered when creating the folder grants its origin. The setup currently supports one
server-address field. `legacySource` and `legacyCommand` are reserved for bundled migrations.

## JavaScript API

The entry script returns an object with synchronous functions. Each invocation runs in a fresh
JavaScriptCore helper process, outside the UI process. The helper applies a macOS Seatbelt profile
that denies new resource access before it reads the script: no files, no network, no other processes.
Its only way out is the pipe to Cra, which checks every session request against the folder’s origins.
This is not a Node.js or DOM environment;
imports, filesystem access and browser globals are not exposed. Promise results are rejected.

| Method | Input | Result |
| --- | --- | --- |
| `describe()` | Empty object | Native presentation description |
| `refresh(input)` | `settings`, `filters`, `state`, `groups`, session grants and cached metadata | Complete snapshot |
| `signIn(input)` | Folder configuration | Sign-in action and instance-specific strings |
| `pageChanged(input)` | `url`, `previousURL`, `settings`, `state` | `{state, refreshAfter, checkSignIn}` |

`pageChanged` runs only when a tab in the folder’s profile moves to or from one of the folder’s
session origins; other addresses never start the helper. `checkSignIn` refreshes a folder that waits
for a sign-in 2 s after such pages stop loading (at most once per 10 s).

`describe()` returns `folderTitle`, `menuTitle`, `icon`, `filters` and `statusMessages`. Each filter
has `id`, `title` and `enabledByDefault`. Optional `groups: {title, description}` controls the group
exclusion submenu. Optional `setup` has `key`, `title`, `message`, `placeholder`, `defaultValue`,
`invalidTitle` and `invalidMessage`; the native address dialog retains Cra’s normal layout.

`signIn()` returns `title`, `url` and `warning`. Optional `emptyText`, `failureText`, `failureURL`,
`instanceLabel` and `detailLabel` supply the folder’s empty/error rows and instance menu labels.

A snapshot contains `items`, `actions` and `preservedGroups`. Each item has a unique `id` and `url`,
`title`, optional `subtitle`, `group` and `createdAt` (Unix seconds). Actions have `title` and `url`;
optional `actionMessage` and `warning` describe additional sign-in requirements. `preservedGroups`
keeps already visible items from those groups when partial authorization hides them from a response.
Return the complete result or throw; a failed request must not turn into an empty successful folder.

Throw `new Error(code)` for `notSignedIn`, `rateLimited`, `network` or `unexpectedPage`.
`statusMessages` maps these codes to service-specific strings. An error can carry a `state` object
of string values, for example to remember a corporate sign-in address. `pageChanged()` can update
the same state and request up to five delayed refreshes, each between 0 and 300 seconds.

## Browser sessions

```js
const response = cra.session.fetch("https://example.com/api/items", {
    headers: {Accept: "application/json"}
});
if (response.status === 401) throw new Error("notSignedIn");
const items = JSON.parse(response.body);
```

The result is `{status, url, body}`. Requests are GET-only and run through Chromium with the folder’s
space profile. Plugins cannot select another profile or read cookies. Cookie, authorization, host,
origin and referer request headers cannot be supplied by plugins. Redirects stop in Chromium and
are checked before the next request; a redirect outside the grant is treated as requiring sign-in.

Each invocation has a 30-second deadline and a limit of 200 requests. Invocations run on a dispatch
queue of their own, never on Swift’s cooperative thread pool. Responses are limited to
4 MiB, protocol messages to 8 MiB and snapshots to 10,000 items. A timed-out helper is terminated;
the existing folder stays intact. Error details go to `cra.log` (Help ▸ Export Diagnostics), and
`CRA_LIVE_FOLDER_DEBUG=1` writes every session response to `<data dir>/live-folder-debug/`.

## Verification

```sh
swift test --package-path Packages/CraCore
scripts/test-live-folder-plugins.sh
bash scripts/test-store.sh
bash scripts/test-folder-glyph.sh
scripts/dev.sh --once
```

The plugin harness (part of `scripts/test.sh`) executes the real, sandboxed helper and tests transport,
permissions, exceptions, timeout, the sandbox, and each bundled provider’s requests, parsing, failures and
migration (`Tests/LiveFolderProviderTests.swift`). The store harness checks native tab reconciliation separately.
The helper uses an explicit `(deny default)` profile: macOS terminates binaries built with SDK 27 or
newer that select a legacy named profile such as `pure-computation` (see `sandbox_init(3)`).
The dev build uses `build/CraDev.app` and `build/dev-data` by default.
