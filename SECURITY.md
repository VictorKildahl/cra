# Security

## Reporting a vulnerability

Please report security problems privately through
[GitHub's private vulnerability reporting](https://github.com/VictorKildahl/cra/security/advisories/new),
not in a public issue. Include the Cra version (Cra ▸ About Cra), your macOS version, and
the steps or a page that shows the problem.

Cra is made by one person, so there is no guaranteed turnaround, but reports are read
within a few days and fixes ship as a signed update that installs on its own. Reporters
are credited in the release notes unless they'd rather not be.

## Supported versions

Only the latest release is supported. Cra updates itself, and fixes are not backported.

## Scope

In scope: anything Cra adds on top of Chromium, for example

- the `cra://` scheme and what pages or other apps can reach through it
- import from other browsers, and the passwords and cookies it moves
- the update feed and signature checks (Sparkle)
- extensions, native messaging hosts and the Chrome Web Store install flow
- Cra's layer and patches in the engine (`engine/chromium`) and the switches Cra starts Chromium with
- passkeys, Safe Storage and other Keychain use

Out of scope: bugs in Chromium itself, which belong with the
[Chromium project](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/).
If Cra ships a Chromium version with a known, fixed vulnerability for longer than a few
days, that is worth an ordinary issue.

Known gaps, listed on [crabrowser.app/security](https://crabrowser.app/security): Cra has
no Google Safe Browsing, so there are no warnings for known phishing or malware pages.
