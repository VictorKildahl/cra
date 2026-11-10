# Sharing: usage stats and crash reports

Cra shares nothing about how it's used unless the user turns that on. This page is the contract
between the app, crabrowser.app and the [privacy page](https://crabrowser.app/privacy): change it
here, in CraCore's `Sharing.swift` and on the privacy page together.

## Where the user chooses

- **Onboarding, Privacy step.** Dia's DisclosureView has two checkboxes; Cra's second one is
  "Help improve Cra by sharing usage stats", unticked. Ticked, it turns on usage stats and sets
  crash reports to Send automatically (`AppSettings.setSharesToImproveCra`).
- **Settings ▸ Privacy ▸ Data.** "Share anonymous usage stats" (`shareUsageStats`, off) and
  "Crash reports": Ask each time (the default), Send automatically, Never send (`crashReports`).
  "Show What’s Sent" opens the next usage report in TextEdit, byte for byte.

Both settings are each Mac's own: settings sync neither sends nor applies them.

## Who sends

Only the released app: it has an update feed (`SUFeedURL`, which `scripts/build.sh` keeps only
with `CRA_RELEASE=1`), its bundle id is `dk.kildahl.cra` and it isn't a `CRA_DATA_DIR` copy
(`Sharing.mayReport`). Builds from source, dev builds, scenarios and renamed test bundles send
nothing. `CRA_SHARING_ENDPOINT=http://127.0.0.1:<port>` points any copy at a local server on
purpose; the `sharing` scenario does that.

## Usage stats

`POST https://crabrowser.app/api/stats`, once per UTC day the app runs (checked 30 s after launch
and every 6 hours; `sharing.json` in the data folder keeps `statsSentAt`), so a day's reports
count that day's users who share, per version, chip and macOS. The body is `UsageStats`:

| Field | Example | Notes |
|---|---|---|
| `id` | `5B0F…` | A new random UUID per report: reports can't be linked by id. |
| `version`, `build` | `0.1.38`, `202611100825` | |
| `macOS` | `26.7` | Major and minor only. |
| `arch` | `arm64` | `x86_64` on Intel copies. |
| `memoryGB` | `32` | Rounded. |
| `spaces`, `profiles`, `tabs`, `extensions` | `21–50` | Ranges: 0, 1, 2–3, 4–5, 6–10, 11–20, 21–50, 51–100, 101+. |
| `settings` | `{"httpsOnly": "true"}` | Only settings changed from the default, only those in `UsageStats.reportedSettings` (switches, choices, numbers). |

`UsageStats.unreportedSettings` lists what is never sent (sites, folders, lists, one-time
marks). A test fails when a new setting is in neither list, so each one is a decision.

## Crash reports

macOS writes `~/Library/Logs/DiagnosticReports/Cra-*.ips` (and `Cra Helper (…)-*.ips`). 30 s
after launch Cra looks for ones written since the last look (`sharing.json`'s
`crashesSeenUntil`; the very first look only sets it, so reports from before the choice never
go), at most 5, newest first. Then, by the setting:

- **Ask each time:** "Cra quit unexpectedly" (or "Part of Cra stopped unexpectedly"), with
  Send, Show Report (opens exactly what would be sent in TextEdit) and Don't Send, and an
  "Always send crash reports" checkbox.
- **Send automatically:** sent without a dialog.
- **Never send:** passed over.

`POST https://crabrowser.app/api/crash` with `CrashReports.reduce`'s output, `{ id, header, body }`:

- `id`: a new random UUID.
- `header`: `app_name`, `app_version`, `build_version`, `slice_uuid`, `bundleID`, `bug_type`,
  `os_version`, `name`, `platform`.
- `body`: `exception`, `termination`, `asi`, `ktriageinfo`, `faultingThread`, `threads` (id, name,
  queue, triggered, frames; no registers), `lastExceptionBacktrace`, `usedImages` (name, uuid,
  base, size, arch, bundle id and version; no path), `legacyInfo`, `sharedCache`, `bundleInfo`,
  `cpuType`, `translated`, `procName`, `procRole`, `modelCode`, `osVersion`, `uptime`.

Everything else in the .ips is dropped, among it `crashReporterKey` (the same for every report
from a Mac), `sleepWakeUUID`, `bootSessionUUID`, `userID`, `incident`, `procPath`, the parent and
responsible processes, `vmRegionInfo` (names mapped files), `storeInfo` and `trialInfo`. The
result then goes through `DiagnosticsRedaction` (addresses keep their host, the home folder
becomes `~`). Over 512 KB, only the crashed thread is kept. A failed send isn't retried.

## On crabrowser.app

`src/app/api/stats/route.ts` and `src/app/api/crash/route.ts` in cra-website, with the checks in
`src/lib/app-reports.ts`: a report with any other field, a value outside the ranges, a path or
one of the dropped ids is refused (400).

- Stats become one event in Phantom's "Cra app" site (a site of its own, so app reports never mix
  with the website's visits), sent server to server with no IP. The event is named after the
  version (`Cra 0.1.38`) and carries the report as readable fields, in the order Phantom's
  card shows them: Version, Chip (Apple silicon or Intel), macOS (`macOS 26.7`), Memory (`32 GB`),
  Tabs, Spaces, Profiles, Extensions, Build and Changed settings (`readable()` in
  `src/lib/app-reports.ts`). Each report's new id makes it a new
  visitor, so **visitors per day are the day's users who share**, and Phantom's events report
  (grouped by name) splits them by version. Phantom's event properties card shows every field at
  once: users, then each field's values with counts and shares, and users a day over longer ranges.
- Crash reports are stored in the private Vercel Blob store `cra-crash-reports` (Frankfurt) as
  `crashes/<day>/<id>.json`, and nowhere else: a crash event in Phantom would count as one more
  user. `node --env-file=.env.local scripts/crashes.mjs [days]` in cra-website counts them by
  version, process, exception and top frames; `… crashes.mjs show <id>` prints one.

Environment on Vercel (production and development): `PHANTOM_INGEST_KEY` (Phantom's server key),
`PHANTOM_APP_WEBSITE_ID` (the "Cra app" site), `NEXT_PUBLIC_PHANTOM_HOST` and
`BLOB_READ_WRITE_TOKEN` (set when the Blob store was connected). `vercel env pull .env.local
--environment development` gives a local `next dev` the same, to test the routes for real.
