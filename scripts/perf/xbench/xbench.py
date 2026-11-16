#!/usr/bin/env python3
"""Cross-browser bench: one cold session of a browser, measured from outside the same way for every browser.

  xbench.py session <browser> <out-dir>       launch → window, idle/memory at 1/10/20 tabs, new tab → first paint,
                                              tab switch → shown, back to 1 tab, new window → on screen
  xbench.py speedometer <browser> <out-dir>   one Speedometer 3.1 run in a cold session
  xbench.py warm <browser>                    first launch on an empty profile, kept as the template every run clones

Every browser runs offline (network only to localhost, offline.sb) with Chromium's sandbox off (--no-sandbox: an
offline copy of Arc needs it, so all four get it), on a clone of its own template profile, and is driven by keyboard
events and Accessibility: ⌘T (⌘L for a browser that opens with a blank tab), the URL set into the focused field over
AX, Return. Pages come from a local server that logs what each page posts (first contentful paint, shown after a tab
switch). Idle CPU, wakeups and memory are the browser's whole process tree (build/perf/fp).
"""
import json, os, shutil, signal, subprocess, sys, time

HOME = os.path.expanduser("~")
B = os.environ.get("XBENCH_DIR", f"{HOME}/CraBench")
TOOLS = f"{B}/tools"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
FP = f"{REPO}/build/perf/fp"
SB = f"{B}/offline.sb"
WIN = (100, 60, 1440, 900)

BROWSERS = {
    # XBENCH_CRA_APP: another Cra build; XBENCH_CRA_ARGS: switches added to its command line (Cra passes
    # --enable-features/--disable-features lists through to the engine).
    "cra": dict(app=os.environ.get("XBENCH_CRA_APP", f"{B}/Cra.app/Contents/MacOS/Cra"),
                args=["--no-sandbox", *os.environ.get("XBENCH_CRA_ARGS", "").split()],
                env=lambda p: {"CRA_DATA_DIR": p, "CRA_SYNC_ICLOUD_DIR": p + "-sync"}, blank_tab=False),
    # An older Cra release, for "before and after" (README: Against an older Cra).
    "craold": dict(app=os.environ.get("XBENCH_CRA_OLD_APP", f"{B}/Cra-old.app/Contents/MacOS/Cra"), args=["--no-sandbox"],
                   env=lambda p: {"CRA_DATA_DIR": p, "CRA_SYNC_ICLOUD_DIR": p + "-sync"}, blank_tab=False),
    # Stock Google Chrome: a reference for Speedometer.
    "chrome": dict(app="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                   args=["--no-sandbox", "--no-first-run", "--no-default-browser-check"],
                   argsp=lambda p: [f"--user-data-dir={p}"], env=lambda p: {}, blank_tab=True),
    "helium": dict(app=f"{B}/Helium.app/Contents/MacOS/Helium",
                   args=["--no-sandbox", "--no-first-run", "--no-default-browser-check"],
                   argsp=lambda p: [f"--user-data-dir={p}"], env=lambda p: {}, blank_tab=True),
    "arc": dict(app="/Applications/Arc.app/Contents/MacOS/Arc", args=["--no-sandbox"],
                env=lambda p: {"CFFIXED_USER_HOME": p}, blank_tab=False),
    "dia": dict(app="/Applications/Dia.app/Contents/MacOS/Dia", args=["--no-sandbox"],
                env=lambda p: {"CFFIXED_USER_HOME": p}, blank_tab=True),
}


def now():
    return time.time() * 1000


def run(*cmd, timeout=60):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()


