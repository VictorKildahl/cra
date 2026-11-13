# journeys.py <out dir>...: scripts/perf/journeys.sh runs per action kind: the time to the next
# "page-shown" mark and the main-thread stall time until the next action (sum and longest), median
# (min–max) over the actions of all the runs given, per run directory name before the last "-".
import os, re, statistics as st, sys
from collections import defaultdict

KINDS = [("tab switch", r"action/nextTab"), ("space switch", r"action/nextSpace"),
         ("sidebar toggle", r"action/toggleSidebar"), ("command bar key", r"commandbar\?query"),
         ("command bar close", r"cra://dismiss"), ("open site", r"cra://open\?url"),
         ("close tab", r"action/closeTab")]


def actions(path):
    lines = []
    for l in open(path):
        p = l.rstrip("\n").split(" ", 2)
        if len(p) == 3:
            lines.append((float(p[0]), p[1], p[2]))
    out = defaultdict(lambda: {"shown": [], "stall": [], "worst": []})
    marks = [(t, label) for t, kind, label in lines if kind == "mark"]
    cmds = [(t, label) for t, label in marks if label.startswith("cra://")]
    for i, (t, label) in enumerate(cmds):
        end = cmds[i + 1][0] if i + 1 < len(cmds) else t + 2
        kind = next((k for k, rx in KINDS if re.search(rx, label)), None)
        if not kind:
            continue
        stalls = [float(lab) for tt, k, lab in lines if k == "stall" and t <= tt < end]
        shown = [tt for tt, lab in marks if lab == "page-shown" and t <= tt < end]
        out[kind]["stall"].append(sum(stalls))
        out[kind]["worst"].append(max(stalls, default=0))
        if shown:
            out[kind]["shown"].append((shown[0] - t) * 1000)
    return out


groups = defaultdict(lambda: defaultdict(lambda: {"shown": [], "stall": [], "worst": []}))
for d in sys.argv[1:]:
    name = os.path.basename(d.rstrip("/")).rsplit("-", 1)[0]
    for kind, v in actions(os.path.join(d, "hitch.log")).items():
        for k in v:
            groups[name][kind][k] += v[k]


def cell(v):
    return f"{st.median(v):.0f} ({min(v):.0f}–{max(v):.0f}, n={len(v)})" if v else "–"


print("| action | " + " | ".join(f"{g}: to page shown (ms) | {g}: stalls (ms) | {g}: longest stall (ms)" for g in groups) + " |")
print("|---|" + "---|---|---|" * len(groups))
for kind, _ in KINDS:
    row = []
    for g in groups.values():
        v = g.get(kind, {"shown": [], "stall": [], "worst": []})
        row += [cell(v["shown"]), cell(v["stall"]), cell(v["worst"])]
    print(f"| {kind} | " + " | ".join(row) + " |")
