<p align="center">
  <img src="brand/cra-segments-icon.svg" alt="Cra logo" width="128" height="128">
</p>

<h1 align="center">Cra</h1>

<p align="center">
  A native macOS browser with a sidebar instead of a tab strip.<br>
  Free and open-source, built to replace Arc one to one.
</p>

<p align="center">
  <a href="https://github.com/VictorKildahl/cra/releases/latest/download/Cra.dmg"><b>Download for macOS</b></a> ·
  <a href="https://crabrowser.app">crabrowser.app</a> ·
  <a href="https://crabrowser.app/release-notes">What's new</a> ·
  <a href="https://crabrowser.app/help">Help</a>
</p>

<p align="center">
  <a href="https://github.com/VictorKildahl/cra/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/VictorKildahl/cra?label=release"></a>
  <img alt="macOS 14+, Apple silicon" src="https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20silicon-lightgrey">
  <a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/github/license/VictorKildahl/cra"></a>
</p>

<p align="center">
  <img src="docs/screenshots/cra.jpg" alt="Cra with favorites, a space with pinned tabs and folders, and a split view in the sidebar" width="760">
</p>

Arc ends on 22 December 2026. Cra keeps the parts of it worth keeping: spaces, pinned tabs
that remember where they started, favorites, a command bar that searches everything,
Today tabs that archive themselves, split view, Little Windows and Arc's keyboard
shortcuts. Import your Arc sidebar in one go and carry on where you left off.

The app is Swift (AppKit and SwiftUI) and the engine is Chromium, through the Chromium
Embedded Framework, so sites and Chrome extensions work as they do in Chrome.

## Install

<p align="center">
  <a href="https://github.com/VictorKildahl/cra/releases/latest/download/Cra.dmg"><img alt="Download for Mac" src="docs/assets/download.png" width="272" height="60"></a>
</p>

<p align="center">
  Open the DMG and drag Cra to Applications.<br>
  It's signed and notarized by Apple, and keeps itself up to date. Needs Apple silicon.
</p>

## Coming from Arc

| Arc feature | Cra |
|---|:---:|
| Spaces | ✅ |
| Pinned tabs | ✅ |
| Today tabs and auto-archive | ✅ |
| Favorites | ✅ |
| Folders | ✅ |
| Command bar | ✅ |
| Little Arc | ✅ |
| Split View | ✅ |
| Picture in Picture | ✅ |
| Developer Mode | ✅ |
| Library | ✅ |
| Air Traffic Control | ✅ |
| Live folders | ✅ |
| Profiles | ✅ |
| Private windows | ✅ |
| Arc's keyboard shortcuts | ✅ |
| Import from Arc | ✅ |
| Easels | Not yet |
| Boosts | Not yet |
| Peek | ✅ |
| Notes | Not yet |
| Arc Max | No, Cra has no built-in AI |

The [roadmap](https://crabrowser.app/roadmap) lists what's next.

## Import

On first launch, or later from Cra ▸ Import from Arc or Dia…, Cra brings over:

- **Arc:** spaces, pinned tabs, folders, favorites and the archive, plus passwords and
  sign-ins.
- **Dia, Chrome, Brave, Edge, Opera, Vivaldi, Chromium, Helium:** tabs, bookmarks, history,
  passwords, sign-ins and extensions.
- **Zen and Firefox:** open tabs, bookmarks and history, and Zen's spaces, Essentials and
  pinned tabs.
- **Safari:** whatever Safari exports itself (File ▸ Export Browsing Data): bookmarks,
  history and passwords.

Spaces with the same name merge, tabs that are already there are skipped, and every
step can be skipped.

## Keyboard

Cra uses Arc's defaults, and every one can be changed in Settings ▸ Shortcuts. The ones
you'll use most:

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd> <kbd>T</kbd> | New tab (command bar) |
| <kbd>⌘</kbd> <kbd>L</kbd> | Edit the URL |
| <kbd>⌘</kbd> <kbd>W</kbd> | Close tab |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>T</kbd> | Restore closed tab |
| <kbd>⌘</kbd> <kbd>D</kbd> | Pin or unpin tab |
| <kbd>⌘</kbd> <kbd>S</kbd> | Show or hide the sidebar |
| <kbd>⌃</kbd> <kbd>1</kbd>…<kbd>9</kbd> | Go to space |
| <kbd>⌘</kbd> <kbd>1</kbd>…<kbd>9</kbd> | Go to tab |
| <kbd>⌃</kbd> <kbd>Tab</kbd> | Switch to recent tab |
| <kbd>⌃</kbd> <kbd>⇧</kbd> <kbd>=</kbd> | Split view |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>N</kbd> | New Little Window |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>N</kbd> | New incognito window |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>C</kbd> | Copy URL |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>K</kbd> | Clear Today |
| <kbd>⌘</kbd> <kbd>Y</kbd> | History and archive |
| <kbd>⌃</kbd> <kbd>D</kbd> | Developer Mode |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>I</kbd> | DevTools |

Pages get the first chance at shortcuts Cra doesn't reserve, like in Chrome, so ⌘F in
Google Docs works. The [full list](https://crabrowser.app/shortcuts) is on the site.

## Privacy and security

Cra has no account and no server, and the app collects no analytics. Spaces, tabs and the
archive are plain JSON in `~/Library/Application Support/Cra`. A built-in blocker stops
requests to more than 22,000 ad and tracker domains.

Pages run in Chromium's sandbox with site isolation, passwords and cookies are encrypted
with a key in your Keychain, and new Chromium releases are checked daily and shipped as
signed updates. [crabrowser.app/security](https://crabrowser.app/security) says what is
and isn't covered. To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Support Cra

Cra is free and open source and has no investors or ads. If it earns a place on your Mac,
sponsoring it pays for the Chromium updates, the Apple signing and the time it takes to
keep a browser going. It unlocks nothing in the app, and every feature stays free for
everyone.

<p align="center">
  <a href="https://github.com/sponsors/VictorKildahl"><img alt="Sponsor on GitHub" src="docs/assets/sponsor.png" width="272" height="60"></a>
</p>

<p align="center"><a href="https://crabrowser.app/support">Where the money goes</a></p>

## Build from source

    scripts/build.sh          # fetches CEF on first run, builds build/Cra.app
    scripts/run.sh            # build if needed, then open
    scripts/dev.sh            # dev loop: debug CraDev.app, rebuilds + relaunches on save

Needs Xcode 16+ and CMake (`brew install cmake`). [CONTRIBUTING.md](CONTRIBUTING.md)
covers sending a change, and [docs/development.md](docs/development.md) covers the code
layout, scripting hooks and test instances.

## Licence

MIT, see [LICENSE](LICENSE). Arc is a trademark of The Browser Company. Cra is an
independent project and is not affiliated with it.
