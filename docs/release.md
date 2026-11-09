# Releasing Cra

Goal: a build that installs like any other Mac app. Download the DMG, drag Cra to
Applications, open it. No right-click, no warnings. That needs three things on top of
the plain build: a Developer ID signature with the hardened runtime, Apple's
notarization ticket stapled to the app and the DMG, and a packaged download.
Everything is scripted; the only manual part is obtaining the certificate once.

## One-time setup

1. **Apple Developer Program** membership for the account that will sign.
2. **Developer ID Application certificate.** In Xcode → Settings → Accounts → Manage
   Certificates, add "Developer ID Application". Export it from Keychain Access as a
   `.p12` with a password. Note the identity string, for example
   `Developer ID Application: Victor Kildahl (ABCDE12345)`:
   `security find-identity -v -p codesigning`.
3. **Notarization credentials.** Create an app-specific password at appleid.apple.com.
   Locally you can store it once: `xcrun notarytool store-credentials cra --apple-id
   you@example.com --team-id ABCDE12345` and then set `NOTARY_KEYCHAIN_PROFILE=cra`.
4. **GitHub secrets** on `VictorKildahl/cra` (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `MACOS_CERTIFICATE_P12` | `base64 -i DeveloperID.p12 \| pbcopy` |
   | `MACOS_CERTIFICATE_PASSWORD` | the `.p12` password |
   | `MACOS_SIGN_IDENTITY` | the identity string from step 2 |
   | `APPLE_ID` | the Apple ID email |
   | `APPLE_TEAM_ID` | the 10-character team id |
   | `APPLE_APP_PASSWORD` | the app-specific password |
   | `MACOS_PROVISIONING_PROFILE` | optional, for passkeys (see [Passkeys](#passkeys)) |
   | `CRA_GOOGLE_API_KEY` | optional, for Safe Browsing (see [Safe Browsing](#safe-browsing)) |

Until these exist the Release workflow still runs: it publishes an ad-hoc build as a
regular release (pre-releases are invisible to `releases/latest`) with the install
steps in `.github/release-notes-unsigned.md`.

## Installing unsigned builds

Gatekeeper only checks files carrying the quarantine flag, which browsers set and curl
does not. So the friction-free path for an ad-hoc build is `scripts/install.sh`, run as

```sh
curl -fsSL https://raw.githubusercontent.com/VictorKildahl/cra/main/scripts/install.sh | bash
```

It downloads `releases/latest/download/Cra.zip`, replaces the app in `/Applications`
(or `~/Applications`), quitting a running Cra first, and opens it. Rerunning it updates.

The DMG path needs one manual approval: open Cra, click Done on the "could not verify"
dialog, then System Settings → Privacy & Security → Open Anyway. Right-click → Open no
longer bypasses Gatekeeper since macOS 15. The README, release notes and the website's
download page all carry both paths; keep them in step.

## Cutting a release

Run the manual checks in [release-checklist.md](release-checklist.md) for every area the
release touched first.

```sh
# 1. Add the release to the website's src/content/releases.ts and bump CRA_VERSION defaults if needed.
# 2. Tag and push. The Release workflow builds, signs, notarizes, packages and publishes.
git tag v0.1.0
git push origin v0.1.0
```

### Sponsors in the release notes

Before writing the notes, run `scripts/sponsors.py`. It reads the GitHub Sponsors tiers and
lists who the tiers promise a name in these notes (one-time $50 and up since the last tag,
monthly $5 and up once a year), which Backers to ask first about the next big feature, and
which companies need their logo on /support. Thank monthly sponsors with their `@login` in
the sentence, so next year's run sees they were thanked. Private sponsors are counted, never
named. It needs the VictorKildahl `gh` login with the `user` scope.

### Clips in the release notes

When a release changes something you can see (UI, animations, dragging), give its
highlight a short clip. `scripts/clips/` records one from a test copy of Cra (CraClip, own
data folder, the website's demo profile) at 120 fps with a pointer that glides like a hand;
the `release-clips` skill in `.claude/skills/` has the steps. Then encode it from the
website repo:

```sh
FPS=120 scripts/release-clip.sh 0.1.14 reorder-spaces ../cra/build/clips/rec/dock.mov 0.9 5.9
```

It writes `public/releases/<version>/<name>.mp4` (H.264, silent, ≤1520 px) and a poster
`.jpg`, and prints a `media: {…}` entry to paste into that highlight in `releases.ts` (fill
in `alt`). A `.png` works too, for still changes. The release notes page loops clips muted
while they're on screen. Keep them under ~8 s and ~2 MB.

A Claude Code hook (`.claude/settings.json` → `scripts/clips/check-release-media.sh`) blocks
pushing a `v*` tag when `Sources/Cra/UI` changed since the previous tag and the release's
entry has no `media`. If there is nothing to film, add `// no clip: <reason>` to the entry.

Every release ships both CPUs. The workflow builds Apple silicon and Intel in two parallel
jobs on the same Apple silicon runner (Intel is cross-compiled) and a third job publishes:

| Apple silicon | Intel |
|---|---|
| `Cra.dmg` | `Cra-Intel.dmg` |
| `Cra.zip` | `Cra-Intel.zip` |
| `appcast.xml` | `appcast-intel.xml` |

plus one `SHA256SUMS.txt` for all four archives. The names carry no version so
`releases/latest/download/Cra.dmg` always resolves; the website's download buttons and
`scripts/install.sh` (which picks the zip by CPU) rely on that.

## Locally

```sh
CRA_VERSION=0.1.0 \
CRA_SIGN_IDENTITY="Developer ID Application: Victor Kildahl (ABCDE12345)" \
NOTARY_KEYCHAIN_PROFILE=cra \
scripts/release.sh
```

`scripts/release.sh` does this once per CPU (`CRA_ARCHS`, default `arm64 x86_64`): it runs
`build.sh` (sign, innermost first, with the CEF entitlements), notarizes and staples the
app, runs `package.sh` (zip, DMG with an Applications link, checksums), then notarizes and
staples the DMG, checks it with `spctl` and writes that CPU's appcast. Both CPUs share one
build number. Without `CRA_SIGN_IDENTITY` it produces an ad-hoc build and skips notarization.

`CRA_ARCH=x86_64 scripts/build.sh` builds the other CPU on its own: the host CPU keeps
`vendor/cef` and `build/Cra.app`, the other one gets `vendor/cef-<arch>` (that CPU's CEF,
read by `Package.swift` through `CRA_CEF_DIR`), `build/swiftpm-<arch>` and
`build/<arch>/Cra.app`. `build.sh` stops if any executable in the bundle lacks that CPU's
code. An Intel build runs on Apple silicon under Rosetta, which is enough for a launch
check; Intel-only problems still need a real Intel Mac.

## The DMG window

Opening `Cra.dmg` shows a drag-to-install window modelled on Dia's installer (decoded from
its `.DS_Store`): 800×400 pt, no toolbar or sidebar, 212 pt icons with Cra at (190, 180)
and Applications at (610, 180), and a background with the install line and a chevron
between them. `scripts/package.sh` builds it with [dmgbuild](https://github.com/dmgbuild/dmgbuild),
which writes the Finder layout directly, so it needs no Finder scripting and runs on CI.
It installs a pinned dmgbuild into `build/dmgbuild-venv` on first use.

- `resources/dmg/settings.py`: window, icon size and positions, volume icon.
- `resources/dmg/background.png`: 1600×800 px at 144 dpi. Regenerate it with
  `swift scripts/make-dmg-background.swift` after changing the brand colours or the layout.

## What the signing covers

Order matters because each signature seals what is inside it:

1. every `.dylib` in `Chromium Embedded Framework.framework/Libraries`
2. the framework itself
3. Sparkle's `Autoupdate` and `Updater.app`, then `Sparkle.framework` (its XPC services are
   removed: they are only for sandboxed apps)
4. the five helper apps, each with `resources/CraHelper.entitlements`
5. `Cra.app` with `resources/Cra.entitlements`

The entitlements are the hardened-runtime exceptions Chromium needs (JIT, unsigned
executable memory, library validation off, dyld environment variables), plus camera,
microphone and location so sites can ask for them.

The helpers run in Chromium's own macOS sandbox (seatbelt): `CraHelper` enters it through
`CefScopedSandboxContext` (which loads the framework's `Libraries/libcef_sandbox.dylib`)
before loading CEF, and `CefSettings.no_sandbox` is off. Renderer, GPU, network, storage
and audio processes are sandboxed, video capture is not (Chrome's choice too).

## Passkeys

Security keys and phones (the QR code in Chrome's "Passkeys & Security Keys" dialog)
work in every build. Passkeys kept on the Mac need entitlements macOS only honours
with a provisioning profile, the way Chrome, Arc and Dia ship:

| Entitlement | Turns on |
|---|---|
| `keychain-access-groups` = `<team>.dk.kildahl.cra.webauthn` | Chromium's Touch ID passkeys, stored in Cra's keychain group. `scripts/cef-patches/webauthn-keychain-access-group.patch` derives the group from the app's `application-identifier` (Chromium's branding has no team ID). |
| `com.apple.developer.web-browser.public-key-credential` | iCloud Keychain passkeys (Passwords app), through Chromium's own iCloud Keychain code. Managed: Apple must approve it. |

One-time setup, as the Account Holder:

1. Request the entitlement for `dk.kildahl.cra` at
   https://developer.apple.com/contact/request/macos-browsers-passkeys/ (Account Holder
   only). Apple reviews it and adds it as a managed capability, which then shows under
   the App ID's Additional Capabilities. The Touch ID group needs no approval.
2. Create a **Developer ID** provisioning profile for the explicit App ID
   `dk.kildahl.cra` and download it. Once the entitlement is approved, regenerate it and
   check that it is included: `security cms -D -i Cra.provisionprofile | grep -A1 public-key`.
3. Locally: `CRA_PROVISIONING_PROFILE=Cra.provisionprofile` next to `CRA_SIGN_IDENTITY`.
   In CI: the `MACOS_PROVISIONING_PROFILE` secret, `base64 -i Cra.provisionprofile | pbcopy`.

`build.sh` embeds the profile as `Contents/embedded.provisionprofile` and adds to
`Cra.entitlements` only what the profile grants (application and team identifier,
the keychain group, iCloud Keychain once approved), because macOS refuses to launch an
app that claims an entitlement its profile lacks. Ad-hoc builds never get them.

## Safe Browsing

Chromium's phishing and malware lists come from Google's Safe Browsing API, which
needs an API key. Without one the lists never download and dangerous pages load
without a warning.

1. In the Google Cloud console, create a project, enable the **Safe Browsing API** and
   create an API key. Restrict it to that API: it ships inside the app, so anyone can
   read it.
2. Locally: `CRA_GOOGLE_API_KEY=<key>` next to `CRA_SIGN_IDENTITY`. In CI: the
   `CRA_GOOGLE_API_KEY` secret. Never commit it.

`build.sh` writes it to Info.plist as `CraGoogleAPIKey`, and CraCEF sets
`GOOGLE_API_KEY` from it before Chromium starts.

The key lives in the Google Cloud project `cra-browser`, restricted to the Safe Browsing
API. Every install shares its quota: 10,000 list updates and 10,000 lookups a day. A
running Cra fetches list updates 1–5 minutes after launch and then once a day
(`scripts/cef-patches/safe-browsing-update-interval.patch`; Chrome uses Google's ~30
minutes), plus a full-hash lookup when a URL matches a list: about 1–3 updates per
install per day. An alert policy in the project emails at 7,000 a day; ask for more on
the API's Quotas page in the Cloud console (the Cloud Quotas API can't). Once the quota
allows it, shorten the interval in the patch. A client over quota backs off (up to 24
hours) and its lists go stale until an update succeeds.

The Safe Browsing API is for non-commercial use. Google's commercial service, Web Risk,
is not a drop-in: it has its own endpoints and request format, so Chromium would need
a patch to its update and full-hash protocol.

## Updates

Cra updates itself the way Arc does, with [Sparkle 2](https://sparkle-project.org)
(`scripts/fetch-sparkle.sh` puts a pinned, checksummed release in `vendor/sparkle`). Every
8 hours it reads `releases/latest/download/appcast.xml`, downloads a newer `Cra.zip` in
the background, installs it when Cra quits, or restarts into it by itself once the user
is away. Cra menu ▸ Check for Updates… and Settings ▸ Advanced ▸ "Automatically update Cra"
are the controls. Details and Arc's original are in `docs/arc-reverse-engineering.md`
("Software updates").

- **Signing key.** Updates are accepted only when `Cra.zip` carries an EdDSA signature
  matching `SUPublicEDKey` in `resources/Info.plist`. The private key is in the login
  keychain of the Mac that made it (`vendor/sparkle/bin/generate_keys --account cra`,
  made 26 Oct 2026) and in the `SPARKLE_PRIVATE_KEY` secret. Back it up
  (`generate_keys --account cra -x <file>`): without it, installed copies can never be
  updated again.
- **Appcast.** `scripts/release.sh` ends with `scripts/appcast.sh`, which signs the final
  `Cra.zip` and writes `build/dist/appcast.xml`; the workflow uploads it with the other
  assets. Each archive holds one CPU's app, so Intel copies have their own feed:
  `build.sh` points their `SUFeedURL` at `appcast-intel.xml`, which signs `Cra-Intel.zip`. `CRA_RELEASE_NOTES=<file.html>` adds release notes to the update window.
- **Version numbers.** Sparkle compares `CFBundleVersion`, the build number `build.sh`
  takes from the clock, so every release is newer than the last.
- **Dev builds** have no feed (`build.sh` drops `SUFeedURL` unless `CRA_RELEASE=1`), so they
  never replace themselves with a release. To test, run a copy with
  `CRA_UPDATE_FEED=http://127.0.0.1:8889/appcast.xml` (and `CRA_UPDATE_IDLE_SECONDS=0` for
  the automatic restart) against a local appcast made with `CRA_UPDATE_URL=… scripts/appcast.sh`.
- Copies from before the updater (0.1.0, 0.1.1) update once by hand: rerun the install line.

## The Chromium engine (CEF)

Cra ships its own CEF build, not Spotify's prebuilt one: Spotify builds leave out
H.264/AAC, so MP4 and HLS video (X, Instagram, Reddit, news sites) never plays. Codecs
are a compile-time switch and FFmpeg is linked into the framework, so there is no way
around building it.

    scripts/build-cef.sh      # ~80 GB free, several hours; resumes where it stopped
    scripts/publish-cef.sh    # uploads the archive as pre-release cef-<version>-codecsN

`build-cef.sh` checks out the same CEF commit `fetch-cef.sh` pins, applies
`scripts/cef-patches/*.patch` on top of CEF's own patches, and builds an official
release with `proprietary_codecs=true ffmpeg_branding=Chrome`. `fetch-cef.sh` (and CI,
keyed on its hash) downloads the published archive into `vendor/cef`, replacing a copy
from a different source. To change the build without a CEF version bump, bump the
`codecsN` suffix of `CEF_RELEASE` and publish again. Needs Xcode's Metal toolchain
(`xcodebuild -downloadComponent MetalToolchain`).

**Patch rounds and Intel.** Once `build-cef.sh` has built a version, a new or changed
patch goes through `rebuild-cef.sh`, which builds from that checkout for both CPUs
(minutes each) and never reruns CEF's patcher (rerunning it compiles Web Push out). The
Intel (`macosx64`) build is cross-compiled on the same Mac from the same sources, in its
own `out/Release_GN_x64` (~12 GB; the first one compiles everything):

    scripts/rebuild-cef.sh [arm64] [x64]           # both when no CPU is given
    scripts/publish-cef.sh                         # arm64 asset
    CEF_ARCH=macosx64 scripts/publish-cef.sh       # Intel asset, same release

**Staying current.** Chromium only ships security fixes for its newest version. The
"CEF updates" workflow (`.github/workflows/cef-updates.yml`, daily, free Linux runner)
runs `scripts/check-cef-update.sh`: when Spotify's index lists a newer stable CEF for
macOS arm64, it opens one "Chromium engine update available" issue, assigned to the repo
owner, with the exact command. The build itself runs on the Mac, because GitHub's free
macOS runners are too small (3 cores, 14 GB disk, 6 hour jobs) and larger ones are billed:

    scripts/update-cef.sh <cef_version>   # build + publish arm64 and x64, pin, rebuild Cra

A same-major update reuses the checkout: `build-cef.sh` moves it to the new Chromium tag
itself, and ninja recompiles nearly everything (about 2½ hours on the M2 Max). A new Chromium
major needs a fresh checkout as well. Then test `build/Cra.app`, commit `scripts/fetch-cef.sh`, close the
issue and tag a release.

## Later

- **Homebrew.** A cask (`brew install --cask cra`) pointing at the DMG and
  `SHA256SUMS.txt`.
