# Contributing to Cra

Thanks for helping. Bug reports with steps to repeat them are the most useful thing
you can send. Code is welcome too, within the few rules below.

## What fits

- **Arc parity by default.** Where Arc had a feature, Cra matches it: the same layout,
  shortcuts, animations and hover states. When you change one, compare it with Arc and
  include a screenshot or clip of both. Arc isn't the only source of truth, though: if
  Arc's way is unintuitive or worse than it could be, open an issue that makes the case,
  and we'll decide it on its merits.
- **New ideas go to Discussions.** A feature Arc never had goes in
  [Ideas](https://github.com/VictorKildahl/cra/discussions/categories/ideas), where others
  can upvote it. Issues are for bugs and for Arc features Cra is missing; an idea opened as
  an issue is labelled `not now` and closed, and may be moved there. An idea is closed
  when it ships, when it's declined, or when it's still under 5 upvotes after 60 days
  (`scripts/ideas-housekeeping.py`, weekly); one labelled `planned` stays open. What makes
  a good one is under [Features Arc never had](#features-arc-never-had).
- **No cloud AI.** Arc Max-style cloud features (anything that needs an
  API key or sends pages away) are out of scope. The exception is features powered by the Mac's
  own on-device Apple Intelligence model (Tidy Tabs, Tidy Tab Titles, Tidy Downloads, 5-Second Previews),
  which only show when Apple Intelligence is turned on and never send anything off the Mac.
- **English only, for now.** Like Arc, the interface isn't translated: keeping every
  language in step with a UI that changes most days is more than one maintainer can carry.
  Web pages and Chromium's own dialogs already follow the system language. If you'd like
  Cra in your language, upvote the
  [localization idea](https://github.com/VictorKildahl/cra/discussions/240) instead of
  opening an issue or a PR.
- **No account, and nothing shared without asking.** Everything stays on the user's Mac. The
  one exception is opt-in: anonymous usage stats and crash reports, off until the user turns
  them on ([docs/sharing.md](docs/sharing.md)). A feature doesn't add to what they send.
- **Native first.** The app is AppKit and SwiftUI; web content is Chromium through CEF.

For anything bigger than a bug fix, open an issue or a
[discussion](https://github.com/VictorKildahl/cra/discussions) first, so we can agree on
the shape before you spend the time.

### Features Arc never had

Parity comes first: Arc is sunset on 22 December 2026, so the first job is that everything
Arc did works in Cra, the way Arc did it. Arc is the reference, not the ceiling, though, and a
new feature fits when:

- **It solves a real problem.** Start from what gets in your way, not from a feature another
  browser has.
- **It builds on what's there.** Tabs, folders, spaces, splits and the command bar cover a
  lot. A new behaviour for one of those beats a new concept, and a new concept has to earn
  its place.
- **It looks like Arc could have shipped it.** It's built from Arc's own parts: its rows,
  pills, menus, spacing and motion. If it needs its own visual language, it probably doesn't
  fit.
- **Nothing leaves the Mac.** No account, server or cloud AI, and no new data in the opt-in
  usage stats. On-device Apple Intelligence is fine, and the feature stays hidden when it's
  off, like Tidy Tabs.
- **It stays out of the way.** People who never use it don't see new settings, badges or
  prompts.
- **One person can keep it working.** Cra has one maintainer and a UI that changes most
  days, which counts against anything that needs constant upkeep (it's why translations are
  "not now").

What feels out of place: anything that needs a sign-in or a server, AI that sends pages
away, a second design language, or a feature that's mostly settings.

Where Cra already differs from Arc, it's one decision at a time with a reason: favorites
belong to each space, and a collapsed space header keeps the space's icon.

To propose one, post it in
[Ideas](https://github.com/VictorKildahl/cra/discussions/categories/ideas): the problem,
which part of Cra it extends, and roughly how it would look. This list grows as original
features ship and there are real examples to point at
([#284](https://github.com/VictorKildahl/cra/discussions/284) is where it started).

## Getting set up

    git clone https://github.com/VictorKildahl/cra.git
    cd cra
    scripts/build.sh          # fetches CEF on first run, builds build/Cra.app
    scripts/build.sh debug    # debug build
    scripts/dev.sh            # dev loop: debug CraDev.app, rebuilds + relaunches on save

You need macOS 14+ on Apple silicon, Xcode 16+ and CMake (`brew install cmake`). With
[just](https://just.systems) (`brew install just`), `just` lists every script with what it
does, and `just build debug` runs `scripts/build.sh debug`.
[docs/development.md](docs/development.md) has the code layout, the `cra://` scripting
hooks and how to run a test instance next to your daily Cra.

## Sending a change

1. Fork, branch from `main`, keep the change to one thing.
2. Match the code around you: naming, comments and structure. Doc comments say *why*,
   not what.
3. Run it, and `scripts/test.sh`. CI builds and signs Cra, runs those tests and launches the
   app, but none of that sees the screen: say in the PR how you tested it, and add a
   screenshot or a short clip for anything visible. A fix for a bug that a test could
   have caught comes with that test ([docs/development.md](docs/development.md#tests)).
4. Don't touch the release pipeline, signing or the CEF pin unless that's the point of
   the PR. Releases are cut by the maintainer.

[docs/reviewing.md](docs/reviewing.md) lists what a review checks, so you can check it first.

## Chromium and CEF

The CEF version is pinned in `scripts/fetch-cef.sh`, which downloads Cra's own CEF build
(H.264/AAC and the patches in `scripts/cef-patches`) from this repository's releases, so
you never need to build Chromium yourself. If your fix needs a new CEF patch, say so in
the issue first: the maintainer rebuilds CEF for it, and every patch has to be carried
through each Chromium update.

## Security

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).

## Licence

By contributing you agree that your contribution is licensed under the
[MIT licence](LICENSE).
