#!/bin/bash
# prep.sh arc|dia: the offline copy's starting home ($XBENCH_DIR/tpl0-<browser>), from the account on this Mac,
# with nothing open: Arc's sidebar cut to the default space with its containers emptied and no sync state; Dia's
# profile without its tabs (tabs.db), pinned tabs (bookmarks), sessions, extensions, caches or queued sync.
# Both run with CFFIXED_USER_HOME on that home and no network but localhost, so nothing reaches the account.
# cfprefsd ignores the fake home: back up `defaults export company.thebrowser.Browser` (Arc) and
# `company.thebrowser.dia` (Dia) first and `defaults import` them after the bench.
set -euo pipefail
B="${XBENCH_DIR:-$HOME/CraBench}"
case "$1" in
arc)
  A="$B/tpl0-arc/Library/Application Support/Arc"; R="$HOME/Library/Application Support/Arc"
  rm -rf "$B/tpl0-arc"; mkdir -p "$A"
  for f in StorableAuthState StorableFeatureFlags StorableEducationState StorableMembershipCard \
           StorableDefaultBrowserPrompts StorableKeyBindings StorableWindows StorableHome; do cp "$R/$f.json" "$A/"; done
  python3 - "$R/StorableSidebar.json" "$A/StorableSidebar.json" "$A/StorableWindows.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c = d["sidebar"]["containers"][1]
sp, it = c["spaces"], c["items"]
i = sp.index("thebrowser.company.defaultPersonalSpaceID")
c["spaces"] = [sp[i], sp[i + 1]]
keep = {x for x in sp[i + 1]["containerIDs"] if isinstance(x, str)} | {x for x in c["topAppsContainerIDs"] if isinstance(x, str)}
items = []
for x in it:
    if isinstance(x, dict) and x["id"] in keep:
        x = dict(x); x["childrenIds"] = []; items += [x["id"], x]
c["items"] = items
d.pop("sidebarSyncState", None); d.pop("firebaseSyncState", None)
json.dump(d, open(sys.argv[2], "w"))
w = json.load(open(sys.argv[3]))
for win in w["windows"]:
    win["expandedItems"] = []; win["itemLastActiveDates"] = []; win["itemCreatedDates"] = []
json.dump(w, open(sys.argv[3], "w"))
PY
  ;;
dia)
  D="$B/tpl0-dia/Library/Application Support/Dia"; R="$HOME/Library/Application Support/Dia"
  rm -rf "$B/tpl0-dia"; mkdir -p "$D"
  cp -c "$R/StorableProfileContainers.json" "$R/BlockList.json" "$D/"; cp -c -R "$R/User Data" "$D/"
  for p in "$D/User Data"/Profile*; do
    rm -rf "$p"/{Sessions,Sessions_Encrypted,Extensions,"Local Extension Settings","Extension State","Extension Rules","Extension Scripts",Cache,"Code Cache","Service Worker",GPUCache,"Session Storage","Web Applications",Bookmarks,Bookmarks.bak,EncryptedBookmarks2,History,History-journal}
    rm -f "$p"/tabs.db* "$p"/sync_queue.db*
  done
  rm -rf "$D/User Data/Snapshots"
  ;;
esac
find "$B/tpl0-$1" -name 'Singleton*' -delete
echo "prepared $B/tpl0-$1"
