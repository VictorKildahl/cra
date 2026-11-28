# Cra brand marks

Chosen 2026-10-24 from the layered explorations. The mark is built from translucent
ribbons that multiply where they overlap, wrapped in a white sticker edge.

| File | Use |
|---|---|
| `cra-segments.svg` | **Primary mark.** A C cut into four coloured segments. Transparent background: nav, documents, hero. |
| `cra-segments-mono.svg` | Single colour, inherits `currentColor`: footer, sidebar, favicons on busy backgrounds. |
| `cra-segments-icon.svg` | The Segments mark on a sand tile with a soft shadow. |

## App icons

Gilad S. designed Cra’s app icons. The [Segments](icons/segments/) and [Original](icons/original/) folders each
contain two 1024 × 1024 renders. `light.png` shows the Default appearance and `dark.png` shows the Dark appearance.
The apps use the shared [Segments document](../resources/AppIcon.icon/) and [alternate icon documents](../resources/app-icons/).

## Colours

| Layer | Hex | Where it lands in Segments |
|---|---|---|
| 1 | `#3f6df5` blue | top right, the opening of the C |
| 2 | `#4fbe7e` green | bottom left |
| 3 | `#f0574f` coral | top left |
| 4 | `#f6c34a` yellow | bottom right |
| Tile | `#f2e3c4` to `#e8d3aa` | the sand gradient behind the icon |

Ribbons are drawn at 92% opacity with `mix-blend-mode: multiply`, so overlaps go darker.
On dark backgrounds use normal blending (the site's `LogoMark` does this when `onDark` is set).

## Regenerating

The geometry lives in `website/src/components/site/brand-marks.ts`, written by the same
script that produced these files. Change the colours there and in this file together.
