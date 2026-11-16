#!/usr/bin/env python3
"""report.py [results-dir]: medians (with min–max) of every measurement per browser, as a table and results.json."""
import glob, json, os, statistics as st, sys

R = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("XBENCH_DIR", os.path.expanduser("~/CraBench")), "results")
NAMES = os.environ.get("XBENCH_NAMES", "cra helium arc dia").split()


def load(b):
    runs, sp = [], []
    for f in sorted(glob.glob(f"{R}/{b}-*/result.json")):
        d = json.load(open(f))
        if "tab_switch_shown_ms" in d:
            runs.append(d)
    for f in sorted(glob.glob(f"{R}/sp-{b}-*/result.json")):
        d = json.load(open(f))
        if "speedometer" in d:
            sp.append(d["speedometer"])
    return runs, sp


def metric(runs, get):
    vals = []
    for r in runs:
        try:
            v = get(r)
        except (KeyError, TypeError, st.StatisticsError):
            continue
        if v is not None:
            vals.append(v)
    if not vals:
        return None
    return {"median": st.median(vals), "min": min(vals), "max": max(vals), "n": len(vals)}


ROWS = [
    ("idle CPU, 1 tab (%)", lambda r: r["tab1"]["cpu_pct"]),
    ("idle CPU, 1 tab settled (%)", lambda r: r["tab1_settled"]["cpu_pct"]),
    ("idle CPU, 20 tabs (%)", lambda r: r["tab20"]["cpu_pct"]),
    ("idle CPU, 20 tabs settled (%)", lambda r: r["tab20_settled"]["cpu_pct"]),
    ("idle wakeups, 1 tab (/s)", lambda r: r["tab1"]["wakeups_s"]),
    ("idle wakeups, 1 tab settled (/s)", lambda r: r["tab1_settled"]["wakeups_s"]),
    ("idle wakeups, 20 tabs (/s)", lambda r: r["tab20"]["wakeups_s"]),
    ("idle wakeups, 20 tabs settled (/s)", lambda r: r["tab20_settled"]["wakeups_s"]),
    ("memory, 1 tab (MB)", lambda r: r["tab1_settled"]["mem_mb"]),
    ("memory, 10 tabs (MB)", lambda r: r["tab10"]["mem_mb"]),
    ("memory, 20 tabs (MB)", lambda r: r["tab20_settled"]["mem_mb"]),
    ("memory, back to 1 tab after 20 (MB)", lambda r: r["back1"]["mem_mb"]),
    ("cold launch → window on screen (ms)", lambda r: r["launch_window_ms"]),
    ("new window → on screen (ms)", lambda r: r["new_window_ms"]),
    ("new tab → first paint (ms)", lambda r: st.median(r["new_tab_fcp_ms"])),
    ("tab switch → shown (ms)", lambda r: st.median(r["tab_switch_shown_ms"])),
]

out, table = {}, []
data = {b: load(b) for b in NAMES}
for label, get in ROWS:
    out[label] = {b: metric(data[b][0], get) for b in NAMES}
out["Speedometer 3.1 (points, higher is better)"] = {
    b: ({"median": st.median(data[b][1]), "min": min(data[b][1]), "max": max(data[b][1]), "n": len(data[b][1])}
        if data[b][1] else None) for b in NAMES}

w = max(len(k) for k in out)
print(f"{'':{w}}  " + "  ".join(f"{b:>22}" for b in NAMES))
for label, row in out.items():
    cells = []
    for b in NAMES:
        m = row[b]
        cells.append(f"{m['median']:8.1f} ({m['min']:.1f}–{m['max']:.1f}, {m['n']})" if m else f"{'–':>22}")
    print(f"{label:{w}}  " + "  ".join(f"{c:>22}" for c in cells))
json.dump(out, open(f"{R}/results.json", "w"), indent=1)
