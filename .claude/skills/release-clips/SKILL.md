---
name: release-clips
description: Record and attach short clips (or stills) of Cra's UI to the release notes on crabrowser.app. Use whenever a release, or an entry in cra-website's releases.ts, includes a UI change, animation, hover effect or drag interaction, before tagging the release, or when the release-tag hook blocks a push for missing clips.
---

# Release clips

Every release that changes something you can see gets a clip on its highlight in
`../cra-website/src/content/releases.ts`, shown on crabrowser.app/release-notes. A PreToolUse
hook (`scripts/clips/check-release-media.sh`) blocks pushing a `v*` tag when `Sources/Cra/UI`
changed since the previous tag and the entry has no `media:`. If a UI change has nothing to
film, put `// no clip: <reason>` in the entry instead.

## Rules

- Record the real app, never the website's mockups or the launch reels.
- Use the demo profile (`scripts/clips/seed-demo.py`), never Victor's own tabs.
- Record the whole clip window (1100 x 700 pt), never a crop of the sidebar or a strip. The
  release page shows every clip on an 11:7 stage, the window's shape, so a full-window clip
  fills it and anything else shrinks to a sliver. `release-clip.sh` refuses other shapes
  (landscape 1.5-1.65:1, at least 1400 px wide, density 2), the website build fails on them
  for releases after 0.1.37, and the tag hook blocks them. Frame a small change by where the
  pointer goes and what moves, not by cropping.
- Record at 120 fps and encode with `FPS=120`. Move the pointer with `glide` (eased, 240 Hz),
  never `cliclick m:`/`dm:`, which jump and look laggy. Victor wants clips as smooth as possible.
- Recording takes over the real pointer and keyboard. Ask Victor before taking the screen, and
  ask peer sessions (ListAgents + SendMessage) to pause their input; tell them when you're done.
- Show Victor one clip before making a batch, and preview the page before pushing the website.

## Steps

1. Build the release first (the clip copy is made from `/Applications/Cra.app`, so install the
   new release there, or delete `build/clips/CraClip.app` to rebuild it from a newer copy).
2. Drive and record:

   ```sh
   source scripts/clips/clip.sh
   reset                                   # demo profile; WX WY = window origin (1100x700 pt)
   guard && rec dock 6 && glide w:300 m:$((WX+113)),$((WY+676)),800 w:450 d w:350 \
     m:$((WX+186)),$((WY+676)),1400 w:350 u; waitrec
   clip_quit
   ```

   - `cmd "cra://action/<id>"` runs any action (ids in Sources/Cra/App/KeyBindings.swift).
   - Plain keys: `key 36` (Return), `key 125`/`126` (arrows), `key 53` (Esc), typing with
     `cliclick -w 200 t:w t:e t:b`. ⌘ shortcuts: `cliclick kd:cmd t:t ku:cmd`.
   - Sidebar landmarks at the seeded size: space dock y = WY+676 (cells at WX+78/113/146/180),
     Library button WX+25, Studio header (WX+62, WY+172), tab rows from WY+418 down.
   - Check takes with `ffmpeg -i $R/x.mov -vf "fps=2,scale=440:-1,tile=5x4" -frames:v 1 t.png`.
3. Encode from the website repo, then paste the printed `media` entry into the highlight and
   write its `alt`:

   ```sh
   cd ../cra-website
   FPS=120 scripts/release-clip.sh 0.1.14 reorder-spaces "$R/dock.mov" 0.9 5.9
   # no CROP or DENSITY: the whole window at density 2 (CROP=2200:1400:x:y only to trim a border)
   ```
4. Preview with `next dev` (`/release-notes`), check the clip plays, then commit the website.

## Gotchas

- A CGEvent key-up that carries ⌘ leaves ⌘ latched (letters turn into shortcuts; a ⌘P once
  opened an invisible Print sheet that ate every key until relaunch). `waitrec` releases
  all modifiers.
- Reset before every take: a drag or a closed pane changes the profile.
- Cra redraws some drags at ~15 fps; that's the app, not the recording.
