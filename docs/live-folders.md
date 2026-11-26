# Live folders (GitHub pull requests)

How Arc and Dia build their GitHub live folders, and how Cra mirrors them.
Targets: Arc 1.170.0 (/Applications/Arc.app), Dia 1.54.2 (/Applications/Dia.app), 27 Oct 2026.
Method: `strings` on both executables, Arc's own data files in ~/Library/Application Support/Arc,
Arc's AX tree and screen captures of its real "Pull Requests" folder, and GitHub's responses to
Cra's own requests. No decompiler on this Mac, so no control flow was read.

Legend: [O] observed, [I] inference, [U] unknown.

## Where the code lives in Arc and Dia
- [O] Both ship the same client, `Frameworks/ARCClients/Sources/GitHubClient/GitHubClient.swift`
  and `GitHubClient+PullRequestsParsing.swift`. Arc's folder model is `LiveFoldersFeature/StorableLiveData.swift`.
  Dia's is `BoostBrowser/Sources/LiveFolders/` (`LiveFolderManager`, `LiveFolderController`,
  `GitHubLiveFolderDataSource`, `PullRequestsLiveFolderDataSource`, `BitbucketLiveFolderDataSource`,
  `LiveDataRefreshSource`). Dia also has Documents, Chats, Notion, Drive and Confluence sources and keeps
  live folders in SQLite (`live_folders`, column `data_source_config`).
