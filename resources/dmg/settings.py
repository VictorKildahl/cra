# dmgbuild settings for Cra.dmg, run by scripts/package.sh:
#   dmgbuild -s resources/dmg/settings.py -D app=build/Cra.app Cra build/dist/Cra.dmg
# The window mirrors Dia's installer: 800x400 pt, no chrome, 212 pt icons with the
# app on the left and Applications on the right of the chevron drawn into
# background.png (regenerate it with scripts/make-dmg-background.swift).
# Paths are relative to the repository root, where package.sh runs it.
import os.path

app = defines["app"]  # noqa: F821 (injected by dmgbuild)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
# The volume icon is the app's own .icns, which actool renders from resources/AppIcon.icon (scripts/build.sh).
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
background = "resources/dmg/background.png"

window_rect = ((110, 110), (800, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
arrange_by = None
label_pos = "bottom"
text_size = 16
icon_size = 212
icon_locations = {
    os.path.basename(app): (190, 180),
    "Applications": (610, 180),
}
