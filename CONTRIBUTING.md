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
  an issue is labelled `not now`, closed and moved there.
- **No cloud AI.** Arc Max-style features (summaries, LLM search, anything that needs an
  API key or sends pages away) are out of scope. The one exception is Tidy Tabs, which runs
  on the Mac's own Apple Intelligence model and only shows when that is turned on.
- **English only, for now.** Like Arc, the interface isn't translated: keeping every
  language in step with a UI that changes most days is more than one maintainer can carry.
  Web pages and Chromium's own dialogs already follow the system language. If you'd like
  Cra in your language, upvote the
  [localization idea](https://github.com/VictorKildahl/cra/discussions/240) instead of
  opening an issue or a PR.
- **No account, no server, no telemetry.** Everything stays on the user's Mac.
- **Native first.** The app is AppKit and SwiftUI; web content is Chromium through CEF.

For anything bigger than a bug fix, open an issue or a
[discussion](https://github.com/VictorKildahl/cra/discussions) first, so we can agree on
the shape before you spend the time.

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
