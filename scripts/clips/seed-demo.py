"""seed-demo.py <data dir> [window frame]: writes the website's demo profile
(cra-website src/components/mockups/demo.ts) into a fresh CRA_DATA_DIR."""
import json, os, shutil, sys, uuid
from datetime import datetime, timezone

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
items, spaces, order = [], [], []

def U(): return str(uuid.uuid4()).upper()

def item(data, parent, title=None, children=None, iid=None):
    it = {"id": iid or U(), "parentID": parent, "children": children or [], "isUnread": False, "createdAt": now, "data": data}
    if title: it["title"] = title
    items.append(it)
    return it

def tab(url, title, parent):
    host = url.split("/")[2].removeprefix("www.")
    t = item({"tab": {"_0": {"url": url, "savedURL": url, "savedTitle": title, "muted": False, "faviconKey": host, "timeLastActiveAt": now}}}, parent, title)
    return t["id"]

def folder(title, parent, entries):
    f = item({"folder": {}}, parent, title)
    f["children"] = [tab(u, t, f["id"]) for u, t in entries]
    return f["id"]

def split(parent, entries):
    s = item({"split": {"_0": {"orientation": "horizontal", "timeLastActiveAt": now}}}, parent)
    s["children"] = [tab(u, t, s["id"]) for u, t in entries]
    return s["id"]

def space(title, emoji, theme, favs, pinned, today):
    sid = U()
    conts = {}
    for kind, entries in (("favorites", favs), ("pinned", pinned), ("today", today)):
        c = item({"container": {"_0": {kind: {"spaceID": sid}}}}, None)
        c["children"] = [e(c["id"]) if callable(e) else tab(e[0], e[1], c["id"]) for e in entries]
        conts[kind] = c["id"]
    spaces.append({"id": sid, "title": title, "emoji": emoji, "theme": theme, "createdAt": now,
                   "favoritesContainerID": conts["favorites"], "pinnedContainerID": conts["pinned"], "todayContainerID": conts["today"]})
    order.append(sid)

def theme(colors, intensity, noise, appearance): return {"colors": colors, "intensity": intensity, "noise": noise, "appearance": appearance, "vibrant": False}

space("Studio", "🎨", theme(["#C7CAFF", "#FFE5E5"], 0.5, 0.1, "light"),
      [("https://github.com/", "GitHub"), ("https://www.figma.com/", "Figma"), ("https://linear.app/", "Linear"), ("https://www.notion.com/", "Notion"),
       ("https://vercel.com/", "Vercel"), ("https://open.spotify.com/", "Spotify"), ("https://en.wikipedia.org/wiki/Main_Page", "Wikipedia"), ("https://www.apple.com/", "Apple")],
      [("https://crabrowser.app/", "Cra - Free, open-source Arc replacement for macOS"),
       lambda p: folder("Launch", p, [("https://github.com/VictorKildahl/cra", "VictorKildahl/cra"),
                                      ("https://developer.apple.com/documentation/swiftui", "SwiftUI | Apple Developer Documentation"),
                                      ("https://crabrowser.app/roadmap", "Roadmap")]),
       ("https://news.ycombinator.com/", "Hacker News"), ("https://www.are.na/", "Are.na"),
       lambda p: folder("Reading list", p, [("https://en.wikipedia.org/wiki/Typography", "Typography"), ("https://en.wikipedia.org/wiki/Color_theory", "Color theory")])],
      [lambda p: split(p, [("https://en.wikipedia.org/wiki/Web_browser", "Web browser"), ("https://linear.app/changelog", "Changelog – Linear")]),
       ("https://fonts.google.com/specimen/Instrument+Serif", "Instrument Serif – Google Fonts"), ("https://oklch.com/", "OKLCH Color Picker & Converter")])
space("Personal", "🌱", theme(["#1C242B", "#3A3660"], 0.85, 0.18, "dark"),
      [("https://www.youtube.com/", "YouTube"), ("https://open.spotify.com/", "Spotify"), ("https://en.wikipedia.org/wiki/Main_Page", "Wikipedia"), ("https://www.apple.com/", "Apple")],
      [("https://github.com/trending", "Trending repositories on GitHub"), ("https://news.ycombinator.com/", "Hacker News")],
      [("https://en.wikipedia.org/wiki/Copenhagen", "Copenhagen"), ("https://www.yr.no/en", "Yr")])
space("Weekend", "🏕️", theme(["#0F2420", "#2F6F5E"], 0.75, 0.18, "dark"),
      [("https://en.wikipedia.org/wiki/Main_Page", "Wikipedia"), ("https://www.apple.com/", "Apple")],
      [("https://en.wikipedia.org/wiki/Hiking", "Hiking")],
      [("https://en.wikipedia.org/wiki/Faroe_Islands", "Faroe Islands")])
space("Reading", "📚", theme(["#F4F1EA", "#E6DCC8"], 0.6, 0.15, "light"),
      [("https://www.gutenberg.org/", "Project Gutenberg")],
      [("https://en.wikipedia.org/wiki/Arc_(web_browser)", "Arc (web browser)")],
      [("https://en.wikipedia.org/wiki/Hypertext", "Hypertext")])

json.dump({"version": 1, "spaceOrder": order, "spaces": spaces, "items": items}, open(f"{out}/sidebar.json", "w"), indent=1)
json.dump({"hasSeenImportPrompt": True, "warnBeforeQuitting": False, "blockAdsAndTrackers": True, "toolbarDefaultMigrated": True,
           "showToolbar": True, "showStatusBar": True}, open(f"{out}/settings.json", "w"))
frame = sys.argv[2] if len(sys.argv) > 2 else "{{0, 0}, {1280, 800}}"
pick = lambda t: next(i["id"] for i in items if i.get("title") == t)
sel = [x for sid, t in zip(order, ["Cra - Free, open-source Arc replacement for macOS", "Copenhagen", "Faroe Islands", "Arc (web browser)"]) for x in (sid, pick(t))]
launch = next(i["id"] for i in items if i.get("title") == "Launch")
first_tab = next(i["id"] for i in items if i.get("title") == "Cra - Free, open-source Arc replacement for macOS")
json.dump({"littleWindowSize": "{780, 520}", "sidebarWidth": 260, "expandedFolders": [launch], "collapsedPinnedSpaces": [],
           "windows": [{"id": U(), "focusedSpaceID": order[0], "selectedTabPerSpace": sel, "frame": frame,
                        "sidebarVisible": True, "isIncognito": False}]}, open(f"{out}/windows.json", "w"))
fav = os.path.join(out, "Favicons"); os.makedirs(fav, exist_ok=True)
src = os.environ.get("CRA_WEBSITE", os.path.join(os.path.dirname(__file__), "../../../cra-website")) + "/public/mockups/favicons"
for name, host in {"github": "github.com", "figma": "figma.com", "linear": "linear.app", "notion": "notion.com", "vercel": "vercel.com",
                   "spotify": "open.spotify.com", "wikipedia": "en.wikipedia.org", "apple": "apple.com", "hackernews": "news.ycombinator.com", "arena": "are.na"}.items():
    shutil.copy(f"{src}/{name}.png", f"{fav}/{host}.png")
print(order[0])