class Session:
    def __init__(self, name, out):
        self.name, self.b, self.out = name, BROWSERS[name], out
        os.makedirs(out, exist_ok=True)
        self.marks = f"{out}/marks.jsonl"
        open(self.marks, "w").close()
        self.result = {"browser": name}
        self.log = open(f"{out}/log.txt", "a")

    def note(self, *a):
        line = f"{time.strftime('%H:%M:%S')} " + " ".join(str(x) for x in a)
        print(line, flush=True)
        self.log.write(line + "\n"); self.log.flush()

    # --- server, profile, launch ---
    def start_server(self):
        port_file = f"{self.out}/port"
        self.server = subprocess.Popen(["python3", "-I", "-u", f"{REPO}/scripts/perf/server.py",
                                        f"{B}/pages", "0", self.marks], stdout=open(port_file, "w"), stderr=subprocess.DEVNULL)
        for _ in range(50):
            txt = open(port_file).read().strip()
            if txt:
                self.port = int(txt); return
            time.sleep(0.1)
        raise SystemExit("server didn't start")

    def profile(self):
        p = f"{B}/run-prof/{self.name}"
        if os.path.exists(p):
            shutil.rmtree(p)
        os.makedirs(f"{B}/run-prof", exist_ok=True)
        subprocess.run(["cp", "-c", "-R", f"{B}/tpl-{self.name}", p], check=True)
        for root, dirs, files in os.walk(p):
            for f in files:
                if f.startswith("Singleton"):
                    os.remove(os.path.join(root, f))
        if os.path.exists(p + "-sync"):
            shutil.rmtree(p + "-sync")
        return p

    def launch(self, prof):
        b = self.b
        env = dict(os.environ, **b["env"](prof))
        cmd = ["sandbox-exec", "-f", SB, b["app"], *b["args"], *(b.get("argsp", lambda p: [])(prof))]
        t0 = now()
        self.proc = subprocess.Popen(cmd, env=env, stdout=open(f"{self.out}/browser.log", "w"), stderr=subprocess.STDOUT)
        self.pid = self.proc.pid
        w = run(f"{TOOLS}/waitwin", f"{t0:.1f}", "40", str(self.pid), timeout=50)
        if not w:
            raise SystemExit(f"{self.name}: no window")
        self.result["launch_window_ms"] = float(w.split()[0])
        self.note("launch → window", w)

    def quit(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        for _ in range(100):
            if self.proc.poll() is not None:
                break
            time.sleep(0.1)
        if self.proc.poll() is None:
            self.proc.kill()
        time.sleep(1)
        # Helpers that outlive the browser (Cra's helpers don't carry the profile path).
        bundle = self.b["app"].split(".app/")[0] + ".app/"
        for line in run("ps", "-axo", "pid=,command=").splitlines():
            pid, _, cmd = line.strip().partition(" ")
            if f"{B}/run-prof/{self.name}" in cmd or (self.name.startswith("cra") and bundle in cmd):
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except Exception:
                    pass
        self.server.terminate()

    # --- driving ---
    def front(self):
        for _ in range(5):
            out = run(f"{TOOLS}/front", str(self.pid))
            if out.endswith("true"):
                return True
            time.sleep(0.5)
        raise SystemExit(f"{self.name}: can't bring it to the front")

    def key(self, *spec):
        self.front()
        return float(run(f"{TOOLS}/key", *spec))

    def size_window(self):
        x, y, w, h = WIN
        script = (f'tell application "System Events" to tell (first process whose unix id is {self.pid}) to '
                  f'set position of window 1 to {{{x}, {y}}}\n'
                  f'tell application "System Events" to tell (first process whose unix id is {self.pid}) to '
                  f'set size of window 1 to {{{w}, {h}}}')
        run("osascript", "-e", script)

    def tree(self):
        rows = [l.split() for l in run("ps", "-axo", "pid=,ppid=").splitlines()]
        out, frontier = {str(self.pid)}, [str(self.pid)]
        while frontier:
            x = frontier.pop()
            for r in rows:
                if len(r) == 2 and r[1] == x and r[0] not in out:
                    out.add(r[0]); frontier.append(r[0])
        return sorted(out)

    def click_window(self):
        """One click on the page area, so the window is key (an offline Arc's first window isn't)."""
        x, y, w, h = WIN
        self.front()
        run("cliclick", f"c:{x + w // 2 + 150},{y + h - 120}")
        time.sleep(0.5)

    def open_url(self, url, first=False):
        """⌘T (⌘L on a browser's first blank tab), URL over AX, Return. Returns the Return's time."""
        self.key("cmd+l" if first and self.b["blank_tab"] else "cmd+t")
        # All but the last character over AX, the last as a key: Arc's command bar updates its suggestions only on
        # typing, and Return on stale ones opens its first row instead of the URL. The field is read back before
        # Return (a bar still opening can drop what was set; Return then searched for the last character), and set
        # again if it doesn't hold the URL. What is measured starts at Return.
        for attempt in range(3):
            ok = run(f"{TOOLS}/axset", str(self.pid), url[:-1], "4")
            if not ok.startswith("AX"):
                self.note("axset failed", ok)
            self.key(f"text:{url[-1]}")
            time.sleep(0.6)
            shown = run(f"{TOOLS}/axget", str(self.pid)).strip()
            if shown == url or shown.endswith(url.split("://", 1)[-1]):
                break
            self.note("field holds", repr(shown[:80]), "- setting it again")
        if os.environ.get("XBENCH_SHOT"):
            subprocess.run(["screencapture", "-x", f"{self.out}/before-return.png"])
        return self.key("return")

    def page(self, n):
        return f"http://127.0.0.1:{self.port}/bench.html?n={n}"

    def read_marks(self):
        out = []
        for line in open(self.marks):
            try:
                out.append(json.loads(line))
            except Exception:
                pass
        return out

    def fcp(self, n, t, wait=8):
        end = time.time() + wait
        while time.time() < end:
            for m in self.read_marks():
                if m.get("kind") == "fcp" and m.get("n") == str(n):
                    return m["t"] - t
            time.sleep(0.1)
        return None

    # --- process tree measurements ---
    def fp(self):
        try:
            return json.loads(run(FP, str(self.pid)))
        except Exception:
            return None

    def idle(self, label, secs=20):
        a, ta = self.fp(), time.time()
        time.sleep(secs)
        b, tb = self.fp(), time.time()
        dt = tb - ta
        r = {"cpu_pct": 100 * (b["cpuNs"] - a["cpuNs"]) / 1e9 / dt, "wakeups_s": (b["wakeups"] - a["wakeups"]) / dt,
             "mem_mb": b["fpMB"], "procs": b["procs"]}
        self.result[label] = r
        self.note(label, json.dumps({k: round(v, 2) for k, v in r.items()}))
        return r

    # --- the session ---
    def session(self):
        self.start_server()
        self.launch(self.profile())
        time.sleep(4)
        self.size_window()
        time.sleep(1)
        self.click_window()
        t = self.open_url(self.page(1), first=True)
        self.result["first_tab_fcp_ms"] = self.fcp(1, t)
        loaded = time.time()
        time.sleep(5)
        self.idle("tab1")
        time.sleep(max(0, loaded + 90 - time.time()))
        self.idle("tab1_settled")
        new_tab = []
        for n in range(2, 11):
            t = self.open_url(self.page(n))
            f = self.fcp(n, t)
            if f is not None:
                new_tab.append(f)
            time.sleep(1.5)
        time.sleep(30)
        self.idle("tab10", secs=10)
        for n in range(11, 21):
            t = self.open_url(self.page(n))
            f = self.fcp(n, t)
            if f is not None:
                new_tab.append(f)
            time.sleep(1.5)
        self.result["new_tab_fcp_ms"] = new_tab
        self.note("new tab → fcp", [round(x, 1) for x in new_tab])
        loaded = time.time()
        time.sleep(5)
        self.idle("tab20")
        time.sleep(max(0, loaded + 90 - time.time()))
        self.idle("tab20_settled")
        presses = []
        for _ in range(10):
            presses.append(self.key("ctrl+tab"))
            time.sleep(1.2)
        time.sleep(1)
        shown = sorted(m["t"] for m in self.read_marks() if m.get("kind") == "shown")
        sw = []
        for p in presses:
            after = [s - p for s in shown if 0 <= s - p < 1000]
            if after:
                sw.append(min(after))
        self.result["tab_switch_shown_ms"] = sw
        self.note("tab switch → shown", [round(x, 1) for x in sw])
        for _ in range(19):
            self.key("cmd+w")
            time.sleep(0.4)
        time.sleep(30)
        self.idle("back1", secs=10)
        before = ",".join(l.split()[0] for l in run(f"{TOOLS}/wins", *self.tree()).splitlines())
        t = self.key("cmd+n")
        w = run(f"{TOOLS}/waitwin", f"{t:.1f}", "10", str(self.pid), f"ignore:{before}", timeout=20)
        self.result["new_window_ms"] = float(w.split()[0]) if w else None
        self.note("new window → on screen", w)
        time.sleep(2)
        run("screencapture", "-x", f"{self.out}/end.png")

    def smoke(self):
        self.start_server()
        self.launch(self.profile())
        time.sleep(4)
        self.size_window()
        time.sleep(1)
        self.click_window()
        for n in range(1, 4):
            t = self.open_url(self.page(n), first=(n == 1))
            self.note("tab", n, "fcp", self.fcp(n, t))
            time.sleep(1)
        presses = []
        for _ in range(6):
            presses.append(self.key("ctrl+tab"))
            time.sleep(1.2)
        time.sleep(1)
        shown = sorted(m["t"] for m in self.read_marks() if m.get("kind") == "shown")
        self.note("switches", [round(min([s - p for s in shown if 0 <= s - p < 1000] or [-1]), 1) for p in presses])
        for _ in range(2):
            self.key("cmd+w")
            time.sleep(0.4)
        before = ",".join(l.split()[0] for l in run(f"{TOOLS}/wins", *self.tree()).splitlines())
        t = self.key("cmd+n")
        self.note("new window", run(f"{TOOLS}/waitwin", f"{t:.1f}", "10", str(self.pid), f"ignore:{before}", timeout=20))
        time.sleep(1)
        run("screencapture", "-x", f"{self.out}/end.png")

    def speedometer(self):
        self.start_server()
        self.launch(self.profile())
        time.sleep(4)
        self.size_window()
        time.sleep(1)
        self.click_window()
        self.open_url(f"http://127.0.0.1:{self.port}/speedometer/index.html?startAutomatically=true", first=True)
        end = time.time() + 600
        while time.time() < end:
            sp = [m for m in self.read_marks() if m.get("kind") == "sp3"]
            if sp:
                self.result["speedometer"] = float(sp[0]["v"])
                self.note("speedometer", sp[0]["v"])
                break
            time.sleep(2)

    def probe(self):
        """One tab, settled: wakeups and CPU per process kind over 20 s (where a browser's idle goes)."""
        self.start_server()
        self.launch(self.profile())
        time.sleep(4)
        self.size_window()
        time.sleep(1)
        self.click_window()
        self.open_url(self.page(1), first=True)
        time.sleep(int(os.environ.get("XBENCH_SETTLE", "90")))
        a, ta = self.fp(), time.time()
        time.sleep(20)
        b, tb = self.fp(), time.time()
        dt = tb - ta
        rows = {k: {"wk_s": round((b["kindsWk"].get(k, 0) - a["kindsWk"].get(k, 0)) / dt, 1),
                    "cpu_pct": round(100 * (b["kindsCpuNs"].get(k, 0) - a["kindsCpuNs"].get(k, 0)) / 1e9 / dt, 2),
                    "mb": round(b["kindsMB"].get(k, 0), 1)}
                for k in b["kindsWk"]}
        self.result["probe"] = rows
        for k, v in sorted(rows.items(), key=lambda kv: -kv[1]["wk_s"]):
            self.note(k, json.dumps(v))
        procs = [l.split(None, 2) for l in run("ps", "-o", "pid=,rss=,command=", "-p", ",".join(self.tree())).splitlines()]
        for p in procs:
            fpj = run(FP, p[0], "--self") if os.environ.get("XBENCH_SELF") else ""
            self.note("proc", p[0], p[1], p[2][:160].replace(B, "~"), fpj[:80])
        if os.environ.get("XBENCH_HOLD"):
            open(f"{self.out}/pid", "w").write(str(self.pid))
            time.sleep(int(os.environ["XBENCH_HOLD"]))

    def warm(self):
        """First launch on an empty (or prepared) profile; what it leaves becomes the template."""
        self.start_server()
        p = f"{B}/run-prof/{self.name}"
        if os.path.exists(p):
            shutil.rmtree(p)
        src = f"{B}/tpl0-{self.name}"
        if os.path.exists(src):
            subprocess.run(["cp", "-c", "-R", src, p], check=True)
        else:
            os.makedirs(p)
        if self.name.startswith("cra"):
            json.dump({"hasSeenImportPrompt": True, "toolbarDefaultMigrated": True}, open(f"{p}/settings.json", "w"))
        self.launch(p)
        time.sleep(20)
        self.quit()
        tpl = f"{B}/tpl-{self.name}"
        if os.path.exists(tpl):
            shutil.rmtree(tpl)
        shutil.move(p, tpl)


def main():
    mode, name = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else f"{B}/warm-{name}"
    s = Session(name, out)
    try:
        getattr(s, mode)()
    finally:
        if mode != "warm":
            try:
                s.quit()
            except Exception as e:
                s.note("quit failed", e)
        json.dump(s.result, open(f"{out}/result.json", "w"), indent=1)


if __name__ == "__main__":
    main()
