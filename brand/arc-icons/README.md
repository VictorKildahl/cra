# Arc's icon set, with Cra's C

Arc's alternate app icons (Original, Candy, Hologram, Neon, Fluted Glass, Schoolbook, Colorful, and its
Canary and Early Birds channel icons) redrawn around Cra's C by Provok ([@provok_ch](https://x.com/provok_ch)),
from [mat-up/cra-icons](https://github.com/mat-up/cra-icons) at 3cf4b7d, under the MIT licence in
[LICENSE](LICENSE).

These SVGs are the sources: 1024 × 1024, on Apple's icon grid (the tile is 824 px, centred), with shadows,
blurs and glows as SVG filters. The app uses 512 px PNGs of them in `resources/app-icons/<id>.png`, listed in
`AppIconManager.presets` (Settings ▸ Icon). `swift scripts/make-arc-icons.swift [id …]` renders them (WebKit, at
512 px with their transparency).

Changed from Provok's originals (23 Nov 2026): the C is 10 % larger, scaled about its centre (500.5, 512) by a
`transform` on the group that holds its layers (in Fluted Glass, on each strip's copy of it), so its outline's outer
edge is as large as in Cra's own Segments and Midnight icons (271 × 310 px of a 411 px tile at 512 px; it was 246 ×
282). The tile, Hologram's frame, Neon's sparkles and Fluted Glass's strips are as drawn.
