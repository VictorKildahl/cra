# Boosts gallery

Every folder here is a Boost listed on [crabrowser.app/boosts](https://crabrowser.app/boosts).
Each listing has an **Open in Cra** button: Cra shows what the Boost changes and adds it when you
say yes.

## What a gallery Boost may do

Gallery Boosts only change how a site looks: colours, fonts, text size, hiding things (Zap) and
CSS. They never run code. That's the rule whoever writes one:

- No JavaScript. The file has no field for it, and Cra drops one from a link.
- Nothing that loads from the web: no `url()`, `@import`, `image()`, `image-set()`,
  `cross-fade()`, `element()` or `src()`. A selector like `input[value^="a"]` with a background
  `url()` would send what you type to whoever wrote the Boost.
- A backslash may only escape punctuation (`.md\:hidden`). `\75 rl(` spells `url(` to a browser.
- One site per Boost, written without `www.`. A Boost for `reddit.com` also applies on its
  subdomains.

Cra runs the same checks (`SharedBoost.problems` in CraCore) before it installs anything, so a
Boost that breaks a rule won't install, from the gallery or from a link.

## Sending one

The quickest way: make the Boost in Cra (type **New Boost** in the command bar on the site), then
right-click it in **Library ▸ Boosts** and choose **Share Boost…**. Open the link. The page has
**Send to the Gallery**, which opens GitHub with the file filled in, ready for a pull request.

By hand: add `boosts/<name>/boost.json`, where `<name>` is lowercase words with hyphens that start
with the site, like `youtube-no-shorts`.

```json
{
  "v": 1,
  "name": "Hide Shorts",
  "host": "youtube.com",
  "about": "Hides Shorts shelves in search and on Home, and Shorts in the side menu.",
  "by": "your-github-name",
  "preview": "https://www.youtube.com/results?search_query=mac+browser",
  "zapped": ["ytd-reel-shelf-renderer"],
  "css": ""
}
```

| Field | Required | What it is |
|---|---|---|
| `v` | yes | Always `1`. |
| `name` | yes | Up to 60 characters, in title case, without the site's name ("Hide Shorts"). |
| `host` | yes | The site, lowercase, without `www.`. |
| `about` | yes | One or two sentences, up to 280 characters: what it changes. |
| `by` | yes | Your GitHub user name. |
| `preview` | yes | A public page where the change shows, with no login needed. The gallery's before and after pictures are taken there. |
| `zapped` | | CSS selectors of what to hide, as Zap records them. |
| `css` | | Your own CSS. |
| `hue`, `strength` | | The colour wheel: hue 0–1, tint 0–1. |
| `invert` | | `true` to invert lightness (pictures keep their colours). |
| `contrast`, `brightness`, `saturation` | | 0–100, where 50 is the site's own. |
| `font` | | One of the editor's fonts by name, such as `"Georgia"` or `"Palatino"`. |
| `textScale` | | Text size, 0.5–3, where 1 is the site's own. |
| `textCase` | | `upper`, `lower` or `capitalize`. |

Before you open the pull request, run the check:

    swift test --package-path Packages/CraCore --filter SharedBoostTests

## Review

A person reads every pull request and opens the preview page with the Boost on. Send one Boost per
pull request. A Boost that hides something should name it by what it is, not by where it is on the
page. `ytd-comments#comments` keeps working longer than `#columns > div:nth-child(3)`.

Sites change. When a gallery Boost stops working, open an issue or send a fix to its folder. To ask
for a Boost nobody has made yet, use
[Boost requests](https://github.com/VictorKildahl/cra/discussions/categories/boost-requests).