- [O] No OAuth app and no token. The client reads github.com with the browser's own session: error cases
  "Not signed in to GitHub", "GitHub SSO required", "Rate Limit Exceeded", "Requested too soon",
  "Unexpected GitHub page structure", "Missing Webcontents for PR". Request headers in the binary:
  `GitHub-Verified-Fetch`, `X-Requested-With`. Sign-in URLs it watches: github.com/login, /logout, /sessions/two-factor/*.
- [O] Pages it reads: `https://github.com/pulls` plus a search (`Failed to construct search URL`, `PR search failed`).
  JSON keys `pullsDashboardSurfaceContentRoute`, `pullsDashboardSurfaceLayoutRoute`, `repoNameWithOwner`,
  `requestingMyReview`, `createdByMe`; it checks for `app-name="dashboard-surface"` (GitHub's React dashboard)
  and falls back to XPath over the classic list (`.js-active-navigation-container > div`,
  `a[@data-hovercard-type='pull_request']`, `a[@data-hovercard-type='repository']`, octicon-git-pull-request*).
- [O] Dia's search terms: `is:pr is:open author:@me`, `user-review-requested:@me`, `review-requested:@me`,
  `review:approved involves:@me`, `review:changes_requested involves:@me`, `sort:updated-desc`, `updated:>=`.
- [O] Single pull request pages are read by running a script in a page (the JS that collects `.gh-header`,
  `relative-time`, diff stats, conflicts, unresolved conversations). Cra doesn't need it for the folder.
- [O] SSO: links to `/orgs/<org>/sso`, `global-sso-banner`, `sso_organizations`; Arc copy "SSO ensures all of your
  organizations' PRs appear", "Login with SSO to unlock this folder".

## Arc's stored model (Victor's real folder)
- [O] StorableSidebar.json, a `list` item titled "Pull Requests" in the JYSK space's pinned container:
  `automaticLiveFolderData { dataSource: {github: {}}, filter: {github: {attributes: 7, hiddenRepositories:
  [{owner, name, provider}]}}, hiddenItems: [{url}], lastFetch: {timestamp, status: {success}} }`,
  `customInfo.iconType.icon = "github"`.
- [O] Its children are ordinary tabs with `liveItemID.url` = the pull request URL; `savedTitle` is the pull
  request's title (not the page title), new ones arrive `isUnread: true`, a tab's `createdAt` is the pull
  request's creation time, children are newest first.
- [O] `hiddenItems` holds pull requests that are still open and awaiting review but no longer in the folder:
  closing a tab out of the folder keeps it out.
- [O] StorableLiveData.json caches each item: `github.pullRequest {author, number, repo{owner,name,provider},
  title, status {open|merged: date}, reviewStatus, isAwaitingMyReview, createdByMe, hasKnownStackMembership, updatedAt}`.
- [I] `attributes` bits: 1 = authored, 2 = review requests to you, 4 = team review requests ("Team Review
  Requests" is a string beside `hiddenRepositories`; 7 = all three, matching Dia's three queries).
- [U] Arc's refresh interval: it reads `automatic-live-folders-min-refresh-interval-in-seconds` from a remote
  flag whose value isn't cached on this Mac.

## Dia's refresh timing
- [O] Dia's LaunchDarkly cache (~/Library/Preferences/com.launchdarkly.client.X35+6+…plist, 27 Oct 2026):
  `github-live-folder-min-refresh-interval-seconds` 120, `github-live-folder-post-merge-retention-seconds` 120,
  `github-live-folder-post-review-retention-seconds` 120, `github-live-folder-json-api-enabled` true,
  `github-live-folder-realtime-updates-enabled` true, `github-live-folder-edit-creation-trigger-enabled` true,
  `github-live-folder-review-creation-trigger-enabled` true, `live-data-proactive-fetching` false.
- [O] Refresh reasons: periodicRefresh, windowFocus, manualRefresh, configChanged, tabReinserted, tabAdopted,
  externalTrigger. The refresh controller keeps `nextEligibleRefreshAt` and skips with rateLimited,
  sourceUnavailable, waitingForActiveWindow. The client has fetchPullRequests, readCurrentUserLogin,
  fetchPullRequestChecks, subscribeToRealtimeUpdates, subscribeToPullRequestDescriptionEditTrigger;
  `reparentPullRequestTabToLiveFolder(url:…createdByMe:)` moves a pull request tab you open into the folder.
- [I] At most one GitHub refresh per 120 s, only while a Dia window is active, plus refreshes when a window
  gains focus and when you create, edit or review a pull request in a tab. Merged and reviewed pull requests
  stay 120 s before they leave the folder.
- [I] How the realtime updates arrive: the signed-in pulls JSON gives each pull request an `aliveChannel` and a
  `commitHeadShaChannel` (null in the responses seen), the names of GitHub's live-update socket channels.
  Dia probably subscribes to those; no socket code was found in its strings, so this is unconfirmed.

## Arc's folder on screen (captured 27 Oct)
- [O] Folder row: Arc's usual folder glyph in the space's folder colours with GitHub's mark on its front;
  title bold like other folders. A 26×26 trailing button showed a ⚠ that stayed on hover (the folder was in
  an error state; the healthy state's button was not seen).
- [O] Pull request rows: GitHub mark as the icon, author login under the title for other people's pull
  requests (`sidebarItemSubtitleTextField`), none under your own (Cra names your own too, Victor's call
  28 Oct); unread dot; ✕ on hover like any pinned tab.
- [O] Context menu strings: "Copy All Links as Markdown", "Delete Live Folder", repository list explained by
  "This list is generated based on your currently active pull requests.", "Failed to update". Deleting asks
  "Delete your %@ Live Folder?". Not in Arc's menu bar (only a debug menu "Automatic Live Folders").
- [O] The menu's nesting (7 Nov 2026, PR #229 review, Arc 1.172.1's arm64 disassembly; Swift keeps strings of up
  to 15 bytes as immediates, so they're decoded from the mov/movk pairs, not found by `strings`): the folder
  menu builds a "Pull Requests" item with an image, then its children: "Refresh", "Initializing..." or "Last
  fetched…", "Repositories", the "Single Sign-On" / "Required" SSO items, and the filters "Created by Me",
  "Review Requests", "Team Review Requests". No "My Pull Requests" string exists. "Move to" sits in the shared
  sidebar item menu.

## What Cra does

The providers now ship as JavaScript packages under `resources/live-folder-plugins`.
The native sidebar presentation and tab lifecycle remain the same. Package installation,
session permissions and the provider API are documented in [Live folder plugins](live-folder-plugins.md).

- Arc follow-up (7 Nov 2026): refresh, category filters and Repositories are in the **Pull Requests**
  submenu; the author filter is named **Created by Me**. Excluding or including a repository refreshes
  the folder and removes or restores its PRs without the closed-request grace period. A live tab
  navigated away from its PR stays in the folder; returning to an excluded PR removes it on the next
  refresh. A PR closed on GitHub was observed with a **Closed** subtitle and remained for at least a
  couple of minutes; its exact retention is still unknown. Cra keeps its existing closed-request delay.
- Fetch: `+[CraCEFRuntime fetchPluginURL:headers:profilePath:completion:]`, a browser-side `CefURLRequest` on the
  space's profile, so it carries that profile's cookies. The GitHub plugin runs one search per enabled
  filter: `/pulls?q=…` with the JSON headers first, `/search?type=pullrequests` when that gives nothing it
  can read. The reader accepts GitHub's JSON routes, embedded React data and the classic list.
  Whatever the answer carries, only open pull requests (drafts too) become items: a merged or closed
  one (`state`, `merged`, `mergedAt`, `closed`, or the classic list's merge/closed icon) is left out, so a
  pull request merged since the last refresh leaves after the 120 s grace (#523).
- Folder: `SidebarItem.liveFolder` (LiveFolderData), tabs carry `liveItemURL` and `liveSubtitle`.
  SidebarStore.applyPluginResults adds and updates tabs, moves a Today tab already on a new pull request into
  the folder, and marks ones that left the results (`liveGoneAt`); `expireLiveItems` removes them 120 s later
  (a tab open in a window stays until it isn't). A tab on one of its item's own pages (Files changed, a comment
  link, a query, owner/repo in another case) still counts as on it and goes too; one on another page stays
  (`LiveItemPage`, #697). Closing or dragging a tab out adds it to `hiddenItems`, and refreshes leave it out
  as Arc's do (#697 asked for them to come back; Arc keeps them out); Reopen Closed Tab puts it back.
  Nothing can be dropped into a live folder.
- Refresh, on Dia's schedule: at most every 120 s and only while Cra is the active app; when any Cra window
  becomes key; from the folder's button and menu (10 s apart); forced when a filter changes; forced 5 s and
  45 s after a tab goes from a repository's compare page to a pull request (one was just created) or to a
  `#pullrequestreview-` anchor (a review was submitted). One GitHub folder per space ("New GitHub Live
  Folder" in the sidebar menus and command bar). Not copied: Dia's realtime updates (see below).
- Import: Arc's live folder (`automaticLiveFolderData` with `dataSource.github`) comes over as a Cra live
  folder with its `attributes`, `hiddenRepositories` and `hiddenItems`; its tabs keep `liveItemID.url` as
  `liveItemURL`. Arc's `lastFetch` stays behind, so the first refresh runs at once and marks nothing unread.
  Before #215 it arrived as a plain folder of import day's pull requests that never refreshed.

## Verified (27 Oct 2026)
- GitHub's answers when signed out: `/pulls` with the JSON headers returns 404 `{"error":"Couldn’t authenticate you"}`;
  `/search?type=pullrequests` returns 200 JSON `payload.blackbirdSearchRoute` with `"logged_in":false`. Both
  read as "not signed in"; the test instance showed "Sign back in to GitHub." and the warning button.
- Real search results (cli/cli, via a scratch build that swapped the `@me` terms for a public query):
  `results[]` with `number`, `hl_title`, `author_name`, `state` open|draft, `merged`, `created`
  (with UTC offsets), `repo.repository.{owner_login,name}`, `issue.issue.pull_request_id`. All ten parsed;
  the folder filled, a removed item came back unread, closing one kept it out across a refresh.
- The browser-side request sends both SameSite=Lax and SameSite=Strict cookies of the profile (checked
  against httpbin.org/cookies), so GitHub's `user_session` and `__Host-user_session_same_site` go along.
- Signed in (Victor's account in a test profile, after JYSK SSO): `/pulls` with the JSON headers returns
  200 `payload.pullsDashboardSurfaceContentRoute {results[], pageInfo, error}`; each result has `number`,
  `title`, `permalink`, `repoNameWithOwner`, `author {displayLogin, displayName}`, `state` OPEN, `isDraft`,
  `mergedAt`, `createdAt`, `updatedAt`, `aliveChannel`. Six pull requests filled the folder from it, without the
  search fallback. Authors come from `displayLogin` (missed at first, fixed).
- Schedule (scratch build with public queries): the compare → pull request trigger refreshed at once and again
  45 s later; items that left the results were kept, then removed after 120 s; an open Today tab on a returning
  pull request was moved into the folder without a duplicate; no fetch for 2.5 minutes in the background,
  one within a second of the window taking focus.
- Not verified: the review trigger (`#pullrequestreview-` anchor) with a real review.
- Organisation SSO (19 Nov 2026, Victor's session with jysk-dev's SAML lapsed): `/pulls` with the JSON headers
  lists pull requests but never the organisations waiting for SSO; the `/pulls` HTML page has them in its
  layout's `sso.sso_organizations[].login` (what Arc reads) and the search JSON in `protected_org_logins`. The
  plugin read only those two keys from the JSON answers, so a folder with pull requests from elsewhere showed
  no key (#521). It now reads the `/pulls` page once per refresh when no answer named them.

## GitLab live folders (Cra only; contributed by STRENCH0, #223)

Arc has no GitLab source (only `dataSource.github`), so Cra's GitLab folder is Arc's GitHub folder with
GitLab as the source: the same folder row, menus, dialogs, refresh schedule and hidden items.
- Live Folders ▸ (space and sidebar menus, Arc's submenu): **GitHub** ✓ while the space has one, then
  **GitLab (host)** ✓ per GitLab folder, then **GitLab…**. A ✓ item asks Arc's "Delete your %@ Live Folder?"
  ("You can restore this folder at any time by right-clicking the sidebar.", Delete Folder `↩`).
- GitLab… asks for the instance in Arc's text-input dialog; empty means `https://gitlab.com`. Self-managed
  addresses keep their port and subpath (`GitLabLiveClient.serverURL`). One folder per instance per space,
  named "Merge Requests" (Arc's GitHub one is "Pull Requests").
- Requests go through `+[CraCEFRuntime fetchURL:…]` on the space's profile, like GitHub's: GitLab takes its
  session cookie on `GET /api/v4`, so no token. `/api/v4/user` for the user id, then one paged
  `/api/v4/merge_requests?state=opened` per filter: `scope=created_by_me` (My Merge Requests),
  `scope=all&reviewer_id=<id>` (Review Requests), `scope=assigned_to_me` (Assigned to Me). All three on by
  default, as Arc's GitHub filters are. A redirect to another page (a sign-in) reads as signed out.
- The folder menu follows GitHub: a **Merge Requests** submenu contains last update, the instance,
  Refresh, the three filters, Projects (Arc's Repositories), and Sign In to GitLab… when signed out.
  Move to, Icon Color, Rename…, Copy All Links as Markdown and Delete Live Folder stay outside it.
  Repository lists fall back to saved live tabs before the first successful refresh, including after
  relaunch; excluded projects stay in the list so they can be enabled again. The mark is GitLab's tanuki
  in one colour, drawn in the folder's ink like GitHub's.
- A space moving to another profile empties its live folders and fetches again with the new profile;
  an answer to a request made for the old profile, server or filters is dropped.
- Left out of #223 as not Arc: category subfolders ("Separate by Category"), "Restore Hidden", a minimum
  450 ms refresh spinner and manual refreshes without Arc's 10 s gap.

## GitHub dashboard and hover checks (24 Nov 2026)

The signed-in `/pulls/search` JSON has `payload.pullsDashboardSurfaceContentRoute.results[]`.
Confirmed item keys: `itemType`, `id`, `number`, `permalink`, `repoNameWithOwner`, `title`,
`titleHtml`, `author {displayLogin}`, `authoredByAgent`, `assignees`, `state`, `displayState`,
`isDraft`, `isReadByCurrentUser`, `commentCount`, `labels [{color, description, globalId, id,
name, nameHtml}]`, `taskListItemCount`, `completeTaskListItemCount`, `headSha`,
`commitHeadShaChannel`, `mergeQueueUrl`, `closedAt`, `mergedAt`, `createdAt`, `updatedAt`.
Dates are ISO 8601 with an offset. No checks or review keys exist in this payload.
The plugin keeps the draft, comments, up to ten labels, nonzero task totals, updated date and
40-hex head SHA; the first known details win when filters overlap. The private capture is
not a fixture; the dashboard fixture uses made-up data and these keys only.

Checks on hover use `GET https://github.com/<owner>/<repo>/pull/<number>/checks` with
`Accept: application/json`, `X-Requested-With: XMLHttpRequest`, `GitHub-Verified-Fetch: true`.
Runtime verification on public `cli/cli` PRs 15108, 13788 and 14927 confirmed JSON
wrapping HTML in `payload["pullRequestsChecksRoute.Main"].value`. The HTML contains
`checks-list-item` jobs nested inside suite `details`/`summary` containers, SVG
`aria-label` status icons, and job names in the span inside `a.SideNav-subItem`.
The recorded parse matched 15108's 12 passing jobs and 6 skipped jobs, and 13788's
8 passing and 3 failing jobs, including the failing names. Success and skipped labels
include `This job succeeded`, `This check passed` and `This job was skipped`.
Hand-written fixtures preserve that structure with made-up job names. Failed/pending
labels are recognised conservatively; any unknown job icon drops the entire checks
result rather than giving an incorrect count.

Count each workflow name + event + check name once, keeping the entry with the highest
`/actions/runs/<id>/` number, regardless of page order. Thus `CI on: push` and
`CI on: pull_request` both count, while an older failure from the same workflow and
event cannot override its passing rerun. Third-party checks without a run ID keep one
entry per app/workflow section and name. An unreadable section header falls back to
check-name deduplication. Skipped checks count as done: the card shows
`(passed + skipped) / (passed + skipped + failed + pending)`, like GitHub's card.

Known limit: commit statuses (for example, a Vercel deployment status) are absent from
`/checks`, so the card can count one fewer than GitHub when a PR has them.
There is no review state, row glyph, prefetch, polling, POST, token or API-host request.
