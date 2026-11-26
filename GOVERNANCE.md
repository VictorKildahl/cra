# Governance

Cra is an independent open-source project with no company or investors behind it.

## Who decides

[Victor Kildahl](https://github.com/VictorKildahl) created Cra and is its maintainer. He
has the final say on what Cra does, what gets merged and when it's released, and he is the
only one who can change a behaviour that has already shipped (see
[docs/testing.md](docs/testing.md)).

## How decisions are made

- **Arc parity by default.** Where Arc had a feature, Cra matches it. Changing that needs an
  issue that makes the case ([CONTRIBUTING.md](CONTRIBUTING.md)).
- **New ideas** go to [Discussions](https://github.com/VictorKildahl/cra/discussions/categories/ideas),
  where the community upvotes them. An idea is planned, declined, or closed when it's still
  under 5 upvotes after 60 days.
- **Pull requests** are reviewed against [docs/reviewing.md](docs/reviewing.md): Arc parity,
  the layer rules in [CLAUDE.md](CLAUDE.md), and tests that fail without the change.
- **Releases** are cut by the maintainer, built and notarized for Apple silicon and Intel, and
  must pass the release gate in `scripts/release.sh`.
- **Security reports** go privately through [SECURITY.md](SECURITY.md).

Much of the day-to-day work is done with AI coding agents working under the rules in
[CLAUDE.md](CLAUDE.md). The maintainer sets those rules and is responsible for every change
that lands.

## Contributors

Anyone can contribute through issues, discussions and pull requests. Contributors are
credited by name in the release notes. Everyone in Cra's spaces follows the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Funding

Cra is free and paid for by [GitHub Sponsors](https://github.com/sponsors/VictorKildahl).
Sponsors, including companies, get the perks listed on the Sponsors page and no say over
Cra's roadmap. Nothing paid for goes inside the app.

## Continuity

The code is MIT-licensed and everything needed to build Cra, including the engine, is in
this repository and its releases, so anyone can fork and continue it.
