# Contributing to Cra

Thanks for helping. Bug reports with steps to repeat them are the most useful thing
you can send. Code is welcome too, within the few rules below.

## What fits

- **Arc parity, one to one.** Where Arc had a feature, Cra matches it: the same layout,
  shortcuts, animations and hover states. When you change one, compare it with Arc and
  include a screenshot or clip of both.
- **No built-in AI.** Arc Max-style features (tidy tabs, summaries, LLM search) are out
  of scope.
- **No account, no server, no telemetry.** Everything stays on the user's Mac.
- **Native first.** The app is AppKit and SwiftUI; web content is Chromium through CEF.

For anything bigger than a bug fix, open an issue or a
[discussion](https://github.com/VictorKildahl/cra/discussions) first, so we can agree on
the shape before you spend the time.

## Getting set up

    git clone https://github.com/VictorKildahl/cra.git
    cd cra
    scripts/build.sh      # first run fetches CEF
    scripts/dev.sh        # debug CraDev.app, rebuilds + relaunches on save

You need macOS 14+ on Apple silicon, Xcode 16+ and CMake (`brew install cmake`).
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
