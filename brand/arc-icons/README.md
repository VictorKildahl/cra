# Arc's icon set, with Cra's C

Provok ([@provok_ch](https://x.com/provok_ch)) redrew Arc's alternate and channel icons around Cra's C in the
SVGs in this directory. The artwork comes from [mat-up/cra-icons](https://github.com/mat-up/cra-icons) at
3cf4b7d, under the MIT licence in [LICENSE](LICENSE).

Gilad S. designed Cra's native icons in Icon Composer. Mac and iOS share the Segments document in
`resources/AppIcon.icon` and the Original, Candy, Hologram, Neon, Fluted Glass, Schoolbook and Colorful
documents in `resources/app-icons/`.

Canary and Early Birds use these 1024 × 1024 SVGs on Apple's icon grid (the tile is 824 px, centred), with shadows,
blurs and glows as SVG filters. The Mac app uses 512 px PNGs of these two in `resources/app-icons/<id>.png`, listed in
`AppIconManager.presets` (Settings ▸ Icon). `swift scripts/make-arc-icons.swift [id …]` renders them (WebKit, at
512 px with their transparency).

The iPhone app has them too (`MobileAppIcon`, Settings ▸ App Icon): `swift scripts/make-arc-icons.swift --ios [id …]`
writes `iOS/Cra/Resources/Assets.xcassets/AppIcon-<Name>.appiconset` (1024 px, opaque) and its 512 px picture. For iOS
the tile's rounded outline becomes a square and the picture is the tile alone, since iOS rounds the corners itself.

Changed from Provok's originals (23 Nov 2026): the C is 10 % larger, scaled about its centre (500.5, 512) by a
`transform` on the group that holds its layers (in Fluted Glass, on each strip's copy of it), so its outline's outer
edge is as large as in Cra's own Segments and Midnight icons (271 × 310 px of a 411 px tile at 512 px; it was 246 ×
282). The tile, Hologram's frame, Neon's sparkles and Fluted Glass's strips are as drawn.
