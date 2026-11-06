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

## What Cra does
- Fetch: `+[CraCEFRuntime fetchURL:headers:profilePath:completion:]`, a browser-side `CefURLRequest` on the
  space's profile, so it carries that profile's cookies. GitHubLiveClient runs one search per enabled
  filter: `/pulls?q=…` with the JSON headers first, `/search?type=pullrequests` when that gives nothing it
  can read. The reader accepts GitHub's JSON routes, embedded React data and the classic list.
- Folder: `SidebarItem.liveFolder` (LiveFolderData), tabs carry `liveItemURL` and `liveSubtitle`.
  SidebarStore.applyLiveResults adds and updates tabs, moves a Today tab already on a new pull request into
  the folder, and marks ones that left the results (`liveGoneAt`); `expireLiveItems` removes them 120 s later
  (a tab open in a window stays until it isn't). Closing or dragging a tab out adds it to `hiddenItems`.
  Nothing can be dropped into a live folder.
- Refresh, on Dia's schedule: at most every 120 s and only while Cra is the active app; when any Cra window
  becomes key; immediately from the folder's button and menu; forced when a filter changes; forced 5 s and
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

## GitLab live folders

The sidebar's **Live Folders** submenu offers **GitHub** and **GitLab…**. A checkmark marks
an existing folder; clicking it asks for confirmation before deleting the folder. Each GitLab
server has its own checked entry, with **Add GitLab Server…** below them. Enter the server's
base URL (GitLab.com or a self-managed instance, including a port or installation subpath).
Leave the address blank to use the suggested `https://gitlab.com`. Requests use the
space's Chromium profile and its GitLab session cookie, without a separate access token.
The client reads `/api/v4/user` and paginated `/api/v4/merge_requests`. Each space supports
one folder per GitLab server; different servers have independent filters, category layouts
and hidden lists. Default names include the server address, for example **GitLab · gitlab.com**.
Ports and installation subpaths are included when present. Names can be changed from the folder menu.

The folder menu controls **My Merge Requests**, **Review Requests**, and **Assigned to Me**,
plus which projects are included. **Separate by Category** puts the enabled categories in
automatic subfolders. Each MR has one tab: when categories overlap, the first enabled match
wins in the order above. Changing layout moves existing tabs rather than recreating them.
If a filter removes a selected tab, it moves to Today so its page stays open.

Closing or dragging out an MR hides it for the whole live folder, including every category.
The last 200 manually closed or extracted URLs stay excluded across refreshes. Both GitHub
and GitLab folders offer **Restore Hidden**: clear all exclusions and immediately reload from
the service, without restoring cached tabs or presenting a separate list. Closed or deleted
requests do not return. The ordinary Reopen Closed Tab command can undo an accidental close.
Automatic removal of an MR from the results never adds it to the exclusions.

Manual refresh bypasses the automatic refresh cooldown and keeps its busy indicator visible
for at least 450 ms. A configuration change during a request queues a fresh request.
Requests keep Chromium's default timeout. A failed GitLab refresh shows the existing error
indicator and pauses automatic updates until a manual refresh or configuration change. There are no automatic
retries for GitLab; successful folders continue updating every two minutes while Cra is active.
GitHub's retry and sign-in behaviour is unchanged.

The full-colour GitLab mark is from the official
[GitLab SVG assets](https://gitlab.com/gitlab-org/gitlab-svgs/-/blob/main/illustrations/gitlab_logo.svg).
