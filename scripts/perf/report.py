# report.py <run dir>...: scripts/perf/bench.sh runs as a table, the median (min–max) per build.
# Runs are grouped by name before the last "-": before-1, before-2 and after-1 give "before" and "after".
# Call a row different only when the ranges separate; overlapping ranges are noise (docs/speed.md).
import datetime, glob, json, os, statistics as st, sys


def load(root):
    out = {}
    idle = f"{root}/idle/result.jsonl"
    if os.path.exists(idle):
        res = {r["at"]: r for r in map(json.loads, open(idle))}

        def rate(k):
            a, b = res[f"{k}-start"], res[f"{k}-end"]
            dt = b["t"] - a["t"]
            return 100 * (b["m"]["cpuNs"] - a["m"]["cpuNs"]) / 1e9 / dt, (b["m"]["wakeups"] - a["m"]["wakeups"]) / dt

        for k in ["mem1", "mem10", "mem20", "mem20settled", "memback1"]:
            if k in res:
                out[f"memory {k[3:]} (MB)"] = res[k]["m"]["fpMB"]
        out["idle CPU 1 tab (%)"], out["idle wakeups 1 tab (/s)"] = rate("idle1")
        out["idle CPU 20 tabs (%)"], out["idle wakeups 20 tabs (/s)"] = rate("idle20")
    lat = f"{root}/latency"
    if os.path.exists(f"{lat}/hitch.log"):
        off = float(open(f"{lat}/clock-offset").read())
        marks = [json.loads(l) for l in open(f"{lat}/marks.jsonl")]
        hitch = [l.split(" ", 2) for l in open(f"{lat}/hitch.log") if " mark " in l]
        switches = [(float(t) + off) * 1000 for t, _, label in hitch if "nextTab" in label]
        opens = {label.split("n=")[-1].strip(): (float(t) + off) * 1000 for t, _, label in hitch if "cra://open" in label}
        shown = sorted(m["t"] for m in marks if m["kind"] == "shown")
        sw = [min(s for s in shown if s >= c) - c for c in switches if any(0 <= s - c < 1000 for s in shown)]
        fcp = [m["t"] - opens[m["n"]] for m in marks if m["kind"] == "fcp" and m["n"] in opens and m["n"] != "1"]
        if sw:
            out["tab switch → shown (ms)"] = st.median(sw)
        out["tab switches shown (of 16)"] = len(sw)
        if fcp:
            out["new tab → first paint (ms)"] = st.median(fcp)
    launch = f"{root}/launch"
    if os.path.exists(f"{launch}/hitch.log"):
        t0 = float(open(f"{launch}/t0").read())
        for line in open(glob.glob(f"{launch}/cra*.log")[0]):
            if " launch: opened" in line:
                at = datetime.datetime.strptime(line[:23], "%Y-%m-%d %H:%M:%S.%f").timestamp() * 1000
                out["start → window open (ms)"] = at - t0
                break
        off = float(open(f"{launch}/clock-offset").read())
        news = [(float(t) + off) * 1000 for t, _, label in
                (l.split(" ", 2) for l in open(f"{launch}/hitch.log") if " mark " in l) if "newWindow" in label]
        fcp = {m["n"]: m["t"] for m in map(json.loads, open(f"{launch}/marks.jsonl")) if m["kind"] == "fcp"}
        win = [fcp[f"w{i + 1}"] - t for i, t in enumerate(news) if f"w{i + 1}" in fcp]
        if win:
            out["new window → first paint (ms)"] = st.median(win)
    return out


groups = {}
for d in sys.argv[1:]:
    d = d.rstrip("/")
    groups.setdefault(os.path.basename(d).rsplit("-", 1)[0], []).append(load(d))
rows = sorted({k for runs in groups.values() for r in runs for k in r}, key=lambda k: (k.split(" ")[0], k))
print("| | " + " | ".join(groups) + " |")
print("|---|" + "---|" * len(groups))
for k in rows:
    cells = []
    for runs in groups.values():
        v = [r[k] for r in runs if k in r]
        cells.append(f"{st.median(v):.4g} ({min(v):.4g}–{max(v):.4g}, n={len(v)})" if v else "–")
    print(f"| {k} | " + " | ".join(cells) + " |")
